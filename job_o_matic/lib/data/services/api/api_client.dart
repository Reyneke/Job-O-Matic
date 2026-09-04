import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import '../../models/job_offer.dart';
import 'api_key_service.dart';

/// Zentrale HTTP-Client-Klasse für alle API-Anfragen.
///
/// Features:
/// - Automatisches Retry mit exponentiellem Backoff
/// - Einheitliches Logging
/// - API-Key-Management (via ApiKeyService)
/// - Timeout-Konfiguration
class ApiClient {
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const int maxRetries = 3;

  final Logger _log;
  final http.Client _client;
  final Duration _timeout;
  final ApiKeyService? _keyService;

  ApiClient({
    required Logger logger,
    ApiKeyService? keyService,
    http.Client? client,
    Duration? timeout,
  })  : _log = logger,
        _client = client ?? http.Client(),
        _timeout = timeout ?? defaultTimeout,
        _keyService = keyService;

  /// HTTP-GET mit Retry-Logik (gemeinsamer Retry-Kern, Jobsuche-Rev Pkt. 4–5).
  Future<http.Response> get(
    Uri uri, {
    String? apiKeyName,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'User-Agent': 'Job-O-Matic/1.0',
      ...?extraHeaders,
    };

    // API-Key automatisch laden, wenn angefordert
    if (apiKeyName != null && _keyService != null) {
      final key = await _keyService.loadKey(apiKeyName);
      if (key != null && key.isNotEmpty) {
        headers['X-API-Key'] = key;
      }
    }

    return _performWithRetry(() => _client.get(uri, headers: headers), uri);
  }

  /// HTTP-POST mit Retry-Logik (gemeinsamer Retry-Kern, Jobsuche-Rev Pkt. 4–5).
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final defaultHeaders = <String, String>{
      'User-Agent': 'Job-O-Matic/1.0',
      'Content-Type': 'application/json',
      ...?headers,
    };

    return _performWithRetry(
      () => _client.post(uri, headers: defaultHeaders, body: body),
      uri,
    );
  }

  /// Gemeinsamer Retry-/429-/Timeout-Kern für GET und POST (Jobsuche-Rev 4–5).
  ///
  /// - HTTP 429 (Rate-Limit): nach `Retry-After`-Header warten, Fallback
  ///   `5s × Versuch`.
  /// - [TimeoutException]: Backoff `2s × Versuch`, dann erneut.
  /// - Andere Fehler werden sofort weitergereicht (wie zuvor, keine
  ///   versteckten Retries auf nicht-idempotente/sonstige Fehler).
  Future<http.Response> _performWithRetry(
    Future<http.Response> Function() send,
    Uri uri,
  ) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _log.fine('Request ${uri.toString()} (Versuch $attempt/$maxRetries)');
        final response = await send().timeout(_timeout);

        if (response.statusCode != 429) {
          _log.fine('Antwort ${response.statusCode} von $uri');
          return response;
        }

        final wait = _retryAfter(response) ?? Duration(seconds: 5 * attempt);
        _log.warning(
            'Rate-Limited (HTTP 429). Warte ${wait.inSeconds}s '
            '(Versuch $attempt/$maxRetries)...');
        await Future.delayed(wait);
      } on TimeoutException {
        _log.warning('Timeout für $uri (Versuch $attempt/$maxRetries)');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * attempt));
        }
      } catch (e, stack) {
        _log.severe('Fehler bei API-Anfrage: $e', e, stack);
        rethrow;
      }
    }

    throw JobApiException(
      'Maximale Anzahl Versuche ($maxRetries) überschritten',
    );
  }

  /// Liest den `Retry-After`-Header eines 429-Response: entweder Sekunden
  /// oder ein HTTP-Datum. Null, wenn der Header fehlt oder unlesbar ist.
  Duration? _retryAfter(http.Response response) {
    final value = response.headers['retry-after'];
    if (value == null || value.isEmpty) return null;
    final trimmed = value.trim();

    final seconds = int.tryParse(trimmed);
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }

    final date = DateTime.tryParse(trimmed);
    if (date != null) {
      final diff = date.difference(DateTime.now());
      return diff.isNegative ? Duration.zero : diff;
    }
    return null;
  }

  void dispose() {
    _client.close();
  }
}