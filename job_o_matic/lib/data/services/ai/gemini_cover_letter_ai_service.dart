import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../../models/application.dart';
import '../../../models/cv_data.dart';
import '../api/api_client.dart';
import '../api/api_key_service.dart';
import 'cover_letter_ai_service.dart';
import 'cover_letter_prompt_builder.dart';
import 'cover_letter_sanitizer.dart';

/// KI-Anschreiben-Generierung über die Google Gemini API.
///
/// Implementiert [CoverLetterAiService] für den in
/// doc/plan/13-Anschreiben-KI.md empfohlenen Primäranbieter.
///
/// - REST-Aufruf via `ApiClient` (Retry mit exponentiellem Backoff,
///   Timeout – analog zu den anderen Services im Projekt)
/// - API-Key aus dem `ApiKeyService` (`geminiApiKey`)
/// - Gemeinsamer Prompt über [CoverLetterPromptBuilder]
/// - Output-Sanitizing via [CoverLetterSanitizer] vor Rückgabe
class GeminiCoverLetterAiService implements CoverLetterAiService {
  /// Aktuell verfügbare stabile Flash-Modelle (gemäß Google Gemini API
  /// https://ai.google.dev/gemini-api/docs/models):
  /// - `gemini-3.7-flash` (latest, most capable)
  /// - `gemini-3.6-flash` (previous generation)
  /// - `gemini-3.5-flash` (legacy, high-throughput)
  ///
  /// `gemini-2.5-flash` wurde nie veröffentlicht und führt zu HTTP 404.
  static const String defaultModel = 'gemini-3.5-flash';
  static const Duration defaultTimeout = Duration(seconds: 90);

  /// Mindestlänge der bereinigten Antwort, darunter gilt sie als kaputt.
  static const int minResponseLength = 50;

  final Logger _log;
  final ApiClient _apiClient;
  final AiApiKeyLoader _loadApiKey;
  final String _model;

  GeminiCoverLetterAiService({
    Logger? logger,
    AiApiKeyLoader? apiKeyLoader,
    http.Client? client,
    Duration? timeout,
    String? model,
  }) : _log = logger ?? Logger('GeminiCoverLetterAiService'),
       _loadApiKey =
           apiKeyLoader ??
           (() => ApiKeyService().loadKey(ApiKeyService.geminiApiKey)),
       _model = model ?? defaultModel,
       _apiClient = ApiClient(
         logger: logger ?? Logger('GeminiCoverLetterAiService'),
         // Key wird als URL-Parameter übergeben, nicht per Header
         keyService: null,
         client: client,
         // LLM-Antworten brauchen länger als klassische REST-Calls
         timeout: timeout ?? defaultTimeout,
       );

  @override
  String get providerName => 'Gemini ($_model)';

  /// Maximale Anzahl Versuche bei abgeschnittener Antwort (`MAX_TOKENS`).
  ///
  /// Bei jedem Versuch wird das Output-Budget erhöht (und das Denk-Budget
  /// minimal gehalten), sodass die sichtbare Antwort bei gemini-3.5-flash
  /// sicher abschließt – unabhängig von den genauen Modell-Limits.
  static const int maxAttempts = 3;

  /// Output-Token-Budgets pro Versuch (steigend): Thinking-Modelle zählen
  /// `maxOutputTokens` als Summe aus Gedankenkette + sichtbarem Text.
  static const List<int> outputBudgets = [8192, 16384, 32768];

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const CoverLetterAiException(
        'Kein Gemini-API-Key konfiguriert. Bitte in den Einstellungen '
        '(API-Keys) hinterlegen.',
      );
    }

    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$_model:generateContent',
      {'key': apiKey},
    );

    // Reasoning-Modelle können Antworten mitten im Satz abbrechen, wenn das
    // Token-Limit (Gedanken + Output) erreicht wird. Statt einer festen
    // Konfiguration probieren wir mit steigendem Output-Budget, bis eine
    // vollständige Antwort kommt (finishReason != MAX_TOKENS).
    CoverLetterAiException? lastError;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final maxTokens = _outputBudgetForAttempt(attempt);
      final requestBody = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': CoverLetterPromptBuilder.build(cvData, application)},
            ],
          },
        ],
        'generationConfig': {
          'temperature': CoverLetterPromptBuilder.temperature,
          'maxOutputTokens': maxTokens,
          // Reasoning-Modelle (Gemini 2.5+/3.x) liefern sonst "thought"-Parts
          // (interne Gedanken) mit in die Antwort – die gehören NICHT ins
          // Anschreiben (includeThoughts=false). thinkingBudget hält die
          // Gedankenkette klein, damit mehr Budget für den sichtbaren Text
          // bleibt (maxOutputTokens zählt Thinking + Output zusammen).
          'thinkingConfig': {
            'includeThoughts': false,
            'thinkingBudget': CoverLetterPromptBuilder.thinkingBudget,
          },
        },
      });

      final response = await _apiClient.post(
        uri,
        headers: {'Accept': 'application/json'},
        body: requestBody,
      );

      if (response.statusCode != 200) {
        throw CoverLetterAiException(
          'Gemini-API-Fehler (HTTP ${response.statusCode})',
          cause: response.body.length > 500
              ? '${response.body.substring(0, 500)}…'
              : response.body,
        );
      }

      final rawText = _extractText(response.body);
      if (rawText == null || rawText.trim().isEmpty) {
        throw const CoverLetterAiException(
          'Gemini lieferte keinen Text (ggf. Sicherheitsfilter ausgelöst).',
        );
      }

      // Abgeschnitten: Token-Limit (Thinking + Output) erreicht. Nicht
      // speichern – mit höherem Output-Budget erneut versuchen, sonst
      // an die Fallback-Kette (Mistral/Groq/Template) weiterreichen.
      if (_finishReason(response.body) == 'MAX_TOKENS') {
        lastError = CoverLetterAiException(
          'Gemini-Antwort abgeschnitten (MAX_TOKENS, Versuch '
          '${attempt + 1}/$maxAttempts, maxOutputTokens=$maxTokens).',
          cause: rawText,
        );
        _log.warning('${lastError.message} – erhöhe Output-Budget...');
        continue;
      }

      final sanitized = CoverLetterSanitizer.sanitize(rawText);
      if (sanitized.length < minResponseLength) {
        throw CoverLetterAiException(
          'Gemini-Antwort zu kurz/unbrauchbar (${sanitized.length} Zeichen).',
          cause: rawText,
        );
      }

      _log.info(
        'Anschreiben generiert (${sanitized.length} Zeichen, $providerName)',
      );
      return sanitized;
    }

    // Alle Versuche abgeschnitten → an Fallback-Kette weiterreichen.
    throw lastError ??
        const CoverLetterAiException(
          'Gemini-Antwort konnte nicht erzeugt '
          'werden.',
        );
  }

  /// Output-Budget für einen Versuch (beginnt mit kleinem, skaliert bei
  /// `MAX_TOKENS` nach oben). Hält `attempt` im gültigen Bereich.
  int _outputBudgetForAttempt(int attempt) {
    if (attempt < 0) return outputBudgets.first;
    if (attempt >= outputBudgets.length) return outputBudgets.last;
    return outputBudgets[attempt];
  }

  /// Liest den `finishReason` des ersten Candidates aus der Response.
  ///
  /// Relevante Werte: `STOP` (normal beendet), `MAX_TOKENS` (Token-Limit
  /// erreicht → Antwort abgeschnitten), `SAFETY` (blockiert).
  String? _finishReason(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) return null;
      return (candidates.first as Map<String, dynamic>)['finishReason']
          as String?;
    } catch (e) {
      _log.severe('Fehler beim Lesen des finishReason: $e');
      return null;
    }
  }

  /// Extrahiert den Text aus der Gemini-Response-Struktur.
  ///
  /// Struktur (v1beta): candidates[0].content.parts[*].text
  ///
  /// Reasoning-Modelle (Gemini 2.5+/3.x) können zusätzlich "thought"-Parts
  /// mit dem Flag `thought: true` liefern (interne Gedankenkette). Diese
  /// werden gefiltert – nur der sichtbare `text` gehört ins Anschreiben.
  String? _extractText(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) {
        _log.warning('Gemini-Response ohne candidates');
        return null;
      }
      final candidate = candidates.first as Map<String, dynamic>;
      final finishReason = candidate['finishReason'] as String?;
      if (finishReason == 'SAFETY') {
        _log.warning('Gemini hat die Antwort aus Sicherheitsgründen blockiert');
        return null;
      }
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      return parts
          .where((p) => p is Map<String, dynamic> && p['thought'] != true)
          .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
          .join();
    } catch (e) {
      _log.severe('Fehler beim Parsen der Gemini-Response: $e');
      return null;
    }
  }
}
