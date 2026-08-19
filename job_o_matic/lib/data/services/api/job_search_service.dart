import 'dart:math';
import 'package:logging/logging.dart';
import 'ba_api_service.dart';
import 'adzuna_api_service.dart';
import 'api_cache_service.dart';
import '../../models/job_offer.dart';

/// Orchestriert die Jobsuche über mehrere Quellen.
///
/// Reihenfolge: BA → Adzuna (kaskadierend)
/// Ergebnisse werden dedupliziert und gecacht.
class JobSearchService {
  final Logger _log = Logger('JobSearchService');
  final BaApiService _baService;
  final AdzunaApiService? _adzunaService;
  final ApiCacheService? _cacheService;

  JobSearchService({
    required BaApiService baService,
    AdzunaApiService? adzunaService,
    ApiCacheService? cacheService,
  })  : _baService = baService,
        _adzunaService = adzunaService,
        _cacheService = cacheService;

  /// Sucht Jobs über alle verfügbaren Quellen.
  ///
  /// Returns a [JobSearchResult] with results and any error that occurred.
  /// If the primary source (BA) fails, Adzuna is used as fallback.
  /// Results are cached for 30 minutes to respect rate limits.
  Future<JobSearchResult> searchJobs({
    required String query,
    String? location,
    int radius = 25,
    EmploymentType? employmentType,
    WorkModel? workModel,
  }) async {
    // Cache-Key erstellen
    final cacheKey = _buildCacheKey(query, location, radius, employmentType, workModel);

    // Cache prüfen
    if (_cacheService != null) {
      final cached = _cacheService.get(cacheKey);
      if (cached != null) {
        _log.info('Gecachte Ergebnisse verwendet: ${cached.length} Jobs');
        return JobSearchResult(jobs: cached);
      }
    }

    final allResults = <JobOffer>[];
    final seenUrls = <String>{};
    String? errorMessage;

    // 1. Bundesagentur für Arbeit (primär)
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
      errorMessage = 'BA-API: ${e.message}'
          '${e.statusCode != null ? ' (HTTP ${e.statusCode})' : ''}'
          '${e.details != null && e.details!.isNotEmpty ? ' · ${e.details!.substring(0, min(200, e.details!.length))}' : ''}';
      _log.warning(errorMessage);
    } catch (e) {
      errorMessage = 'Netzwerkfehler bei der BA-API: $e';
      _log.warning(errorMessage);
    }

    // 2. Adzuna (sekundär) – falls BA wenig oder keine Ergebnisse liefert
    if (_adzunaService != null && allResults.length < 10) {
      try {
        final adzunaResults = await _adzunaService.search(
          query: query,
          location: location,
          radius: radius,
          employmentType: employmentType,
        );
        for (final job in adzunaResults) {
          if (seenUrls.add(job.url)) {
            allResults.add(job);
          }
        }
        _log.info('Adzuna: ${adzunaResults.length} Ergebnisse');
      } on JobApiException catch (e) {
        final adzunaError = 'Adzuna-API: ${e.message}'
            '${e.statusCode != null ? ' (HTTP ${e.statusCode})' : ''}';
        _log.warning(adzunaError);
        // Adzuna-Fehler nur melden, wenn BA auch fehlgeschlagen ist
        errorMessage ??= adzunaError;
      } catch (e) {
        _log.warning('Adzuna-API fehlgeschlagen: $e');
      }
    }

    // 3. Post-Filterung nach WorkModel (clientseitig)
    var filtered = _applyWorkModelFilter(allResults, workModel);

    // 4. Im Cache speichern
    if (_cacheService != null && filtered.isNotEmpty) {
      _cacheService.set(cacheKey, filtered);
    }

    _log.info(
        'Jobsuche abgeschlossen: ${filtered.length} Ergebnisse (nach Filter)');
    return JobSearchResult(
      jobs: filtered,
      errorMessage: filtered.isEmpty ? errorMessage : null,
    );
  }

  List<JobOffer> _applyWorkModelFilter(
      List<JobOffer> jobs, WorkModel? workModel) {
    if (workModel == null || workModel == WorkModel.any) return jobs;

    return jobs.where((job) {
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

  /// Erstellt einen eindeutigen Cache-Key aus den Suchparametern.
  String _buildCacheKey(
    String query,
    String? location,
    int radius,
    EmploymentType? employmentType,
    WorkModel? workModel,
  ) {
    return '${query}_${location ?? ''}_${radius}_'
        '${employmentType?.name ?? ''}_${workModel?.name ?? ''}';
  }
}

/// Result of a job search containing jobs and optional error information.
class JobSearchResult {
  final List<JobOffer> jobs;
  final String? errorMessage;

  const JobSearchResult({
    required this.jobs,
    this.errorMessage,
  });

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
  bool get isEmpty => jobs.isEmpty;
  bool get isSuccess => !hasError && jobs.isNotEmpty;
}