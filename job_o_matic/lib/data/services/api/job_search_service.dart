import 'dart:math';
import 'package:logging/logging.dart';
import 'ba_api_service.dart';
import 'adzuna_api_service.dart';
import 'serp_api_service.dart';
import 'api_cache_service.dart';
import 'job_offer_mapper.dart';
import '../../models/job_offer.dart';

/// Orchestriert die Jobsuche über mehrere Quellen.
///
/// Reihenfolge: BA → Adzuna → SerpAPI (kaskadierend)
/// Ergebnisse werden dedupliziert und gecacht.
class JobSearchService {
  final Logger _log = Logger('JobSearchService');
  final BaApiService _baService;
  final AdzunaApiService? _adzunaService;
  final SerpApiService? _serpService;
  final ApiCacheService? _cacheService;

  JobSearchService({
    required BaApiService baService,
    AdzunaApiService? adzunaService,
    SerpApiService? serpService,
    ApiCacheService? cacheService,
  })  : _baService = baService,
        _adzunaService = adzunaService,
        _serpService = serpService,
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
    int page = 1,
    int size = 20,
  }) async {
    // Cache-Key erstellen (inkl. Seite, damit jede Seite getrennt gecacht wird)
    final cacheKey =
        _buildCacheKey(query, location, radius, employmentType, workModel, page);

    // Cache prüfen
    if (_cacheService != null) {
      final cached = _cacheService.get(cacheKey);
      if (cached != null) {
        _log.info('Gecachte Ergebnisse verwendet: ${cached.length} Jobs');
        return JobSearchResult(jobs: cached);
      }
    }

    final allResults = <JobOffer>[];
    final seenKeys = <String>{};
    String? errorMessage;

    // 1. Bundesagentur für Arbeit (primär)
    try {
      final baResults = await _baService.search(
        query: query,
        location: location,
        radius: radius,
        employmentType: employmentType,
        page: page,
        size: size,
      );
      for (final job in baResults) {
        if (seenKeys.add(_dedupeKey(job))) {
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
          page: page,
          size: size,
        );
        for (final job in adzunaResults) {
          if (seenKeys.add(_dedupeKey(job))) {
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

    // 3. SerpAPI (letzter Fallback) – nur wenn BA + Adzuna zusammen zu wenig
    // Ergebnisse liefern. SerpAPI ist kostenpflichtig und langsam, daher
    // bewusst nicht als Parallel-/Default-Quelle, sondern als letzte Kaskade.
    if (_serpService != null && allResults.length < 10) {
      try {
        final serpResults = await _serpService.search(
          query: query,
          location: location,
          radius: radius,
          employmentType: employmentType,
          page: page,
          size: size,
        );
        for (final job in serpResults) {
          if (seenKeys.add(_dedupeKey(job))) {
            allResults.add(job);
          }
        }
        _log.info('SerpAPI: ${serpResults.length} Ergebnisse');
      } on JobApiException catch (e) {
        final serpError = 'SerpAPI-API: ${e.message}'
            '${e.statusCode != null ? ' (HTTP ${e.statusCode})' : ''}';
        _log.warning(serpError);
        errorMessage ??= serpError;
      } catch (e) {
        _log.warning('SerpAPI-API fehlgeschlagen: $e');
      }
    }

    // 4. Post-Filterung nach WorkModel (clientseitig)
    var filtered = _applyWorkModelFilter(allResults, workModel);

    // 5. Im Cache speichern – auch leere Ergebnisse mit kurzer TTL,
    // damit wiederholte Blind-Suchen nicht jedes Mal das Netz treffen
    // (Jobsuche-Rev, Punkt 7).
    if (_cacheService != null) {
      if (filtered.isEmpty) {
        _cacheService.set(
          cacheKey,
          filtered,
          ttl: const Duration(minutes: 5),
        );
        _log.fine('Leeres Ergebnis für "$cacheKey" gecacht (TTL 5 min).');
      } else {
        _cacheService.set(cacheKey, filtered);
      }
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
      // Bevorzugt das modellierte Feld; sonst beschreibungsbasiert ableiten.
      final detected = job.workModel ??
          JobOfferMapper.workModelFromDescription(job.description);

      // Nicht bewertbar (keine Angabe, z. B. BA-Listen-Response ohne
      // Beschreibung) → bewusst durchlassen (transparenter Filter,
      // Jobsuche-Rev Punkt 3). Keine versteckten Ausschlüsse.
      if (detected == null) return true;

      switch (workModel) {
        case WorkModel.remote:
          return detected == WorkModel.remote;
        case WorkModel.hybrid:
          return detected == WorkModel.hybrid;
        case WorkModel.onSite:
          return detected == WorkModel.onSite;
        default:
          return true;
      }
    }).toList();
  }

  /// Erstellt einen eindeutigen Cache-Key aus den Suchparametern.
  /// [page] ist Teil des Keys, damit jede Seite separat gecacht wird.
  String _buildCacheKey(
    String query,
    String? location,
    int radius,
    EmploymentType? employmentType,
    WorkModel? workModel,
    int page,
  ) {
    return '${query}_${location ?? ''}_${radius}_'
        '${employmentType?.name ?? ''}_${workModel?.name ?? ''}_p$page';
  }

  /// Deduplizierungs-Schlüssel für ein [JobOffer] (Jobsuche-Rev, „Normieren“).
  ///
  /// Bevorzugt die **normalisierte URL** (Tracking-Parameter/Query entfernt),
  /// damit dieselbe Stelle aus mehreren Quellen bzw. mit unterschiedlichen
  /// Tracking-Parametern nur einmal erscheint. Nur falls keine URL vorhanden
  /// ist, greift ein Inhalts-Fallback (Titel+Firma+Ort). Eine pauschale
  /// Inhalts-Deduplizierung über Portale hinweg ist bewusst **nicht** aktiv,
  /// um keine unterschiedlichen Jobs mit gleichem Titel/Firma/Ort fälschlich
  /// zu verschmelzen.
  String _dedupeKey(JobOffer job) {
    final normalizedUrl = _normalizeUrlKey(job.url);
    if (normalizedUrl.isNotEmpty) return 'url:$normalizedUrl';

    String norm(String? value) => value?.trim().toLowerCase() ?? '';
    return 'job:${norm(job.title)}|${norm(job.company)}|${norm(job.location)}';
  }

  /// Entfernt Query-/Fragment-Anteile (z. B. `?utm_source=…`) aus einer URL.
  String _normalizeUrlKey(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (uri.host.isEmpty) return url.trim().toLowerCase();
      return '${uri.scheme}://${uri.host}${uri.path}'.toLowerCase();
    } catch (_) {
      return url.trim().toLowerCase();
    }
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