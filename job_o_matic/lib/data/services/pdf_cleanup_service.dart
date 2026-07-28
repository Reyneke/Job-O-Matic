import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';
import '../repositories/database_repository.dart';

/// Service für die Bereinigung verwaister PDF-Dateien.
///
/// Wird beim App-Start ausgeführt und entfernt:
/// - PDF-Dateien, die zu keiner Bewerbung mehr gehören
/// - Temporäre Dateien, die älter als 24 Stunden sind
class PdfCleanupService {
  final Logger _log = Logger('PdfCleanupService');
  final DatabaseRepository _dbRepository;

  PdfCleanupService({DatabaseRepository? dbRepository})
      : _dbRepository = dbRepository ?? DatabaseRepository();

  /// Führt die Bereinigung durch. Sollte beim App-Start aufgerufen werden.
  Future<PdfCleanupResult> cleanup() async {
    _log.info('Starte PDF-Bereinigung...');
    final result = PdfCleanupResult();

    try {
      final dir = await _getPdfDirectory();
      if (!await dir.exists()) {
        _log.info('PDF-Verzeichnis existiert nicht – keine Bereinigung nötig');
        return result;
      }

      final files = await dir.list().toList();
      final validPaths = await _getValidPdfPaths();

      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.pdf')) {
          if (!validPaths.contains(entity.path)) {
            // Prüfen, ob die Datei älter als 24h ist (Sicherheit)
            final stat = await entity.stat();
            final age = DateTime.now().difference(stat.modified);
            if (age.inHours >= 24) {
              await entity.delete();
              result.deletedFiles.add(entity.path);
              _log.info('Verwaiste PDF gelöscht: ${entity.path}');
            } else {
              result.skippedFiles.add(entity.path);
              _log.fine('PDF zu jung zum Löschen: ${entity.path}');
            }
          }
        }
      }

      _log.info(
        'PDF-Bereinigung abgeschlossen: '
        '${result.deletedFiles.length} gelöscht, '
        '${result.skippedFiles.length} übersprungen',
      );
    } catch (e) {
      _log.severe('Fehler bei PDF-Bereinigung: $e');
      result.error = e.toString();
    }

    return result;
  }

  /// Sammelt alle gültigen PDF-Pfade aus der Datenbank.
  Future<Set<String>> _getValidPdfPaths() async {
    final validPaths = <String>{};
    try {
      final applications = await _dbRepository.loadApplications();
      for (final app in applications) {
        if (app.pdfPath != null && app.pdfPath!.isNotEmpty) {
          validPaths.add(app.pdfPath!);
        }
      }
    } catch (e) {
      _log.warning('Konnte gültige PDF-Pfade nicht laden: $e');
    }
    return validPaths;
  }

  /// Ermittelt das PDF-Verzeichnis.
  Future<Directory> _getPdfDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${appDir.path}/pdfs');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    return pdfDir;
  }
}

class PdfCleanupResult {
  final List<String> deletedFiles;
  final List<String> skippedFiles;
  String? error;

  PdfCleanupResult({
    this.deletedFiles = const [],
    this.skippedFiles = const [],
    this.error,
  });

  bool get hasError => error != null && error!.isNotEmpty;
  int get totalCleaned => deletedFiles.length;
}