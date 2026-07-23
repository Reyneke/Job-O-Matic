import 'package:logging/logging.dart';
import 'ba_api_service.dart';
import '../../models/job_offer.dart';

/// Orchestriert die Jobsuche über mehrere Quellen.
///
/// Reihenfolge: BA → (zukünftig) Adzuna → SerpAPI (kaskadierend)
/// Ergebnisse werden dedupliziert.
class JobSearchService {
  final Logger _log = Logger('JobSearchService');
  final BaApiService _baService;

  JobSearchService({
    required BaApiService baService,
  }) : _baService = baService;

  /// Sucht Jobs über alle verfügbaren Quellen.
  Future<List<JobOffer>> searchJobs({
    required String query,
    String? location,
    int radius = 25,
    EmploymentType? employmentType,
    WorkModel? workModel,
  }) async {
    final allResults = <JobOffer>[];
    final seenUrls = <String>{};

    // 1. Bundesagentur für Arbeit
    try {
      final baResults = await _baService.search(
        query: query,
        location: location,
        radius: radius,
        employmentType: employmentType,
      );
      for (final job in baResults) {
        if (seenUrls.add(job.url)) {
          allResults.add(job);
        }
      }
      _log.info('BA: ${baResults.length} Ergebnisse');
    } on JobApiException catch (e) {
      _log.warning('BA-API fehlgeschlagen: ${e.message}');
    }

    // 2. Post-Filterung nach WorkModel (clientseitig)
    var filtered = _applyWorkModelFilter(allResults, workModel);

    _log.info(
        'Jobsuche abgeschlossen: ${filtered.length} Ergebnisse (nach Filter)');
    return filtered;
  }

  List<JobOffer> _applyWorkModelFilter(
      List<JobOffer> jobs, WorkModel? workModel) {
    if (workModel == null || workModel == WorkModel.any) return jobs;

    return jobs.where((job) {
      // Post-Filter: Schlüsselwörter in der Beschreibung suchen
      if (job.description == null) return true;
      final desc = job.description!.toLowerCase();

      switch (workModel) {
        case WorkModel.remote:
          return desc.contains('remote') ||
              desc.contains('homeoffice') ||
              desc.contains('mobile work');
        case WorkModel.hybrid:
          return desc.contains('hybrid') || desc.contains('flexibel');
        case WorkModel.onSite:
          return desc.contains('vor ort') || desc.contains('präsenz');
        default:
          return true;
      }
    }).toList();
  }
}