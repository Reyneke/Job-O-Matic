import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Gemeinsame Helfer für die PDF-Generierung.
///
/// Definiert Seitenränder, Farben, Schriftarten, Datumsformate und
/// wiederverwendbare Konfigurationen für alle PDF-Generatoren.
class PdfUtils {
  PdfUtils._();

  // --- Seitenränder (DIN 5008) ---
  // 1 mm = 2.8346 pt
  // Links: 25mm, Rechts: 20mm, Oben/Unten: 20mm
  static const double marginLeft = 71; // 25mm
  static const double marginRight = 57; // 20mm
  static const double marginTop = 57; // 20mm
  static const double marginBottom = 57; // 20mm

  // --- Datumsformate (DIN 5008) ---
  /// Volles Datum: TT.MM.JJJJ (z.B. "21.08.2026")
  static final DateFormat dateFormatFull = DateFormat('dd.MM.yyyy');

  /// Monat/Jahr: MM.JJJJ (z.B. "08.2026")
  static final DateFormat dateFormatMonthYear = DateFormat('MM.yyyy');

  /// Extrahiert den Ort (Stadt) aus einer deutschen Adresse.

  /// Beispiel: "Glacisweg 9,13583 Berlin" → "Berlin".
  ///
  /// Erwartet das Muster „…PLZ(5 Ziffern) Ort". Wird keine PLZ gefunden,
  /// wird `null` zurückgegeben – der Aufrufer kann dann auf eine
  /// DIN-5008-konforme Datums-Schreibweise ohne Ortsangabe fallbacken.

  static String? extractCityFromAddress(String? address) {
    if (address == null || address.trim().isEmpty) return null;
    final trimmed = address.trim();
    final match = RegExp(r'\d{5}\s+(.+)$').firstMatch(trimmed);
    if (match == null) return null;
    final city = match.group(1)!.trim();
    if (city.isEmpty) return null;
    // Nachgestellte Satzzeichen/Beistriche entfernen (z.B. "13583 Berlin,"]).
    return city.replaceFirst(RegExp(r'[,;]\s*$'), '').trim();
  }

  /// Primärfarbe (entspricht AppTheme seed color red).
  static const primaryColor = PdfColors.red700;

  /// Sekundärfarbe für Headlines.
  static const headlineColor = PdfColors.red900;

  /// Default-Schriftgröße.
  static const defaultFontSize = 11.0;

  /// A4-Seitenformat mit DIN-5008-konformen Rändern.
  static PdfPageFormat get pageFormat => PdfPageFormat(
        595, // A4 width
        842, // A4 height
        marginLeft: marginLeft,
        marginRight: marginRight,
        marginTop: marginTop,
        marginBottom: marginBottom,
      );

  /// Gemeinsame Fußzeile: "Seite X von Y" (zentriert, dezent).
  ///
  /// DIN 5008: Die Seitenzahl erscheint **nicht** auf der ersten Seite.
  static pw.Widget buildFooter(pw.Context context) {
    if (context.pageNumber <= 1) {
      return pw.SizedBox.shrink();
    }
    return pw.Align(
      alignment: pw.Alignment.center,
      child: pw.Text(
        'Seite ${context.pageNumber} von ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }
}