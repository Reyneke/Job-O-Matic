import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'api_key_service.dart';

/// Ergebnis eines einzelnen Konnektivitäts-Checks.
enum ApiConnectivityStatus { notConfigured, ok, failed }

/// Einzelnes Testergebnis für einen Dienst.
class ApiConnectivityResult {
  final String serviceLabel;
  final ApiConnectivityStatus status;
  final String message;
  final Duration? latency;

  const ApiConnectivityResult({
    required this.serviceLabel,
    required this.status,
    required this.message,
    this.latency,
  });
}

/// Prüft die Konnektivität aller konfigurierten API-Dienste (Jobsuche-Rev).
///
/// Führt pro Dienst einen leichten HTTP-Request aus („Ping“-Endpunkte ohne
/// Seiteneffekte: `size=1`/`results_per_page=1` bzw. Metadaten-Endpunkte wie
/// `/account` oder `/models`). Ergebnis ist je Dienst eine
/// [ApiConnectivityResult]-Instanz für die UI im `ApiKeySettingsScreen`.
///
/// Der Dienst ist bewusst mit `http.Client` injizierbar, damit Unit-Tests
/// (MockClient) ohne echte Netzwerkzugriffe auskommen.
class ApiConnectivityService {
  final Logger _log = Logger('ApiConnectivityService');
  final ApiKeyService _keyService;

  /// Injizierbarer Key-Loader für Tests; default: `_keyService.loadKey`.
  final Future<String?> Function(String name)? _keyLoader;
  final http.Client _client;
  final Duration _timeout;

  /// Öffentlicher Standard-Key der BA-JOBBÖRSE (siehe BaApiService).
  static const String _baDefaultApiKey = 'jobboerse-jobsuche';

  static const String _baSearchPath = '/jobboerse/jobsuche-service/pc/v6/jobs';

  ApiConnectivityService({
    required ApiKeyService keyService,
    http.Client? client,
    Duration? timeout,
    Future<String?> Function(String name)? keyLoader,
  })  : _keyService = keyService,
        _keyLoader = keyLoader,
        _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 10);

  /// Lädt einen Key über den injizierten Loader oder den KeyService.
  Future<String?> _loadKey(String name) =>
      _keyLoader != null ? _keyLoader(name) : _keyService.loadKey(name);

  /// Führt alle Checks aus. Reihenfolge: BA → Adzuna → Brevo →
  /// Gemini → Mistral → Groq. SerpAPI ist bewusst nicht enthalten, da es
  /// kostenpflichtig ist und die echte Jobsuche nur als letzter Fallback dient.
  Future<List<ApiConnectivityResult>> checkAll() async {
    final results = <ApiConnectivityResult>[];
    results.add(await _checkBa());
    results.add(await _checkAdzuna());
    results.add(await _checkBrevo());
    results.add(await _checkGemini());
    results.add(await _checkMistral());
    results.add(await _checkGroq());
    return results;
  }

  Future<ApiConnectivityResult> _checkBa() async {
    // BA nutzt einen festen, öffentlichen Key (siehe BaApiService). Ein in den
    // Einstellungen gespeicherter BA-Key darf den funktionierenden Standard
    // NICHT überschreiben: Ein veralteter/falscher gespeicherter Wert würde
    // hier fälschlich HTTP 403 liefern, während die echte Suche (BaApiService)
    // weiterhin den Standard-Key nutzt und funktioniert. Deshalb wird bewusst
    // immer `_baDefaultApiKey` gesendet – inkl. User-Agent (Header-Parität mit
    // `ApiClient`), damit der Test exakt das abbildet, was die Suche tut.
    final uri = Uri.https(
      'rest.arbeitsagentur.de',
      _baSearchPath,
      {'was': 'Flutter', 'page': '1', 'size': '1'},
    );
    return _check(
      label: 'BA JOBBÖRSE',
      configured: true,
      uri: uri,
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'Job-O-Matic/1.0',
        'X-API-Key': _baDefaultApiKey,
      },
    );
  }

  Future<ApiConnectivityResult> _checkAdzuna() async {
    final appId = await _loadKey(ApiKeyService.adzunaAppId);
    final apiKey = await _loadKey(ApiKeyService.adzunaApiKey);
    if (appId == null ||
        appId.isEmpty ||
        apiKey == null ||
        apiKey.isEmpty) {
      return ApiConnectivityResult(
        serviceLabel: 'Adzuna',
        status: ApiConnectivityStatus.notConfigured,
        message: 'App-ID und/oder API-Key fehlen.',
      );
    }

    // Markt/Land über denselben injizierbaren Loader wie die Keys laden
    // (Default `de`), damit der Test den Request exakt wie die Suche abbildet.
    final countryRaw = await _loadKey(ApiKeyService.adzunaCountry);
    final country = (countryRaw == null || countryRaw.trim().isEmpty)
        ? 'de'
        : countryRaw.trim().toLowerCase();

    return _check(
      label: 'Adzuna',
      configured: true,
      uri: Uri.https(
        'api.adzuna.com',
        '/v1/api/jobs/$country/search/1',
        {
          'app_id': appId,
          'app_key': apiKey,
          'what': 'Flutter',
          'results_per_page': '1',
        },
      ),
    );
  }

  Future<ApiConnectivityResult> _checkBrevo() async {
    final key = await _loadKey(ApiKeyService.brevoApiKey);
    if (key == null || key.isEmpty) {
      return ApiConnectivityResult(
        serviceLabel: 'Brevo (E-Mail)',
        status: ApiConnectivityStatus.notConfigured,
        message: 'API-Key fehlt.',
      );
    }
    return _check(
      label: 'Brevo (E-Mail)',
      configured: true,
      uri: Uri.https('api.brevo.com', '/v3/account'),
      headers: {'api-key': key, 'Accept': 'application/json'},
    );
  }

  Future<ApiConnectivityResult> _checkGemini() async {
    final key = await _loadKey(ApiKeyService.geminiApiKey);
    if (key == null || key.isEmpty) {
      return ApiConnectivityResult(
        serviceLabel: 'Gemini (KI)',
        status: ApiConnectivityStatus.notConfigured,
        message: 'API-Key fehlt.',
      );
    }
    return _check(
      label: 'Gemini (KI)',
      configured: true,
      uri: Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models',
        {'key': key},
      ),
    );
  }

  Future<ApiConnectivityResult> _checkMistral() async {
    final key = await _loadKey(ApiKeyService.mistralApiKey);
    if (key == null || key.isEmpty) {
      return ApiConnectivityResult(
        serviceLabel: 'Mistral (KI)',
        status: ApiConnectivityStatus.notConfigured,
        message: 'API-Key fehlt.',
      );
    }
    return _check(
      label: 'Mistral (KI)',
      configured: true,
      uri: Uri.https('api.mistral.ai', '/v1/models'),
      headers: {'Authorization': 'Bearer $key', 'Accept': 'application/json'},
    );
  }

  Future<ApiConnectivityResult> _checkGroq() async {
    final key = await _loadKey(ApiKeyService.groqApiKey);
    if (key == null || key.isEmpty) {
      return ApiConnectivityResult(
        serviceLabel: 'Groq (KI)',
        status: ApiConnectivityStatus.notConfigured,
        message: 'API-Key fehlt.',
      );
    }
    return _check(
      label: 'Groq (KI)',
      configured: true,
      uri: Uri.https('api.groq.com', '/openai/v1/models'),
      headers: {'Authorization': 'Bearer $key', 'Accept': 'application/json'},
    );
  }

  /// Führt einen einzelnen HTTP-Check aus und klassifiziert das Ergebnis.
  Future<ApiConnectivityResult> _check({
    required String label,
    required bool configured,
    required Uri uri,
    Map<String, String> headers = const {},
  }) async {
    if (!configured) {
      return ApiConnectivityResult(
        serviceLabel: label,
        status: ApiConnectivityStatus.notConfigured,
        message: 'Nicht konfiguriert.',
      );
    }

    final stopwatch = Stopwatch()..start();
    http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      stopwatch.stop();
      _log.warning(
          'Connectivity-Check $label: Timeout nach ${_timeout.inSeconds}s');
      return ApiConnectivityResult(
        serviceLabel: label,
        status: ApiConnectivityStatus.failed,
        message: 'Timeout (${_timeout.inSeconds}s).',
        latency: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      _log.warning('Connectivity-Check $label fehlgeschlagen: $e');
      return ApiConnectivityResult(
        serviceLabel: label,
        status: ApiConnectivityStatus.failed,
        message: 'Nicht erreichbar ($e).',
        latency: stopwatch.elapsed,
      );
    }

    stopwatch.stop();
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    _log.fine('Connectivity-Check $label: HTTP ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds} ms)');
    return ApiConnectivityResult(
      serviceLabel: label,
      status: ok ? ApiConnectivityStatus.ok : ApiConnectivityStatus.failed,
      message: ok
          ? 'Erreichbar (HTTP ${response.statusCode}).'
          : 'Fehler (HTTP ${response.statusCode}).',
      latency: stopwatch.elapsed,
    );
  }
}