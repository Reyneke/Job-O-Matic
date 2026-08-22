import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Lädt Textvorlagen aus dem assets-Verzeichnis.
///
/// Fallback auf eine eingebettete Default-Vorlage, falls die Datei nicht existiert.
/// Standard-Anschreiben-Vorlage (Fallback, falls keine Datei gefunden wird).
const String _defaultCoverLetterTemplate = '''
{{salutation}}

mit großem Interesse habe ich Ihre Stellenausschreibung für die Position als {{jobTitle}} bei der {{company}} gelesen. {{job_description_excerpt}}

Ich verfüge über {{experience_years}} Berufserfahrung und bringe fundierte Kenntnisse in folgenden Bereichen mit: {{relevant_skills}}. In meiner bisherigen Tätigkeit konnte ich umfangreiche Erfahrungen in der Entwicklung und Umsetzung komplexer Softwareprojekte sammeln.

Ich bin zuverlässig, teamfähig und arbeite mich schnell in neue Themengebiete ein. Mein strukturiertes und lösungsorientiertes Arbeiten befähigt mich, auch anspruchsvolle Projekte erfolgreich umzusetzen.

Ich freue mich auf die Möglichkeit, mich in einem persönlichen Gespräch vorstellen zu dürfen, und stehe Ihnen für Rückfragen jederzeit gerne zur Verfügung.
''';

class TemplateLoader {
  final Logger _log = Logger('TemplateLoader');

  /// Lädt eine Vorlage aus `assets/mydata/vorlagen/`.
  ///
  /// [templateName] ohne Pfad und Endung, z. B. 'cover_letter_default'.
  Future<String> loadTemplate(String templateName) async {
    try {
      return await rootBundle.loadString(
        'assets/mydata/vorlagen/$templateName.txt',
      );
    } catch (e) {
      _log.warning('Vorlage "$templateName" nicht gefunden, verwende Fallback');
      return _defaultCoverLetterTemplate;
    }
  }

  /// Lädt mehrere Vorlagen auf einmal.
  Future<Map<String, String>> loadAllTemplates() async {
    final templates = <String, String>{
      'cover_letter_default': '',
    };

    for (final key in templates.keys.toList()) {
      templates[key] = await loadTemplate(key);
    }

    return templates;
  }
}

/// Ersetzt Platzhalter `{{variable}}` durch tatsächliche Werte.
class TemplateRenderer {
  /// Ersetzt alle Platzhalter im Template durch die angegebenen Werte.
  ///
  /// Beispiel:
  /// ```dart
  /// render('Hallo {{name}}', {'name': 'Welt'}) → 'Hallo Welt'
  /// ```
  ///
  /// Normalisiert außerdem Zeilenumbrüche:
  /// - Einfache `\n` werden zu Leerzeichen (Fließtext fließt dynamisch)
  /// - Leere Zeilen (`\n\n`) bleiben als Absatztrenner erhalten
  String render(String template, Map<String, String> variables) {
    String result = template;
    for (final entry in variables.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return _normalizeLineBreaks(result);
  }

  /// Normalisiert Zeilenumbrüche für den Fließtext.
  ///
  /// DIN 5008: Der Fließtext soll dynamisch umbrechen (Blocksatz).
  /// Feste Zeilenumbrüche aus der Vorlage würden das Layout zerstören.
  ///
  /// Regeln:
  /// - Einfache `\n` → Leerzeichen (Zeilen werden zusammengeführt)
  /// - `\n\n` → Absatzumbruch (bleibt erhalten)
  /// - Mehrfache Leerzeichen werden zu einem einzelnen reduziert
  String _normalizeLineBreaks(String text) {
    // Zeilenumbrüche normalisieren (Windows CRLF → LF)
    var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Absätze (leere Zeilen) temporär schützen
    final paragraphs = normalized.split('\n\n');

    // Jeden Absatz: Einfache Zeilenumbrüche → Leerzeichen, trimmen
    final merged = paragraphs.map((paragraph) {
      return paragraph
          .replaceAll('\n', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }).toList();

    // Absätze wieder mit \n\n verbinden
    return merged.join('\n\n').trim();
  }
}