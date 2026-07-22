import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import '../../models/application.dart';
import '../../models/cv_data.dart';

/// Repository for managing job applications and CV data.
///
/// Acts as the central data store between screens. Uses Riverpod for
/// state management and notification.
class JobRepository {
  final Logger _log = Logger('JobRepository');

  /// List of validated job URLs (Screen 1 → Screen 3).
  final List<String> _validatedUrls = [];

  /// List of all applications.
  final List<Application> _applications = [];

  /// Loaded CV data.
  CvData? _cvData;

  /// Currently selected job IDs from search (Screen 2 → Screen 3).
  final List<String> _selectedJobIds = [];

  int _nextId = 1;

  // -- URL Management --

  /// Add validated URLs. Duplicates are ignored.
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
  }

  /// Get all validated URLs.
  List<String> get validatedUrls => List.unmodifiable(_validatedUrls);

  /// Remove a URL.
  void removeUrl(String url) {
    _validatedUrls.remove(url);
    _log.info('URL entfernt: $url');
  }

  /// Clear all URLs.
  void clearUrls() {
    _validatedUrls.clear();
    _log.info('Alle URLs gelöscht');
  }

  /// Whether valid applications exist in the repository.
  bool get hasValidApplications => _validatedUrls.isNotEmpty || _applications.isNotEmpty;

  // -- Application Management --

  /// Create applications from validated URLs.
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
    }
    _log.info('Applikationen erstellt: ${newApps.length}');
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

  /// Update an application's status.
  void updateApplicationStatus(int id, ApplicationStatus status,
      {String? pdfPath, String? errorMessage}) {
    final index = _applications.indexWhere((a) => a.id == id);
    if (index >= 0) {
      _applications[index] = _applications[index].copyWith(
        status: status,
        pdfPath: pdfPath ?? _applications[index].pdfPath,
        errorMessage: errorMessage ?? _applications[index].errorMessage,
        completedAt:
            status == ApplicationStatus.completed ? DateTime.now() : null,
      );
      _log.info('Applikation $id: Status -> ${status.displayName}');
    }
  }

  /// Remove an application.
  void removeApplication(int id) {
    _applications.removeWhere((a) => a.id == id);
    _log.info('Applikation $id entfernt');
  }

  // -- CV Data --

  /// Set CV data.
  void setCvData(CvData data) {
    _cvData = data;
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
    _log.info('Jobs aus Suche übernommen: $added (davon neu: $added von ${jobIds.length})');
  }

  /// Get selected job IDs.
  List<String> get selectedJobIds => List.unmodifiable(_selectedJobIds);

  // -- URL Normalization --

  String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      return uri.normalizePath().toString().toLowerCase();
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }
}

/// Riverpod provider for the JobRepository.
final jobRepositoryProvider = Provider<JobRepository>((ref) {
  return JobRepository();
});