import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/logging/app_logger.dart';
import 'core/theme/app_theme_provider.dart';
import 'core/providers/providers.dart';
import 'data/repositories/job_repository.dart';
import 'router/app_router.dart';

void main() {
  // Initialize the logging system
  AppLogger.init(
    level: Level.ALL,
    enableFileLogging: false,
  );

  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqlite for desktop platforms (Windows/Linux/macOS)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    const ProviderScope(
      child: JobOMaticApp(),
    ),
  );
}

class JobOMaticApp extends ConsumerStatefulWidget {
  const JobOMaticApp({super.key});

  @override
  ConsumerState<JobOMaticApp> createState() => _JobOMaticAppState();
}

class _JobOMaticAppState extends ConsumerState<JobOMaticApp> {
  @override
  void initState() {
    super.initState();

    // PDF-Cleanup und MailDispatcher-Start nach dem ersten Frame ausführen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  Future<void> _initializeServices() async {
    final log = Logger('App');

    // 1. PDF-Cleanup beim App-Start durchführen
    try {
      final cleanupService = ref.read(pdfCleanupServiceProvider);
      final result = await cleanupService.cleanup();
      if (result.totalCleaned > 0) {
        log.info('PDF-Cleanup: ${result.totalCleaned} verwaiste Dateien entfernt');
      }
    } catch (e) {
      log.warning('PDF-Cleanup fehlgeschlagen: $e');
    }

    // 2. MailDispatcher starten (für Hintergrund-Queue-Verarbeitung)
    try {
      final mailDispatcher = ref.read(mailDispatcherProvider);
      mailDispatcher.start();
      log.info('MailDispatcher gestartet');
    } catch (e) {
      log.warning('MailDispatcher-Start fehlgeschlagen: $e');
    }
  }

  @override
  void dispose() {
    // MailDispatcher beim Beenden stoppen
    try {
      ref.read(mailDispatcherProvider).stop();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);

    // Initialize the job repository from database on first build
    ref.listen(jobRepositoryProvider, (prev, next) {
      // Initialization is triggered once via the provider
    });

    return MaterialApp.router(
      title: 'Job-O-Matic',
      debugShowCheckedModeBanner: false,
      theme: AppThemeProvider.lightTheme,
      darkTheme: AppThemeProvider.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
