import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'api_client.dart';
import 'api_key_service.dart';
import 'job_offer_mapper.dart';
import 'stable_hash.dart';
import '../../models/job_offer.dart';

/// Service für die Careerjet-Such-API.
///
/// API-Dokumentation: https://www.careerjet.com/partners/api/
///
/// **Authentifizierung:**
/// - Publisher-API-Key erforderlich (kostenlose Registrierung als Publisher)
/// - Key gespeichert via `ApiKeyService` (`careerjetApiKey`)
/// - Übertragen per HTTP **Basic Auth** (`Authorization: Basic base64("key:")`)
///
/// **Endpunkt:**
/// - `https://search.api.careerjet.net/v4/query`
///
/// **Besonderheiten:**
/// - Careerjet ist ein **Aggregator** (bündelt fremde Anzeigen) → überlappt mit
///   BA/Adzuna; in der Kaskade nur als **Lückenfüller** vor dem kostenpflichtigen
///   SerpAPI-Fallback sinnvoll (siehe `doc/plan/16-Jobsuche-BA.md`).
/// - Die Felder `user_ip` und `user_agent` sind **Pflicht**. `user_ip` wird über
///   einen einmaligen, kurz getakteten Abruf von `api.ipify.org` ermittelt und
///   pro Prozess gecacht (Fallback `0.0.0.0` bei Fehler). → Mit einem echten
///   Publisher-Key live verifizieren, ob Careerjet den Platzhalter akzeptiert.
/// - `url` ist ein Tracking-Redirect (`jobviewtrack.com`); die URL-Dedup
///   (`_normalizeUrlKey` in `JobSearchService`) normalisiert solche Links.
/// - Careerjet liefert **kein** Arbeitgeber-E-Mail-/Kontaktfeld → dieselbe
///   Kontakt-Kaskaden-Lücke wie bei der BA (`doc/plan/16`).
class CareerjetApiService {
  final Logger _log = Logger('CareerjetApiService');
  final ApiClient _client;
  final ApiKeyService _keyService;

  /// Injizierbarer Key-Loader für Tests; default: `_keyService.loadKey`.
  final Future<String?> Function()? _keyLoader;

  /// Injizierbarer Client für den (einmaligen) IP-Echo-Abruf; Tests nutzen
  /// einen MockClient. null → eigener [http.Client] mit kurzem Timeout.
  final http.Client? _ipClient;

  /// Gecachte öffentliche IP. Bewusst instanz- (statt statisch), damit Tests
  /// mit frischen Instanzen deterministisch sind. Da der Riverpod-Provider
  /// pro App-Lauf ein Singleton ist, entspricht das einer „pro Prozess“-Cache.
  String? _cachedIp;

  static const _baseUrl = 'search.api.careerjet.net';
  static const _queryPath = '/v4/query';
  static const _localeCode = 'de_DE';
  static const _ipEchoUrl = 'https://api.ipify.org/?format=json';
  static const _ipFallback = '0.0.0.0';

  CareerjetApiService({
    required ApiClient client,
    required ApiKeyService keyService,
    http.Client? ipClient,
    Future<String?> Function()? keyLoader,
  })  : _client = client,
        _keyService = keyService,
        _ipClient = ipClient,
        _keyLoader = keyLoader;

  /// Sucht Stellen über die Careerjet-API.
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
        : await _keyService.loadKey(ApiKeyService.careerjetApiKey);

    if (key == null || key.isEmpty) {
      throw JobApiException(
        'Careerjet-Key nicht konfiguriert. '
        'Bitte API-Key in den Einstellungen hinterlegen.',
      );
    }

    final userIp = await _resolveUserIp();

    final params = <String, String>{
      'locale_code': _localeCode,
      'keywords': query,
      'page': page.toString(),
      'pagesize': size.toString(),
      // Careerjet verlangt user_ip + user_agent pro Request (Pflicht).
      'user_ip': userIp,
      'user_agent': 'Job-O-Matic/1.0',
    };

    if (location != null && location.isNotEmpty) {
      params['location'] = location;
      params['radius'] = radius.toString();
    }

    // Basic Auth: base64("key:")
    final auth = 'Basic ${base64Encode(utf8.encode('$key:'))}';

    final uri = Uri.https(_baseUrl, _queryPath, params);
    final response = await _client.get(
      uri,
      extraHeaders: {'Authorization': auth},
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw JobApiException(
        'Careerjet: Zugriff verweigert (HTTP ${response.statusCode}). '
        'Publisher-Key prüfen oder „de_DE“-Abdeckung (bzw. freies Kontingent) '
        'verifizieren.',
        statusCode: response.statusCode,
        details: response.body,
      );
    }

    if (response.statusCode != 200) {
      throw JobApiException(
        'Careerjet-API-Fehler',
        statusCode: response.statusCode,
        details: response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    // "type": "LOCATIONS" (Orts-Mehrdeutigkeit) bzw. kein "jobs" → leer.
    final jobs = data['jobs'] as List<dynamic>?;
    if (jobs == null || jobs.isEmpty) return [];

    return _parseJobOffers(jobs);
  }

  List<JobOffer> _parseJobOffers(List<dynamic> items) {
    final results = <JobOffer>[];

    for (final item in items) {
      try {
        final map = item as Map<String, dynamic>;
        final url = _text(map['url']) ?? '';
        final title = _text(map['title']) ?? 'Unbekannt';
        final company = _company(map['company']) ?? 'Unbekannt';

        final description = _text(map['description']);

        final id = url.isNotEmpty
            ? fnv1a32(url).toString()
            : fnv1a32('$title|$company').toString();

        results.add(JobOffer(
          id: id,
          title: title,
          company: company,
          location: _locations(map['locations']),
          description: description,
          url: url,
          salaryRange: _salary(map),
          // Kein zuverlässiges Beschäftigungsart-Feld (Code-Ambivalenz) →
          // bewusst null (transparenter Filter lässt „nicht bewertbar“ durch).
          employmentType: null,
          workModel: JobOfferMapper.workModelFromDescription(description),
          publishedAt: null, // Careerjet-Datum ist RFC-1123, kein ISO.
          source: 'careerjet',
        ));
      } catch (e) {
        _log.warning('Fehler beim Parsen eines Careerjet-Jobs: $e');
      }
    }

    return results;
  }

  /// Ermittelt die öffentliche IP für das Pflichtfeld `user_ip`.
  ///
  /// Ein Abruf pro Prozess (Cache), kurzer Timeout, Fallback `0.0.0.0`. Tests
  /// können über einen injizierbaren [http.Client] ([_ipClient]) antworten.
  Future<String> _resolveUserIp() async {
    if (_cachedIp != null) return _cachedIp!;
    try {
      final client = _ipClient ?? http.Client();
      final response =
          await client.get(Uri.parse(_ipEchoUrl)).timeout(
                const Duration(seconds: 5),
              );
      if (_ipClient == null) client.close();
      if (response.statusCode == 200) {
        final ip = ((jsonDecode(response.body) as Map<String, dynamic>)['ip']
                as String?)
            ?.trim();
        if (ip != null && ip.isNotEmpty) {
          _cachedIp = ip;
          return ip;
        }
      }
    } catch (e) {
      _log.warning('Public-IP-Ermittlung fehlgeschlagen: $e');
    }
    return _ipFallback;
  }

  /// Extrahiert einen String (ggf. num → Text), sonst null.
  static String? _text(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final t = value.trim();
      return t.isEmpty ? null : t;
    }
    return value.toString();
  }

  /// Firmenname tolerant lesen: string ODER Objekt mit `display_name`/`name`.
  static String? _company(dynamic company) {
    if (company is String) return _text(company);
    if (company is Map) {
      return _text(company['display_name']) ?? _text(company['name']);
    }
    return null;
  }

  /// Orte tolerant lesen: string ODER Liste → mit ", " verbunden.
  static String? _locations(dynamic locations) {
    if (locations == null) return null;
    if (locations is String) return _text(locations);
    if (locations is List) {
      final parts = locations.map(_text).whereType<String>().toList();
      return parts.isEmpty ? null : parts.join(', ');
    }
    return null;
  }

  /// Gehalt: bevorzugt strukturierte Felder (`salary_min`/`salary_max` +
  /// Währung), sonst der Text (`salary`).
  static String? _salary(Map<String, dynamic> map) {
    final min = map['salary_min'];
    final max = map['salary_max'];
    final currency = (map['salary_currency_code'] ??
            map['salary_currency'] ??
            'EUR')
        .toString();

    if (min is num || max is num) {
      String format(dynamic v) => v is num
          ? JobOfferMapper.formatSalaryAmount(v)
          : (v?.toString() ?? '?');
      return '${format(min)} - ${format(max)} $currency';
    }

    final text = _text(map['salary']);
    if (text != null && text.trim().isNotEmpty) return text.trim();
    return null;
  }
}
