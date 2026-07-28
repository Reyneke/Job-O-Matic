import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'dart:io';

/// Centralized logging system for the application.
///
/// Usage:
/// ```dart
/// final log = AppLogger.logger('Workflow');
/// log.info('Generierung gestartet');
/// ```
class AppLogger {
  AppLogger._();

  static bool _initialized = false;

  /// Initialize the logging system.
  ///
  /// Call once at app startup, e.g. in `main()`.
  /// - [level]: The root log level (default: `Level.ALL` for debug, `Level.INFO` for release).
  /// - [enableFileLogging]: When true, logs are written to a file in the app cache directory.
  /// - [logDirectory]: Custom log directory path (optional). If null, uses app cache directory.
  static void init({
    Level level = Level.ALL,
    bool enableFileLogging = false,
    String? logDirectory,
  }) {
    if (_initialized) return;
    _initialized = true;

    Logger.root.level = level;

    // Console output (uses debugPrint to avoid interleaving with Flutter output)
    Logger.root.onRecord.listen((record) {
      final message = _formatLog(record);
      debugPrint(message);
    });

    // File output (optional)
    if (enableFileLogging && logDirectory != null) {
      final file = File('$logDirectory/app_log.txt');
      Logger.root.onRecord.listen((record) async {
        final message = _formatLog(record);
        await file.writeAsString('$message\n', mode: FileMode.append);
        _rotateLogIfNeeded(file);
      });
    }
  }

  /// Get a named logger for a specific component/module.
  static Logger logger(String name) => Logger(name);

  /// Format a log record as a human-readable string.
  static String _formatLog(LogRecord record) {
    final timestamp = record.time.toIso8601String();
    final level = record.level.name.padRight(7);
    final loggerName = record.loggerName;
    final message = record.message;
    final stackTrace = record.stackTrace;
    final error = record.error;

    final buffer = StringBuffer('[$timestamp] [$level] [$loggerName] $message');
    if (error != null) {
      buffer.write(' | Error: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }

  /// Rotate log file if it exceeds maxSize (5 MB).
  static Future<void> _rotateLogIfNeeded(File file) async {
    try {
      final size = await file.length();
      if (size > 5 * 1024 * 1024) {
        // 5 MB
        for (int i = 2; i >= 0; i--) {
          final rotatedFile = File('${file.path}.$i');
          if (await rotatedFile.exists()) {
            if (i < 2) {
              await rotatedFile.rename('${file.path}.${i + 1}');
            } else {
              await rotatedFile.delete();
            }
          }
        }
        await file.rename('${file.path}.0');
      }
    } catch (_) {
      // Silently ignore rotation errors
    }
  }
}