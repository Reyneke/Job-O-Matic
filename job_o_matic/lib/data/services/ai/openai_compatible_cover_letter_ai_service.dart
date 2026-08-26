import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../../models/application.dart';
import '../../../models/cv_data.dart';
import '../api/api_client.dart';
import 'cover_letter_ai_service.dart';
import 'cover_letter_prompt_builder.dart';
import 'cover_letter_sanitizer.dart';

/// Basis-Klasse für KI-Anbieter mit **OpenAI-kompatibler Chat-API**.
///
/// Mistral und Groq (sowie viele weitere Anbieter) verwenden dasselbe
/// Schema:
/// - `POST https://{host}{path}`
/// - Header: `Authorization: Bearer {key}`
/// - Body: `{model, messages, temperature, max_tokens}`
/// - Antwort: `choices[0].message.content`
///
/// Dadurch genügt einer Unterklasse die Angabe von Host, Pfad und
/// Standardmodell (siehe [MistralCoverLetterAiService] und
/// [GroqCoverLetterAiService]).
abstract class OpenAiCompatibleCoverLetterAiService
    implements CoverLetterAiService {
  static const Duration defaultTimeout = Duration(seconds: 90);

  /// Mindestlänge der bereinigten Antwort, darunter gilt sie als kaputt.
  static const int minResponseLength = 50;

  final Logger _log;
  final ApiClient _apiClient;
  final AiApiKeyLoader _loadApiKey;
  final String? _explicitModel;
  final String _host;
  final String _path;

  /// Effektives Modell: explizit gesetzt oder Anbieter-Standard.
  String get _model => _explicitModel ?? fallbackModel;

  /// Menschenlesbarer Anbietername ohne Modell (z. B. "Mistral").
  String get providerLabel;

  /// Vom Anbieter empfohlenes Standardmodell.
  String get fallbackModel;

  OpenAiCompatibleCoverLetterAiService({
    required String host,
    required String path,
    Logger? logger,
    AiApiKeyLoader? apiKeyLoader,
    http.Client? client,
    Duration? timeout,
    String? model,
  })  : _log = logger ?? Logger('OpenAiCompatibleCoverLetterAiService'),
        _loadApiKey = apiKeyLoader ?? (() async => null),
        _explicitModel = model,
        _host = host,
        _path = path,
        _apiClient = ApiClient(
          logger: logger ?? Logger('OpenAiCompatibleCoverLetterAiService'),
          client: client,
          // LLM-Antworten brauchen länger als klassische REST-Calls
          timeout: timeout ?? defaultTimeout,
        );

  @override
  String get providerName => '$providerLabel ($_model)';

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw CoverLetterAiException(
        'Kein $providerLabel-API-Key konfiguriert. Bitte in den Einstellungen '
        '(API-Keys) hinterlegen.',
      );
    }

    final uri = Uri.https(_host, _path);
    final response = await _apiClient.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {
            'role': 'user',
            'content': CoverLetterPromptBuilder.build(cvData, application),
          },
        ],
        'temperature': CoverLetterPromptBuilder.temperature,
        'max_tokens': CoverLetterPromptBuilder.maxOutputTokens,
      }),
    );

    if (response.statusCode != 200) {
      throw CoverLetterAiException(
        '$providerLabel-API-Fehler (HTTP ${response.statusCode})',
        cause: response.body.length > 500
            ? '${response.body.substring(0, 500)}…'
            : response.body,
      );
    }

    final rawText = _extractText(response.body);
    if (rawText == null || rawText.trim().isEmpty) {
      throw CoverLetterAiException(
          '$providerLabel lieferte keinen Text.');
    }

    final sanitized = CoverLetterSanitizer.sanitize(rawText);
    if (sanitized.length < minResponseLength) {
      throw CoverLetterAiException(
        '$providerLabel-Antwort zu kurz/unbrauchbar '
        '(${sanitized.length} Zeichen).',
        cause: rawText,
      );
    }

    _log.info(
        'Anschreiben generiert (${sanitized.length} Zeichen, $providerName)');
    return sanitized;
  }

  /// Extrahiert den Text aus der OpenAI-kompatiblen Response-Struktur:
  /// `choices[0].message.content`
  String? _extractText(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>? ?? [];
      if (choices.isEmpty) {
        _log.warning('$providerLabel-Response ohne choices');
        return null;
      }
      final choice = choices.first as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>?;
      return message?['content'] as String?;
    } catch (e) {
      _log.severe('Fehler beim Parsen der $providerLabel-Response: $e');
      return null;
    }
  }
}
