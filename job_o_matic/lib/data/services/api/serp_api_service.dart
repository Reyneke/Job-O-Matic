import 'dart:convert';
import 'package:logging/logging.dart';
import 'api_client.dart';
import 'api_key_service.dart';
import 'job_offer_mapper.dart';
import '../../models/job_offer.dart';

/// Service für die SerpAPI-Google-Jobs-Suche.
///
/// API-Dokumentation: https://serpapi.com/google-jobs-api
///
/// **Authentifizierung:**
/// - SerpAPI-Key erforderlich (kostenpflichtig, ab ~500 Requests/Monat)
/// - Key gespeichert via `ApiKeyService` (`serpApiKey`)
///
/// **Endpunkt:**
/// - `https://serpapi.com/search.json` mit `engine=google_jobs`
///
/// **Hinweis zur Einordnung im Job-O-Matic:**
/// Diese Quelle ist bewusst der **letzte Fallback** in der Kaskade
/// BA → Adzuna → SerpAPI und wird nur angefragt, wenn BA und Adzuna
/// zusammen keine (ausreichenden) Ergebnisse liefern. SerpAPI ist
/// **kostenpflichtig** – jeder Request verbraucht ein Kontingent und die
/// `google_jobs`-Antwort kann mehrere Sekunden dauern. Aus diesem Grund ist
/// SerpAPI **nicht** im Konnektivitäts-Test (`ApiConnectivityService`)
/// enthalten.
class SerpApiService {
  final Logger _log = Logger('SerpApiService');
  final ApiClient _client;
  final ApiKeyService _keyService;

  /// Injizierbarer Key-Loader für Tests; default: `_keyService.loadKey`.
  final Future<String?> Function()? _keyLoader;

  static const _baseUrl = 'serpapi.com';
  static const _searchPath = '/search.json';

  SerpApiService({
    required ApiClient client,
    required ApiKeyService keyService,
    Future<String?> Function()? keyLoader,
  })  : _client = client,
        _keyService = keyService,
        _keyLoader = keyLoader;

  /// Sucht Stellen über die SerpAPI-Google-Jobs-Suche.
  Future<List<JobOffer>> search({
    required String query,
    String? location,
    int radius = 25,
    EmploymentType? employmentType,
    int page = 1,
    int size = 20,
  }) async {
    final key = _keyLoader != null
        ? await _keyLoader()
        : await _keyService.loadKey(ApiKeyService.serpApiKey);

    if (key == null || key.isEmpty) {
      throw JobApiException(
        'SerpAPI-Key nicht konfiguriert. '
        'Bitte API-Key in den Einstellungen hinterlegen.',
      );
    }

    final params = <String, String>{
      'engine': 'google_jobs',
      'api_key': key,
      'q': query,
      // DE-Suche: deutsches Google-Domain + Sprache/Region.
      'google_domain': 'google.de',
      'gl': 'de',
      'hl': 'de',
    };

    if (location != null && location.isNotEmpty) {
      params['location'] = location;
    }

    final uri = Uri.https(_baseUrl, _searchPath, params);
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw JobApiException(
        'SerpAPI-API-Fehler',
        statusCode: response.statusCode,
        details: response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    // SerpAPI liefert API-Fehler als HTTP 200 mit einem `error`-Objekt.
    if (data['error'] != null) {
      throw JobApiException(
        'SerpAPI-API-Fehler',
        details: data['error'].toString(),
      );
    }

    final items = data['jobs_results'] as List<dynamic>? ?? [];
    return _parseJobOffers(items);
  }

  List<JobOffer> _parseJobOffers(List<dynamic> items) {
    final results = <JobOffer>[];

    for (final item in items) {
      try {
        final map = item as Map<String, dynamic>;
        final detected =
            map['detected_extensions'] as Map<String, dynamic>? ?? const {};
        final description = _buildDescription(map);

        results.add(JobOffer(
          id: (map['job_id'] ?? '').toString(),
          title: (map['title'] ?? 'Unbekannt') as String,
          company: (map['company_name'] ?? 'Unbekannt') as String,
          location: map['location'] as String?,
          description: description,
          // share_link = Google-Jobs-Tiefenlink zur Anzeige.
          url: (map['share_link'] ?? '') as String,
          salaryRange: _parseSalary(detected),
          employmentType: _employmentTypeFromSchedule(
            detected['schedule_type'] as String?,
          ),
          workModel: detected['work_from_home'] == true
              ? WorkModel.remote
              : JobOfferMapper.workModelFromDescription(description),
          publishedAt: null, // Kein zuverlässiges ISO-Datum in der Suche.
          source: 'serpapi',
        ));
      } catch (e) {
        _log.warning('Fehler beim Parsen eines SerpAPI-Jobs: $e');
      }
    }

    return results;
  }

  /// Kombiniert `description` und `job_highlights` zu einem Fließtext.
  String? _buildDescription(Map<String, dynamic> map) {
    final parts = <String>[];

    final desc = map['description'] as String?;
    if (desc != null && desc.trim().isNotEmpty) {
      parts.add(desc.trim());
    }

    final highlights = map['job_highlights'] as List<dynamic>? ?? [];
    for (final highlight in highlights) {
      final hm = highlight as Map<String, dynamic>?;
      if (hm == null) continue;
      final title = hm['title'] as String?;
      final items = (hm['items'] as List<dynamic>? ?? [])
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (items.isEmpty) continue;

      final header =
          (title != null && title.trim().isNotEmpty) ? '$title:\n' : '';
      parts.add('$header- ${items.join('\n- ')}');
    }

    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  /// Liest einen Gehaltstext aus `detected_extensions` (Key enthält „salary“),
  /// falls SerpAPI einen liefert. Sonst null.
  String? _parseSalary(Map<String, dynamic> detected) {
    for (final entry in detected.entries) {
      if (!entry.key.toLowerCase().contains('salary')) continue;
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num) {
        return JobOfferMapper.formatSalaryAmount(value);
      }
    }
    return null;
  }

  /// Mappt `detected_extensions.schedule_type` („Full-time“/„Part-time“ …)
  /// auf den [EmploymentType].
  EmploymentType? _employmentTypeFromSchedule(String? scheduleType) {
    if (scheduleType == null) return null;
    final s = scheduleType.toLowerCase();
    if (s.contains('part')) return EmploymentType.partTime;
    if (s.contains('full') || s.contains('contract')) {
      return EmploymentType.fullTime;
    }
    return null;
  }
}

