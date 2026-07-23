import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_utils.dart';
import '../../../models/cv_data.dart';

/// Generator für das Anschreiben einer Bewerbung.
class CoverLetterGenerator {
  pw.MultiPage build({
    required PersonalData personalData,
    required String renderedText,
    String? subject,
  }) {
    return pw.MultiPage(
      pageFormat: PdfUtils.pageFormat,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => [
        // Absender (wie auf einem Brief)
        pw.Text(
          '${personalData.fullName}\n'
          '${personalData.address ?? ''}\n'
          '${personalData.email ?? ''}\n'
          '${personalData.phone ?? ''}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 20),

        // Betreff
        pw.Header(
          level: 1,
          child: pw.Text(
            subject ?? 'Bewerbung',
            style: const pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 12),

        // Anschreiben-Text (aus Template)
        pw.Paragraph(
          text: renderedText,
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.5),
        ),
        pw.SizedBox(height: 20),

        // Grußformel
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Mit freundlichen Grüßen\n${personalData.fullName}',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}