import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_utils.dart';
import '../../../models/cv_data.dart';

/// Generator für das Deckblatt einer Bewerbung.
class CoverPageGenerator {
  pw.MultiPage build({
    required PersonalData personalData,
    required Map<String, dynamic> jobInfo,
  }) {
    return pw.MultiPage(
      pageFormat: PdfUtils.pageFormat,
      margin: const pw.EdgeInsets.all(48),
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
        pw.SizedBox(height: 80),

        // Firmenlogo-Platzhalter (zentriert)
        pw.Center(
          child: pw.Container(
            width: 120,
            height: 120,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Center(
              child: pw.Text(
                'Logo',
                style: const pw.TextStyle(color: PdfColors.grey400),
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 60),

        // Stellenbezeichnung
        pw.Center(
          child: pw.Text(
            jobInfo['jobTitle'] as String? ?? '',
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
            style: const pw.TextStyle(fontSize: 18, color: PdfColors.grey800),
          ),
        ),
        pw.SizedBox(height: 40),

        // Datum
        pw.Center(
          child: pw.Text(
            'Datum: ${jobInfo['date']}',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
          ),
        ),

        // Fußzeile
        ..._buildFooter(context, personalData),
      ],
    );
  }

  List<pw.Widget> _buildFooter(pw.Context context, PersonalData data) {
    return [
      pw.SizedBox(height: 100),
      pw.Divider(),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(data.email ?? '',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text(data.phone ?? '',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    ];
  }
}