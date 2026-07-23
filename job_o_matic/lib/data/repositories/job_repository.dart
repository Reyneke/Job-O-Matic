import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import '../../models/application.dart';
import '../../models/cv_data.dart';
import 'database_repository.dart';
import '../services/pdf/pdf_generator.dart';
import '../services/pdf/template_loader.dart';

/// Repository for managing job applications and CV data.
///
/// Acts as the central data store between screens. Uses Riverpod for
/// state management and notification. Now backed by SQLite database.
class JobRepository {
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
            );

  /// Initialize repository from database (load all persisted data).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _log.info('Initialisiere JobRepository aus Datenbank...');

    try {
      final results = await Future.wait([
        _dbRepo.loadApplications(),
        _dbRepo.loadValidatedUrls(),
        _dbRepo.loadCvData(),
      ]);

      _applications.addAll(results[0] as List<Application>);
      _validatedUrls.addAll(results[1] as List<String>);
      _cvData = results[2] as CvData?;

      _log.info('JobRepository initialisiert: '
          '${_applications.length} Applications, '
          '${_validatedUrls.length} URLs, '
          '${_cvData != null ? 'CV-Daten vorhanden' : 'keine CV-Daten'}');
    } catch (e) {
      _log.severe('Fehler bei JobRepository-Initialisierung: $e');
    }
  }

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
  }

  /// Clear all URLs.
  void clearUrls() {
    _validatedUrls.clear();
    _dbRepo.saveValidatedUrls([]);
    _log.info('Alle URLs gelöscht');
  }

  /// Whether valid applications exist in the repository.
  bool get hasValidApplications =>
      _validatedUrls.isNotEmpty || _applications.isNotEmpty;

  // -- Application Management --

  /// Create applications from validated URLs and persist them.
  List<Application> createApplicationsFromUrls() {
    final newApps = <Application>[];
    for (final url in _validatedUrls) {
      final app = Application(
        id: _nextId++,
        jobTitle: 'Unbekannte Stelle',
        company: 'Unbekanntes Unternehmen',
        jobUrl: url,
        createdAt: DateTime.now(),
      );
      _applications.add(app);
      newApps.add(app);

      // Persist to database
      _dbRepo.insertApplication(app);
    }
    _log.info('Applikationen erstellt: ${newApps.length}');

    // Clear validated URLs after creation
    _validatedUrls.clear();
    _dbRepo.saveValidatedUrls([]);

    return newApps;
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
    }
  }

  /// Remove an application.
  void removeApplication(int id) {
    _applications.removeWhere((a) => a.id == id);
    _dbRepo.deleteApplication(id);
    _log.info('Applikation $id entfernt');
  }

  /// Generate PDF for an application.
  Future<String> generatePdf(int applicationId) async {
    final app = getApplication(applicationId);
    if (app == null) {
      throw Exception('Application $applicationId nicht gefunden');
    }

    final cvData = _cvData;
    if (cvData == null) {
      throw Exception('CV-Daten nicht geladen');
    }

    updateApplicationStatus(applicationId, ApplicationStatus.processing);

    try {
      final pdfPath = await _pdfGenerator.generateApplicationPdf(
        application: app,
        cvData: cvData,
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
  }

  /// Get CV data.
  CvData? get cvData => _cvData;

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
  }

  /// Get selected job IDs.
  List<String> get selectedJobIds => List.unmodifiable(_selectedJobIds);

  // -- Internal --

  int _nextId = 1;

  String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      return uri.normalizePath().toString().toLowerCase();
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }
}

/// Riverpod provider for JobRepository.
final jobRepositoryProvider = Provider<JobRepository>((ref) {
  return JobRepository();
});