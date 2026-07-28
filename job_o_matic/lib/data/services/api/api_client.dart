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
  final ApiKeyService _keyService;

  ApiClient({
    required Logger logger,
    required this._keyService,
    http.Client? client,
    Duration? timeout,
  })  : _log = logger,
        _client = client ?? http.Client(),
        _timeout = timeout ?? defaultTimeout;

  /// HTTP-GET mit Retry-Logik.
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
    if (apiKeyName != null) {
      final key = await _keyService.loadKey(apiKeyName);
      if (key != null && key.isNotEmpty) {
        headers['X-API-Key'] = key;
      }
    }

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _log.fine('GET ${uri.toString()} (Versuch $attempt/$maxRetries)');
        final response = await _client
            .get(uri, headers: headers)
            .timeout(_timeout);

        if (response.statusCode == 429) {
          final retryAfter = Duration(seconds: 5 * attempt);
          _log.warning('Rate-Limited. Warte ${retryAfter.inSeconds}s...');
          await Future.delayed(retryAfter);
          continue;
        }

        _log.fine('Antwort ${response.statusCode} von $uri');
        return response;
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

  /// HTTP-POST mit Retry-Logik.
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

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _log.fine('POST ${uri.toString()} (Versuch $attempt/$maxRetries)');
        final response = await _client
            .post(uri, headers: defaultHeaders, body: body)
            .timeout(_timeout);

        if (response.statusCode == 429) {
          final retryAfter = Duration(seconds: 5 * attempt);
          _log.warning('Rate-Limited. Warte ${retryAfter.inSeconds}s...');
          await Future.delayed(retryAfter);
          continue;
        }

        _log.fine('Antwort ${response.statusCode} von $uri');
        return response;
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

  void dispose() {
    _client.close();
  }
}