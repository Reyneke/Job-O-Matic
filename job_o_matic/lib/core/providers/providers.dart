import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/database_repository.dart';
import '../../data/services/api/api_client.dart';
import '../../data/services/api/api_key_service.dart';
import '../../data/services/api/ba_api_service.dart';
import '../../data/services/api/job_search_service.dart';
import '../../data/services/api/adzuna_api_service.dart';
import '../../data/services/api/api_cache_service.dart';
import '../../data/services/api/job_scraper_service.dart';
import '../../data/services/pdf/template_loader.dart';
import '../../data/services/pdf/cover_page_generator.dart';
import '../../data/services/pdf/cover_letter_generator.dart';
import '../../data/services/pdf/cv_generator.dart';
import '../../data/services/pdf/pdf_generator.dart';
import '../../data/services/autosave_service.dart';
import '../../data/services/pdf_cleanup_service.dart';
import '../../data/services/email/email_service.dart';
import '../../data/services/email/email_template_service.dart';
import '../../data/services/email/mail_queue_service.dart';
import '../../data/services/email/circuit_breaker.dart';
import '../../data/services/email/mail_dispatcher.dart';

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
  final cacheService = ref.read(apiCacheServiceProvider);
  return JobSearchService(
    baService: baService,
    adzunaService: adzunaService,
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
  return PdfCleanupService(
    dbRepository: ref.read(databaseRepositoryProvider),
  );
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

final circuitBreakerProvider = Provider<CircuitBreaker>((ref) {
  return CircuitBreaker();
});

final mailQueueServiceProvider = Provider<MailQueueService>((ref) {
  return MailQueueService();
});

final mailDispatcherProvider = Provider<MailDispatcher>((ref) {
  return MailDispatcher(
    queueService: ref.read(mailQueueServiceProvider),
    emailService: ref.read(emailServiceProvider),
    templateService: ref.read(emailTemplateServiceProvider),
    circuitBreaker: ref.read(circuitBreakerProvider),
  );
});