import 'package:html/parser.dart' as html_parser;
import 'package:logging/logging.dart';
import 'package:mustache_template/mustache.dart';

/// Service für E-Mail-Vorlagen mit Mustache-Template-Engine.
///
/// Verwendet das `mustache_template`-Paket für logikfreie Templates.
/// Unterstützt Platzhalter wie {{name}}, {{company}}, {{position}} etc.
///
/// Beispiel-Template:
/// ```
/// Betreff: Bewerbung als {{position}} bei {{company}}
///
/// Sehr geehrte Damen und Herren,
///
/// hiermit bewerbe ich mich auf die Stelle als {{position}}.
///
/// Mit freundlichen Grüßen
/// {{fullName}}
/// ```
class EmailTemplateService {
  final Logger _log = Logger('EmailTemplateService');

  /// Vordefinierte Standard-Vorlagen
  static const String defaultSubject = 'Bewerbung als {{position}}';

  static const String defaultBody = '''
Sehr geehrte Damen und Herren,

hiermit bewerbe ich mich auf die Stelle als **{{position}}** bei der **{{company}}**.

Meine vollständigen Bewerbungsunterlagen finden Sie im Anhang dieser E-Mail.

Für Rückfragen stehe ich Ihnen jederzeit gerne zur Verfügung.

Mit freundlichen Grüßen
{{fullName}}
''';

  /// Rendert ein Template mit den gegebenen Daten.
  String render(String template, Map<String, dynamic> data) {
    try {
      // htmlEscapeValues: false – die E-Mail ist bewusst Klartext; die
      // Standard-Engine würde sonst u. a. `/` zu `&#x2F;` escapen und so
      // Jobtitel wie „Flutter Developer / Client Engineer“ verstümmeln.
      final compiled = Template(template, htmlEscapeValues: false);
      final result = compiled.renderString(data);
      _log.fine('Template gerendert (${template.length} Zeichen)');
      return result;
    } catch (e) {
      _log.severe('Fehler beim Rendern des Templates: $e');
      // Fallback: Roh-Text zurückgeben
      return template;
    }
  }

  /// Erstellt den E-Mail-Body für eine Bewerbung.
  String buildApplicationBody({
    required String position,
    required String company,
    required String fullName,
    String? customTemplate,
    Map<String, dynamic>? extraData,
  }) {
    final data = <String, dynamic>{
      'position': _cleanText(position),
      'company': _cleanText(company),
      'fullName': _cleanText(fullName),
      ...?extraData,
    };

    final template = customTemplate ?? defaultBody;
    return render(template, data);
  }

  /// Erstellt die E-Mail-Betreffzeile.
  String buildSubject({
    required String position,
    required String company,
    String? customTemplate,
  }) {
    final data = <String, dynamic>{
      'position': _cleanText(position),
      'company': _cleanText(company),
    };

    final template = customTemplate ?? defaultSubject;
    return render(template, data);
  }

  /// Dekodiert HTML-Entities (z. B. `&#x2F;` → `/`, `&amp;` → `&`), die aus
  /// gescrapten/API-Job-Titeln stammen können, damit Betreff und Body sauber
  /// sind (siehe doc/plan/14-Email.md – Log: „Senior Flutter Developer
  /// &#x2F; …“). Nutzt den html-Parser (bereits Dependency).
  String _cleanText(String text) {
    if (text.isEmpty) return text;
    if (!text.contains('&')) return text;
    try {
      return html_parser.parseFragment(text).text ?? text;
    } catch (_) {
      return text;
    }
  }

  /// Validiert ein Template auf syntaktische Korrektheit.
  TemplateValidationResult validate(String template) {
    try {
      Template(template);
      return TemplateValidationResult(isValid: true);
    } catch (e) {
      return TemplateValidationResult(
        isValid: false,
        errorMessage: 'Template-Fehler: $e',
      );
    }
  }

  /// Extrahiert alle verwendeten Platzhalter aus einem Template.
  List<String> extractPlaceholders(String template) {
    final placeholders = <String>{};
    final regex = RegExp(r'\{\{([^}]+)\}\}');
    for (final match in regex.allMatches(template)) {
      placeholders.add(match.group(1)!.trim());
    }
    return placeholders.toList()..sort();
  }
}

class TemplateValidationResult {
  final bool isValid;
  final String? errorMessage;

  const TemplateValidationResult({required this.isValid, this.errorMessage});
}
