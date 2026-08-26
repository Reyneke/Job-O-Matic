import 'openai_compatible_cover_letter_ai_service.dart';

/// KI-Anschreiben-Generierung über die Groq API.
///
/// Zweite Alternative in der Fallback-Kette (Gemini → Mistral → **Groq**):
/// extrem schnell (LPU-Inferenz), offene Modelle, kostenloses Tageskontingent.
///
/// OpenAI-kompatible Chat-API:
/// `POST https://api.groq.com/openai/v1/chat/completions`
class GroqCoverLetterAiService extends OpenAiCompatibleCoverLetterAiService {
  static const String defaultModel = 'llama-3.3-70b-versatile';

  @override
  String get providerLabel => 'Groq';

  @override
  String get fallbackModel => defaultModel;

  GroqCoverLetterAiService({
    super.logger,
    super.apiKeyLoader,
    super.client,
    super.timeout,
    super.model,
  }) : super(host: 'api.groq.com', path: '/openai/v1/chat/completions');
}
