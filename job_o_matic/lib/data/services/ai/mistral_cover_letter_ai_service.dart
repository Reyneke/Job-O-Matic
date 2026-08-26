import 'openai_compatible_cover_letter_ai_service.dart';

/// KI-Anschreiben-Generierung über die Mistral API (La Plateforme).
///
/// Erste Alternative in der Fallback-Kette (Gemini → **Mistral** → Groq):
/// EU-Anbieter (Frankreich), damit DSGVO-freundlichste Cloud-Option.
///
/// OpenAI-kompatible Chat-API: `POST https://api.mistral.ai/v1/chat/completions`
class MistralCoverLetterAiService
    extends OpenAiCompatibleCoverLetterAiService {
  static const String defaultModel = 'mistral-small-latest';

  @override
  String get providerLabel => 'Mistral';

  @override
  String get fallbackModel => defaultModel;

  MistralCoverLetterAiService({
    super.logger,
    super.apiKeyLoader,
    super.client,
    super.timeout,
    super.model,
  }) : super(host: 'api.mistral.ai', path: '/v1/chat/completions');
}
