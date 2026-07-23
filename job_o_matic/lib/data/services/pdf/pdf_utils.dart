import 'package:pdf/pdf.dart';

/// Gemeinsame Helfer für die PDF-Generierung.
///
/// Definiert Seitenränder, Farben, Schriftarten und wiederverwendbare
/// Konfigurationen für alle PDF-Generatoren.
class PdfUtils {
  PdfUtils._();

  /// Seitenränder in Points (1 inch = 72 pt).
  static const double marginLeft = 48;
  static const double marginRight = 48;
  static const double marginTop = 48;
  static const double marginBottom = 48;

  /// Primärfarbe (entspricht AppTheme seed color red).
  static const primaryColor = PdfColors.red700;

  /// Sekundärfarbe für Headlines.
  static const headlineColor = PdfColors.red900;

  /// Default-Schriftgröße.
  static const defaultFontSize = 11.0;

  /// A4-Seitenformat mit benutzerdefinierten Rändern.
  static PdfPageFormat get pageFormat => PdfPageFormat(
        595, // A4 width
        842, // A4 height
        marginLeft: marginLeft,
        marginRight: marginRight,
        marginTop: marginTop,
        marginBottom: marginBottom,
      );
}