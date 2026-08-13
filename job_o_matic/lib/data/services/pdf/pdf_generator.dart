import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:logging/logging.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'template_loader.dart';
import 'cover_page_generator.dart';
import 'cover_letter_generator.dart';
import 'cv_generator.dart';
import '../../../models/application.dart';
import '../../../models/cv_data.dart';

/// Orchestriert die PDF-Generierung für eine vollständige Bewerbung.
///
/// Erzeugt Deckblatt + Anschreiben + Lebenslauf und speichert
/// das Ergebnis als PDF-Datei im App-Dokumentenverzeichnis.
class PdfGenerator {
  final Logger _log = Logger('PdfGenerator');
  final TemplateLoader _templateLoader;
  final TemplateRenderer _templateRenderer;
  final CoverPageGenerator? _coverPageGenerator;
  final CoverLetterGenerator? _coverLetterGenerator;
  final CvGenerator? _cvGenerator;

  PdfGenerator({
    required this._templateLoader,
    required this._templateRenderer,
    this._coverPageGenerator,
    this._coverLetterGenerator,
    this._cvGenerator,
  });

  /// Generiert eine vollständige Bewerbung als PDF und gibt den Dateipfad zurück.
  Future<String> generateApplicationPdf({
    required Application application,
    required CvData cvData,
    String? customTemplateName,
  }) async {
    _log.info(
        'PDF-Generierung gestartet für: ${application.jobTitle} bei ${application.company}');

    final pdfDocument = pw.Document();
    var pageCount = 0;

    // 1. Deckblatt
    if (_coverPageGenerator != null) {
      // Logo/Foto aus photoPath laden (falls vorhanden).
      final logoBytes = await _loadLogoBytes(cvData.personalData.photoPath);
      final coverPage = _coverPageGenerator.build(
        personalData: cvData.personalData,
        jobInfo: {
          'jobTitle': application.jobTitle,
          'company': application.company,
          'date': DateFormat('dd.MM.yyyy').format(DateTime.now()),
        },
        logoBytes: logoBytes,
      );
      pdfDocument.addPage(coverPage);
      pageCount++;
    }

    // 2. Anschreiben (mit Template)
    if (_coverLetterGenerator != null) {
      final templateText = await _templateLoader.loadTemplate(
        customTemplateName ?? 'cover_letter_default',
      );
      final renderedLetter = _templateRenderer.render(templateText, {
        'firstName': cvData.personalData.firstName,
        'lastName': cvData.personalData.lastName,
        'address': cvData.personalData.address ?? '',
        'email': cvData.personalData.email ?? '',
        'phone': cvData.personalData.phone ?? '',
        'jobTitle': application.jobTitle,
        'company': application.company,
        'date': DateFormat('dd.MM.yyyy').format(DateTime.now()),
        'skills': cvData.skills.map((s) => s.name).join(', '),
        'experience_years': _calculateTotalExperience(cvData.workExperience),
      });
      final letterPage = _coverLetterGenerator.build(
        personalData: cvData.personalData,
        renderedText: renderedLetter,
        subject: 'Bewerbung als ${application.jobTitle}',
      );
      pdfDocument.addPage(letterPage);
      pageCount++;
    }

    // 3. Lebenslauf
    if (_cvGenerator != null) {
      final cvPage = _cvGenerator.build(cvData: cvData);
      pdfDocument.addPage(cvPage);
      pageCount++;
    }

    // 4. Sicherheitscheck: Keine leeren PDFs speichern
    if (pageCount == 0) {
      throw StateError(
        'PDF-Generierung abgebrochen: Keine Seiten hinzugefügt. '
        'Bitte stellen Sie sicher, dass mindestens ein Generator '
        '(Deckblatt, Anschreiben oder Lebenslauf) konfiguriert ist.',
      );
    }

    // 5. Speichern
    final safeCompany = _sanitizeFileName(application.company);
    final safeTitle = _sanitizeFileName(application.jobTitle);
    // Fallback: Wenn Firma unbekannt, Titel verwenden.
    final namePart = (safeCompany.isEmpty ||
            safeCompany.toLowerCase().contains('unbekannt'))
        ? safeTitle
        : safeCompany;
    final fileName =
        '${application.id}_${namePart.isEmpty ? 'Bewerbung' : namePart}.pdf';
    final directory = await _getApplicationDirectory();
    final filePath = '${directory.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(await pdfDocument.save());

    _log.info('PDF gespeichert: $filePath ($pageCount Seiten)');
    return filePath;
  }

  /// Lädt das Logo/Foto aus dem Asset-Pfad, falls vorhanden.
  Future<Uint8List?> _loadLogoBytes(String? photoPath) async {
    if (photoPath == null || photoPath.isEmpty) return null;
    try {
      final data = await rootBundle.load(photoPath);
      return data.buffer.asUint8List();
    } catch (e) {
      _log.warning('Logo-Asset nicht gefunden: $photoPath ($e)');
      return null;
    }
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
  }

  String _calculateTotalExperience(List<WorkExperience> experiences) {
    int totalMonths = 0;
    for (final exp in experiences) {
      final start = exp.startDate;
      final end = exp.endDate ?? DateTime.now();
      totalMonths += (end.year - start.year) * 12 + (end.month - start.month);
    }
    final years = totalMonths ~/ 12;
    final months = totalMonths % 12;
    if (years == 0) return '$months Monate';
    if (months == 0) return '$years Jahre';
    return '$years Jahre und $months Monate';
  }

  Future<Directory> _getApplicationDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${appDir.path}/applications');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    return pdfDir;
  }
}