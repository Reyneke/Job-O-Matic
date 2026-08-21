import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_utils.dart';
import '../../../models/cv_data.dart';

/// Generator für das Anschreiben einer Bewerbung.
///
/// Erzeugt ein klassisches, professionelles deutsches Bewerbungsanschreiben-
/// Design, das den gängigen Formvorgaben entspricht.
///
/// Layout (DIN 5008):
/// 1. Absender (oben links, gleiche Kopfzeile wie auf dem Deckblatt)
/// 2. Empfänger (Firma + Adresse) darunter
/// 3. Datum (rechtsbündig, in der Zeile des Empfängers)
/// 4. Betreff mit "Betreff:"-Präfix
/// 5. Fließtext (aus Template, nur Inhalt – keine Absender-/Grußformel-Duplikate)
/// 6. Eine einzige Grußformel
///
/// Garantiert maximal eine Seite: Der Text wird bei Bedarf gekürzt
/// und die Schriftgröße dynamisch reduziert.
class CoverLetterGenerator {
  /// Maximale Zeichenanzahl für den Fließtext (ca. 1 Seite bei 10pt).
  static const int _maxTextLength = 1600;

  /// Minimale Schriftgröße, bevor der Text gekürzt wird.
  static const double _minFontSize = 9.0;

  pw.MultiPage build({
    required PersonalData personalData,
    required String renderedText,
    String? subject,
    String? company,
    String? companyAddress,
  }) {
    // Text auf maximale Länge kürzen, um eine Seite zu garantieren.
    final trimmedText = _trimToFit(renderedText);

    // Dynamische Schriftgröße: Bei langem Text leicht reduzieren.
    final fontSize = trimmedText.length > 1200 ? _minFontSize : 10.0;

    return pw.MultiPage(
      pageFormat: PdfUtils.pageFormat,
      margin: const pw.EdgeInsets.all(48),
      // Garantiert maximal eine Seite.
      maxPages: 1,
      // Fußzeile: "Seite X von Y" (zentriert, dezent, nicht auf Seite 1)
      footer: PdfUtils.buildFooter,
      build: (context) => [
        // --- ABSENDER (oben links, gleiche Kopfzeile wie Deckblatt) ---
        // DIN 5008: Nur Name + Adresse in der Absenderzeile.
        // E-Mail/Telefon gehören in den Briefkopf.
        pw.Header(
          level: 0,
          child: pw.Text(
            '${personalData.fullName}\n'
            '${personalData.address ?? ''}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
        pw.SizedBox(height: 20),

        // --- EMPFÄNGER (Firma + Adresse) + DATUM (rechtsbündig) ---
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Empfänger links
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (company != null && company.isNotEmpty)
                    pw.Text(
                      company,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                      ),
                    ),
                  if (companyAddress != null && companyAddress.isNotEmpty)
                    pw.Text(
                      companyAddress,
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                ],
              ),
            ),
            // Datum rechts (DIN 5008: numerisch TT.MM.JJJJ)
            pw.Text(
              PdfUtils.dateFormatFull.format(DateTime.now()),
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
            ),
          ],
        ),
        pw.SizedBox(height: 24),

        // --- BETREFF (mit "Betreff:"-Präfix) ---
        pw.Text(
          'Betreff: ${subject ?? 'Bewerbung'}',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey800,
          ),
        ),
        pw.SizedBox(height: 16),

        // --- FLIESS-TEXT (aus Template, nur Inhalt) ---
        pw.Paragraph(
          text: trimmedText,
          style: pw.TextStyle(
            fontSize: fontSize,
            lineSpacing: 1.3,
            color: PdfColors.grey900,
          ),
        ),
        pw.SizedBox(height: 20),

        // --- GRUßFORMEL (einzige, vom Generator gerendert) ---
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Mit freundlichen Grüßen\n${personalData.fullName}',
            style: pw.TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  /// Kürzt den Text auf eine maximale Länge, ohne mitten im Wort zu schneiden.
  String _trimToFit(String text) {
    if (text.length <= _maxTextLength) return text;

    // An der letzten Wortgrenze vor dem Limit schneiden.
    final cutIndex = text.lastIndexOf(' ', _maxTextLength);
    if (cutIndex <= 0) {
      return '${text.substring(0, _maxTextLength - 3)}...';
    }
    return '${text.substring(0, cutIndex)}...';
  }
}