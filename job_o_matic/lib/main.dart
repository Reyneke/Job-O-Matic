import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/logging/app_logger.dart';
import 'core/theme/app_theme_provider.dart';
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

class JobOMaticApp extends ConsumerWidget {
  const JobOMaticApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

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