import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import '../../data/database/database_helper.dart';
import '../../data/repositories/database_repository.dart';
import '../../data/repositories/job_repository.dart';
import '../../data/services/api/api_client.dart';
import '../../data/services/api/api_key_service.dart';
import '../../data/services/api/ba_api_service.dart';
import '../../data/services/api/job_search_service.dart';
import '../../data/services/pdf/template_loader.dart';
import '../../data/services/pdf/cover_page_generator.dart';
import '../../data/services/pdf/cover_letter_generator.dart';
import '../../data/services/pdf/cv_generator.dart';
import '../../data/services/pdf/pdf_generator.dart';
import '../../data/services/autosave_service.dart';

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
// Job Repository
// ---------------------------------------------------------------------------

final jobRepositoryProvider = Provider<JobRepository>((ref) {
  final dbRepo = ref.read(databaseRepositoryProvider);
  final pdfGen = ref.read(pdfGeneratorProvider);
  return JobRepository(dbRepo: dbRepo, pdfGenerator: pdfGen);
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
// BA API Service
// ---------------------------------------------------------------------------

final baApiServiceProvider = Provider<BaApiService>((ref) {
  final client = ref.read(apiClientProvider);
  return BaApiService(client: client);
});

// ---------------------------------------------------------------------------
// Job Search Service
// ---------------------------------------------------------------------------

final jobSearchServiceProvider = Provider<JobSearchService>((ref) {
  final baService = ref.read(baApiServiceProvider);
  return JobSearchService(
    baService: baService,
  );
});

// ---------------------------------------------------------------------------
// PDF Generierung
// ---------------------------------------------------------------------------

final templateLoaderProvider = Provider<TemplateLoader>((ref) {
  return TemplateLoader();
});

final templateRendererProvider = Provider<TemplateRenderer>((ref) {
  return TemplateRenderer();
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
    templateRenderer: ref.read(templateRendererProvider),
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