import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import '../../models/application.dart';
import '../../models/cv_data.dart';
import 'database_repository.dart';
import '../services/pdf/pdf_generator.dart';
import '../services/pdf/template_loader.dart';
import '../services/pdf/cover_page_generator.dart';
import '../services/pdf/cover_letter_generator.dart';
import '../services/pdf/cv_generator.dart';
import '../services/cv_data_parser.dart';
import '../services/api/job_scraper_service.dart';
import '../services/api/job_title_cleaner.dart';

/// Repository for managing job applications and CV data.
///
/// Acts as the central data store between screens. Uses Riverpod for
/// state management and notification. Now backed by SQLite database.
class JobRepository extends ChangeNotifier {
  final Logger _log = Logger('JobRepository');
  final DatabaseRepository _dbRepo;
  final PdfGenerator _pdfGenerator;

  /// List of validated job URLs (Screen 1 → Screen 3).
  final List<String> _validatedUrls = [];

  /// List of all applications.
  final List<Application> _applications = [];

  /// Loaded CV data.
  CvData? _cvData;

  /// Currently selected job IDs from search (Screen 2 → Screen 3).
  final List<String> _selectedJobIds = [];

  /// Auto-saved input text from the URL textarea (Screen 1).
  String? _autoSavedInput;

  /// Scraped job details for validated URLs (Screen 1 → Screen 3).
  final Map<String, JobScrapeResult> _scrapeResults = {};

  /// Whether the repository has been initialized from database.
  bool _initialized = false;

  JobRepository({
    DatabaseRepository? dbRepo,
    PdfGenerator? pdfGenerator,
  })  : _dbRepo = dbRepo ?? DatabaseRepository(),
        _pdfGenerator = pdfGenerator ??
            PdfGenerator(
              templateLoader: TemplateLoader(),
              templateRenderer: TemplateRenderer(),
              coverPageGenerator: CoverPageGenerator(),
              coverLetterGenerator: CoverLetterGenerator(),
              cvGenerator: CvGenerator(),
            );

  /// Initialize repository from database (load all persisted data).
  ///
  /// Should be called once at app startup, typically by the first screen
  /// that needs access to persisted data.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _log.info('Initialisiere JobRepository aus Datenbank...');

    try {
      final results = await Future.wait([
        _dbRepo.loadApplications(),
        _dbRepo.loadValidatedUrls(),
        _dbRepo.loadFilter('autosaved_input'),
      ]);

      _applications.addAll(results[0] as List<Application>);
      _validatedUrls.addAll(results[1] as List<String>);
      _autoSavedInput = results[2] as String?;

      _log.info('JobRepository initialisiert: '
          '${_applications.length} Applications, '
          '${_validatedUrls.length} URLs, '
          '${_cvData != null ? 'CV-Daten vorhanden' : 'keine CV-Daten'}');
      notifyListeners();
    } catch (e) {
      _log.severe('Fehler bei JobRepository-Initialisierung: $e');
    }
  }

  /// Returns whether the repository has been initialized.
  bool get isInitialized => _initialized;

  // -- URL Management --

  /// Add validated URLs. Duplicates are ignored. Auto-persists.
  void addValidatedUrls(List<String> urls) {
    final before = _validatedUrls.length;
    for (final url in urls) {
      final normalizedUrl = _normalizeUrl(url);
      if (!_validatedUrls.contains(normalizedUrl)) {
        _validatedUrls.add(normalizedUrl);
      }
    }
    final added = _validatedUrls.length - before;
    _log.info('URLs hinzugefügt: $added (neu) / ${urls.length} (eingegeben)');
    notifyListeners();

    // Auto-persist
    _dbRepo.saveValidatedUrls(_validatedUrls);
  }

  /// Get all validated URLs.
  List<String> get validatedUrls => List.unmodifiable(_validatedUrls);

  /// Remove a URL and persist.
  void removeUrl(String url) {
    _validatedUrls.remove(url);
    _dbRepo.saveValidatedUrls(_validatedUrls);
    _log.info('URL entfernt: $url');
    notifyListeners();
  }

  /// Clear all URLs.
  void clearUrls() {
    _validatedUrls.clear();
    _dbRepo.saveValidatedUrls([]);
    _log.info('Alle URLs gelöscht');
    notifyListeners();
  }

  /// Whether valid applications exist in the repository.
  bool get hasValidApplications =>
      _validatedUrls.isNotEmpty ||
      _applications.isNotEmpty ||
      _selectedJobIds.isNotEmpty;

  // -- Application Management --

  /// Speichert gescrapte Job-Details für validierte URLs.
  void saveScrapeResults(Map<String, JobScrapeResult> results) {
    _scrapeResults.addAll(results);
    _log.info('Scrape-Ergebnisse gespeichert: ${results.length}');
  }

  /// Create applications from validated URLs and persist them.
  /// Uses scraped job details (title, company, location) when available.
  List<Application> createApplicationsFromUrls() {
    final newApps = <Application>[];
    for (final url in _validatedUrls) {
      final scraped = _scrapeResults[url];
      final rawTitle = scraped?.title ?? '';
      final cleanedTitle = rawTitle.isEmpty
          ? 'Unbekannte Stelle'
          : JobTitleCleaner.cleanJobTitle(rawTitle);
      final app = _createAndInsert(
        jobTitle: cleanedTitle,
        company: scraped?.company ?? 'Unbekanntes Unternehmen',
        companyAddress: scraped?.companyAddress,
        jobUrl: url,
        jobDescription: scraped?.description,
      );
      newApps.add(app);
      _log.fine('Applikation aus URL erstellt: $url');
    }
    _log.info('Applikationen erstellt: ${newApps.length}');

    _validatedUrls.clear();
    _scrapeResults.clear();
    _dbRepo.saveValidatedUrls([]);

    if (newApps.isNotEmpty) notifyListeners();
    return newApps;
  }

  /// Create a single Application, insert into DB, return with DB-generated ID.
  Application _createAndInsert({
    required String jobTitle,
    required String company,
    required String jobUrl,
    String? companyAddress,
    String? jobDescription,
  }) {
    final now = DateTime.now();
    final app = Application(
      id: 0, // Placeholder — DB AUTOINCREMENT assigns real ID
      jobTitle: jobTitle,
      company: company,
      companyAddress: companyAddress,
      jobUrl: jobUrl,
      jobDescription: jobDescription,
      createdAt: now,
    );

    // Insert into DB and update the local copy with the real ID
    _dbRepo.insertApplication(app).then((dbId) {
      final index = _applications.indexWhere((a) =>
          a.id == 0 &&
          a.createdAt == now &&
          a.jobUrl == jobUrl);
      if (index >= 0) {
        final updated = _applications[index].copyWith(id: dbId);
        _applications[index] = updated;
      }
    });

    _applications.add(app);
    return app;
  }

  /// Get all applications.
  List<Application> get applications => List.unmodifiable(_applications);

  /// Get a single application by ID.
  Application? getApplication(int id) {
    try {
      return _applications.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Update an application's status and persist.
  void updateApplicationStatus(int id, ApplicationStatus status,
      {String? pdfPath, String? errorMessage}) {
    final index = _applications.indexWhere((a) => a.id == id);
    if (index >= 0) {
      final updated = _applications[index].copyWith(
        status: status,
        pdfPath: pdfPath ?? _applications[index].pdfPath,
        errorMessage: errorMessage ?? _applications[index].errorMessage,
        completedAt:
            status == ApplicationStatus.completed ? DateTime.now() : null,
      );
      _applications[index] = updated;
      _log.info('Applikation $id: Status -> ${status.displayName}');

      // Persist update
      _dbRepo.updateApplication(updated);
      notifyListeners();
    }
  }

  /// Directly add an application with job details (from search).
  void addApplication({
    required String jobTitle,
    required String company,
    String jobUrl = '',
  }) {
    _createAndInsert(
      jobTitle: jobTitle,
      company: company,
      jobUrl: jobUrl,
    );
    _log.info('Applikation hinzugefügt: $jobTitle bei $company');
    notifyListeners();
  }

  /// Remove an application.
  void removeApplication(int id) {
    _applications.removeWhere((a) => a.id == id);
    _dbRepo.deleteApplication(id);
    _log.info('Applikation $id entfernt');
    notifyListeners();
  }

  /// Load CV data from assets YAML file.
  ///
  /// The YAML file is the authoritative source of truth. It is always
  /// re-read to ensure the latest data is used, and the database cache
  /// is updated accordingly.
  Future<void> _ensureCvDataLoaded() async {
    _log.info('CV-Daten werden aus assets/mydata/cv/cv_data.yaml geladen...');
    try {
      final parser = CvDataParser();
      final result = await parser.loadFromAssets();
      if (result.isSuccess && result.data != null) {
        _cvData = result.data;
        _dbRepo.saveCvData(result.data!);
        _log.info('CV-Daten geladen für: ${result.data!.personalData.fullName}');
      } else {
        _log.warning('CV-Daten nicht geladen: ${result.errors.map((e) => e.message).join(", ")}');
      }
    } catch (e) {
      _log.severe('Fehler beim Laden der CV-Daten: $e');
    }
  }

  /// Generate PDF for an application.
  Future<String> generatePdf(int applicationId) async {
    final app = getApplication(applicationId);
    if (app == null) {
      throw Exception('Application $applicationId nicht gefunden');
    }

    // Auto-load CV data if not yet loaded
    await _ensureCvDataLoaded();

    if (_cvData == null) {
      throw Exception('CV-Daten konnten nicht geladen werden');
    }

    updateApplicationStatus(applicationId, ApplicationStatus.processing);

    try {
      final pdfPath = await _pdfGenerator.generateApplicationPdf(
        application: app,
        cvData: _cvData!,
      );
      updateApplicationStatus(
        applicationId,
        ApplicationStatus.completed,
        pdfPath: pdfPath,
      );
      return pdfPath;
    } catch (e) {
      updateApplicationStatus(
        applicationId,
        ApplicationStatus.failed,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  // -- CV Data --

  /// Set CV data and persist.
  void setCvData(CvData data) {
    _cvData = data;
    _dbRepo.saveCvData(data);
    _log.info('CV-Daten geladen für: ${data.personalData.fullName}');
    notifyListeners();
  }

  /// Get CV data.
  CvData? get cvData => _cvData;

  // -- Autosave (Screen 1) --

  /// Get last auto-saved input text.
  String? get autoSavedInput => _autoSavedInput;

  /// Save current input text for later restoration.
  void saveAutoSavedInput(String input) {
    _autoSavedInput = input;
    // Persist to database for survival across restarts
    _dbRepo.saveFilter('autosaved_input', input);
  }

  // -- Search (Screen 2) --

  /// Add job IDs from search results.
  void addJobsFromSearch(List<String> jobIds) {
    final before = _selectedJobIds.length;
    for (final id in jobIds) {
      if (!_selectedJobIds.contains(id)) {
        _selectedJobIds.add(id);
      }
    }
    final added = _selectedJobIds.length - before;
    _log.info(
        'Jobs aus Suche übernommen: $added (davon neu: $added von ${jobIds.length})');
    if (added > 0) notifyListeners();
  }

  /// Get selected job IDs.
  List<String> get selectedJobIds => List.unmodifiable(_selectedJobIds);

  /// Create applications from selected job IDs (from search).
  List<Application> createApplicationsFromSelectedJobs() {
    final newApps = <Application>[];
    final now = DateTime.now();
    for (final jobId in _selectedJobIds) {
      final app = Application(
        id: 0, // Placeholder — DB AUTOINCREMENT assigns real ID
        jobTitle: 'Stelle $jobId',
        company: 'Unbekanntes Unternehmen',
        jobUrl: '',
        createdAt: now,
      );
      _applications.add(app);
      newApps.add(app);
      _dbRepo.insertApplication(app).then((dbId) {
        final index = _applications.indexWhere((a) =>
            a.id == 0 &&
            a.createdAt == now &&
            a.jobTitle == 'Stelle $jobId');
        if (index >= 0) {
          _applications[index] = _applications[index].copyWith(id: dbId);
        }
      });
    }
    _log.info('Applikationen aus Jobsuche erstellt: ${newApps.length}');

    _selectedJobIds.clear();
    if (newApps.isNotEmpty) notifyListeners();
    return newApps;
  }

  /// Reset the repository for development/debugging.
  /// Clears all data and resets the database.
  Future<void> resetAllData() async {
    _log.info('Setze alle Daten zurück...');
    _applications.clear();
    _validatedUrls.clear();
    _selectedJobIds.clear();
    _cvData = null;
    _initialized = false;
    await _dbRepo.forceResetDatabase();
    _log.info('Alle Daten zurückgesetzt');
    notifyListeners();
  }

  /// Set all applications back to queued (for re-processing in debug mode).
  void resetAllToQueued() {
    for (int i = 0; i < _applications.length; i++) {
      final updated = _applications[i].copyWith(
        status: ApplicationStatus.queued,
        pdfPath: null,
        errorMessage: null,
        completedAt: null,
      );
      _applications[i] = updated;
      _dbRepo.updateApplication(updated);
    }
    _log.info('Alle Applikationen auf "wartend" zurückgesetzt');
    notifyListeners();
  }

  // -- Internal --

  String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      return uri.normalizePath().toString().toLowerCase();
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }
}

/// Riverpod provider for JobRepository as ChangeNotifier.
final jobRepositoryProvider = ChangeNotifierProvider<JobRepository>((ref) {
  return JobRepository();
});