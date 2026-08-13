import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_utils.dart';
import '../../../models/cv_data.dart';

/// Generator für das Deckblatt einer Bewerbung.
class CoverPageGenerator {
  pw.MultiPage build({
    required PersonalData personalData,
    required Map<String, dynamic> jobInfo,
    Uint8List? logoBytes,
  }) {
    return pw.MultiPage(
      pageFormat: PdfUtils.pageFormat,
      margin: const pw.EdgeInsets.all(48),
      // Fußzeile mit dezenter Seitenzahl (Option A).
      footer: (context) {
        String footerText;
        try {
          footerText = 'Seite ${context.pageNumber} von ${context.pagesCount}';
        } catch (_) {
          footerText = '';
        }
        return pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            footerText,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        );
      },
      build: (context) => [
        // Absender (oben links)
        pw.Header(
          level: 0,
          child: pw.Text(
            '${personalData.fullName}\n'
            '${personalData.address ?? ''}\n'
            '${personalData.email ?? ''}\n'
            '${personalData.phone ?? ''}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
        pw.SizedBox(height: 40),

        // Firmenlogo (zentriert) – Bild aus assets/mydata/cv, sonst Platzhalter
        pw.Center(
          child: pw.Container(
            width: 120,
            height: 120,
            decoration: logoBytes != null
                ? null
                : pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
            child: logoBytes != null
                ? pw.Image(pw.MemoryImage(logoBytes),
                    fit: pw.BoxFit.contain)
                : pw.Center(
                    child: pw.Text(
                      'Logo',
                      style: const pw.TextStyle(color: PdfColors.grey400),
                    ),
                  ),
          ),
        ),
        pw.SizedBox(height: 40),

        // Stellenbezeichnung – zentriert, auch bei mehrzeiligem Umbruch
        pw.Center(
          child: pw.Text(
            jobInfo['jobTitle'] as String? ?? '',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfUtils.primaryColor,
            ),
          ),
        ),
        pw.SizedBox(height: 16),

        // Firmenname
        pw.Center(
          child: pw.Text(
            jobInfo['company'] as String? ?? '',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 18, color: PdfColors.grey800),
          ),
        ),
        pw.SizedBox(height: 24),

        // Datum
        pw.Center(
          child: pw.Text(
            'Datum: ${jobInfo['date']}',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
          ),
        ),
      ],
    );
  }
}
