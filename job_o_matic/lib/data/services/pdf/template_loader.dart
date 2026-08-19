import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Lädt Textvorlagen aus dem assets-Verzeichnis.
///
/// Fallback auf eine eingebettete Default-Vorlage, falls die Datei nicht existiert.
/// Standard-Anschreiben-Vorlage (Fallback, falls keine Datei gefunden wird).
const String _defaultCoverLetterTemplate = '''
{{firstName}} {{lastName}}
{{address}}
{{email}}
{{phone}}

{{company}}
{{jobTitle}}

{{date}}

Betreff: Bewerbung als {{jobTitle}}

Sehr geehrte Damen und Herren,

mit großem Interesse habe ich Ihre Stellenausschreibung für die Position
als {{jobTitle}} bei der {{company}} gelesen.

{{job_description_excerpt}}

 Ich verfüge über {{experience_years}} Berufserfahrung und bringe fundierte
 Kenntnisse in folgenden Bereichen mit: {{relevant_skills}}.

Ich freue mich auf die Möglichkeit, mich in einem persönlichen Gespräch
vorstellen zu dürfen.

Mit freundlichen Grüßen

{{firstName}} {{lastName}}
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
  String render(String template, Map<String, String> variables) {
    String result = template;
    for (final entry in variables.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }
}