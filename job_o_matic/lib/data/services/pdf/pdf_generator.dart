import 'dart:io';
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
    required TemplateLoader templateLoader,
    required TemplateRenderer templateRenderer,
    CoverPageGenerator? coverPageGenerator,
    CoverLetterGenerator? coverLetterGenerator,
    CvGenerator? cvGenerator,
  })  : _templateLoader = templateLoader,
        _templateRenderer = templateRenderer,
        _coverPageGenerator = coverPageGenerator,
        _coverLetterGenerator = coverLetterGenerator,
        _cvGenerator = cvGenerator;

  /// Generiert eine vollständige Bewerbung als PDF und gibt den Dateipfad zurück.
  Future<String> generateApplicationPdf({
    required Application application,
    required CvData cvData,
    String? customTemplateName,
  }) async {
    _log.info(
        'PDF-Generierung gestartet für: ${application.jobTitle} bei ${application.company}');

    final pdfDocument = pw.Document();

    // 1. Deckblatt
    if (_coverPageGenerator != null) {
      final coverPage = _coverPageGenerator.build(
        personalData: cvData.personalData,
        jobInfo: {
          'jobTitle': application.jobTitle,
          'company': application.company,
          'date': DateFormat('dd.MM.yyyy').format(DateTime.now()),
        },
      );
      pdfDocument.addPage(coverPage);
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
    }

    // 3. Lebenslauf
    if (_cvGenerator != null) {
      final cvPage = _cvGenerator.build(cvData: cvData);
      pdfDocument.addPage(cvPage);
    }

    // 4. Speichern
    final fileName =
        '${application.id}_${_sanitizeFileName(application.company)}.pdf';
    final directory = await _getApplicationDirectory();
    final filePath = '${directory.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(await pdfDocument.save());

    _log.info('PDF gespeichert: $filePath');
    return filePath;
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