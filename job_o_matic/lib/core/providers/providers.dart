import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/database_repository.dart';
import '../../data/services/api/api_client.dart';
import '../../data/services/api/api_key_service.dart';
import '../../data/services/api/ba_api_service.dart';
import '../../data/services/api/job_search_service.dart';
import '../../data/services/api/adzuna_api_service.dart';
import '../../data/services/api/serp_api_service.dart';
import '../../data/services/api/api_cache_service.dart';
import '../../data/services/api/job_scraper_service.dart';
import '../../data/services/api/api_connectivity_service.dart';
import '../../data/services/pdf/template_loader.dart';
import '../../data/services/pdf/cover_page_generator.dart';
import '../../data/services/pdf/cover_letter_generator.dart';
import '../../data/services/pdf/cv_generator.dart';
import '../../data/services/pdf/pdf_generator.dart';
import '../../data/services/autosave_service.dart';
import '../../data/services/pdf_cleanup_service.dart';
import '../../data/services/email/email_service.dart';
import '../../data/services/email/email_template_service.dart';
import '../../data/services/email/email_discovery_service.dart';
import '../../data/services/email/mail_queue_service.dart';
import '../../data/services/email/mail_queue_store.dart';
import '../../data/services/email/circuit_breaker.dart';
import '../../data/services/email/mail_dispatcher.dart';
import '../../data/repositories/sent_email_log_repository.dart';
import '../../data/services/ai/cover_letter_ai_service.dart';
import '../../data/services/ai/fallback_cover_letter_ai_service.dart';
import '../../data/services/ai/gemini_cover_letter_ai_service.dart';
import '../../data/services/ai/groq_cover_letter_ai_service.dart';
import '../../data/services/ai/mistral_cover_letter_ai_service.dart';

// ---------------------------------------------------------------------------
// Logger
// ---------------------------------------------------------------------------

final appLoggerProvider = Provider<Logger>((ref) {
  return Logger('App');
});

// ---------------------------------------------------------------------------
// Database Layer
// ---------------------------------------------------------------------------

final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper();
});

final databaseRepositoryProvider = Provider<DatabaseRepository>((ref) {
  return DatabaseRepository(dbHelper: ref.read(databaseHelperProvider));
});

// ---------------------------------------------------------------------------
// API Key Service
// ---------------------------------------------------------------------------

final apiKeyServiceProvider = Provider<ApiKeyService>((ref) {
  return ApiKeyService();
});

// ---------------------------------------------------------------------------
// API Client
// ---------------------------------------------------------------------------

final apiClientProvider = Provider<ApiClient>((ref) {
  final logger = ref.read(appLoggerProvider);
  final keyService = ref.read(apiKeyServiceProvider);
  return ApiClient(logger: logger, keyService: keyService);
});

// ---------------------------------------------------------------------------
// API Cache Service
// ---------------------------------------------------------------------------

final apiCacheServiceProvider = Provider<ApiCacheService>((ref) {
  return ApiCacheService();
});

// ---------------------------------------------------------------------------
// API Connectivity Check (Jobsuche-Rev, Konnektivitäts-Button in den
// API-Key-Einstellungen)
// ---------------------------------------------------------------------------

final apiConnectivityServiceProvider = Provider<ApiConnectivityService>((ref) {
  return ApiConnectivityService(keyService: ref.read(apiKeyServiceProvider));
});

// ---------------------------------------------------------------------------
// BA API Service
// ---------------------------------------------------------------------------

final baApiServiceProvider = Provider<BaApiService>((ref) {
  final client = ref.read(apiClientProvider);
  return BaApiService(client: client);
});

// ---------------------------------------------------------------------------
// Adzuna API Service
// ---------------------------------------------------------------------------

final adzunaApiServiceProvider = Provider<AdzunaApiService>((ref) {
  final client = ref.read(apiClientProvider);
  final keyService = ref.read(apiKeyServiceProvider);
  return AdzunaApiService(client: client, keyService: keyService);
});

// ---------------------------------------------------------------------------
// SerpAPI Service (letzter Fallback in der Jobsuche-Kaskade)
// ---------------------------------------------------------------------------

final serpApiServiceProvider = Provider<SerpApiService>((ref) {
  final client = ref.read(apiClientProvider);
  final keyService = ref.read(apiKeyServiceProvider);
  return SerpApiService(client: client, keyService: keyService);
});

// ---------------------------------------------------------------------------
// Job Scraper Service
// ---------------------------------------------------------------------------

final jobScraperServiceProvider = Provider<JobScraperService>((ref) {
  return JobScraperService();
});

// ---------------------------------------------------------------------------
// Job Search Service
// ---------------------------------------------------------------------------

final jobSearchServiceProvider = Provider<JobSearchService>((ref) {
  final baService = ref.read(baApiServiceProvider);
  final adzunaService = ref.read(adzunaApiServiceProvider);
  final serpService = ref.read(serpApiServiceProvider);
  final cacheService = ref.read(apiCacheServiceProvider);
  return JobSearchService(
    baService: baService,
    adzunaService: adzunaService,
    serpService: serpService,
    cacheService: cacheService,
  );
});

// ---------------------------------------------------------------------------
// PDF Generierung
// ---------------------------------------------------------------------------

final templateLoaderProvider = Provider<TemplateLoader>((ref) {
  return TemplateLoader();
});

final coverPageGeneratorProvider = Provider<CoverPageGenerator>((ref) {
  return CoverPageGenerator();
});

final coverLetterGeneratorProvider = Provider<CoverLetterGenerator>((ref) {
  return CoverLetterGenerator();
});

final cvGeneratorProvider = Provider<CvGenerator>((ref) {
  return CvGenerator();
});

final pdfGeneratorProvider = Provider<PdfGenerator>((ref) {
  return PdfGenerator(
    templateLoader: ref.read(templateLoaderProvider),
    templateRenderer: TemplateRenderer(),
    coverPageGenerator: ref.read(coverPageGeneratorProvider),
    coverLetterGenerator: ref.read(coverLetterGeneratorProvider),
    cvGenerator: ref.read(cvGeneratorProvider),
  );
});

// ---------------------------------------------------------------------------
// Autosave Service
// ---------------------------------------------------------------------------

final autosaveServiceProvider = Provider<AutosaveService>((ref) {
  return AutosaveService();
});

// ---------------------------------------------------------------------------
// PDF Cleanup Service
// ---------------------------------------------------------------------------

final pdfCleanupServiceProvider = Provider<PdfCleanupService>((ref) {
  return PdfCleanupService(dbRepository: ref.read(databaseRepositoryProvider));
});

// ---------------------------------------------------------------------------
// E-Mail Services (Automailer)
// ---------------------------------------------------------------------------

final emailServiceProvider = Provider<EmailService>((ref) {
  final keyService = ref.read(apiKeyServiceProvider);
  return EmailService(keyService: keyService);
});

final emailTemplateServiceProvider = Provider<EmailTemplateService>((ref) {
  return EmailTemplateService();
});

final emailDiscoveryServiceProvider = Provider<EmailDiscoveryService>((ref) {
  // Phase C: E-Mail-Adress-Ermittlung (Kaskade Stufen 1–3). Nutzt einen
  // eigenen http.Client mit Timeout; Stufe 4 (manuell) liegt in der UI.
  return EmailDiscoveryService();
});

final circuitBreakerProvider = Provider<CircuitBreaker>((ref) {
  return CircuitBreaker();
});

final sentEmailLogRepositoryProvider = Provider<SentEmailLogRepository>((ref) {
  return SentEmailLogRepository(dbHelper: ref.read(databaseHelperProvider));
});

final mailQueueServiceProvider = Provider<MailQueueService>((ref) {
  // Phase B: Queue in SQLite persistieren (offene pending-Einträge überleben
  // den App-Neustart; kein stiller Auto-Versand – siehe requeuePendingEmails).
  return MailQueueService(
    store: SqliteMailQueueStore(dbHelper: ref.read(databaseHelperProvider)),
  );
});

final mailDispatcherProvider = Provider<MailDispatcher>((ref) {
  return MailDispatcher(
    queueService: ref.read(mailQueueServiceProvider),
    emailService: ref.read(emailServiceProvider),
    templateService: ref.read(emailTemplateServiceProvider),
    circuitBreaker: ref.read(circuitBreakerProvider),
    sentEmailLogRepository: ref.read(sentEmailLogRepositoryProvider),
    databaseRepository: ref.read(databaseRepositoryProvider),
  );
});

// ---------------------------------------------------------------------------
// KI-Anschreiben (Phase 2+3, doc/plan/13-Anschreiben-KI.md)
// ---------------------------------------------------------------------------

/// Primärer KI-Anbieter für Anschreiben (Google Gemini).
///
/// Der API-Key wird intern über den [ApiKeyService] (`geminiApiKey`) geladen.
final geminiCoverLetterAiServiceProvider = Provider<GeminiCoverLetterAiService>(
  (ref) {
    return GeminiCoverLetterAiService(logger: ref.read(appLoggerProvider));
  },
);

/// Erste Alternative: Mistral (EU-Anbieter, DSGVO-freundlich).
final mistralCoverLetterAiServiceProvider =
    Provider<MistralCoverLetterAiService>((ref) {
      return MistralCoverLetterAiService(
        logger: ref.read(appLoggerProvider),
        apiKeyLoader: () =>
            ApiKeyService().loadKey(ApiKeyService.mistralApiKey),
      );
    });

/// Zweite Alternative: Groq (extrem schnell, offene Modelle).
final groqCoverLetterAiServiceProvider = Provider<GroqCoverLetterAiService>((
  ref,
) {
  return GroqCoverLetterAiService(
    logger: ref.read(appLoggerProvider),
    apiKeyLoader: () => ApiKeyService().loadKey(ApiKeyService.groqApiKey),
  );
});

/// Aktiver KI-Anschreiben-Service als Fallback-Kette:
/// Gemini → Mistral → Groq. Schlägt alles fehl, greift der
/// Template-Fallback auf Ebene des Aufrufers.
final coverLetterAiServiceProvider = Provider<CoverLetterAiService>((ref) {
  return FallbackCoverLetterAiService([
    ref.read(geminiCoverLetterAiServiceProvider),
    ref.read(mistralCoverLetterAiServiceProvider),
    ref.read(groqCoverLetterAiServiceProvider),
  ]);
});
