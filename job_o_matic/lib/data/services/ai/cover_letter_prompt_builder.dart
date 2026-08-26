import '../../../models/application.dart';
import '../../../models/cv_data.dart';

/// Baut den gemeinsamen Prompt für alle KI-Anbieter.
///
/// Wird von Gemini, Mistral und Groq genutzt, damit alle denselben
/// getesteten Prompt verwenden (keine Kopien!).
///
/// Enthält:
/// - Harte Regeln (keine erfundenen Fakten, nur Fließtext, DIN-5008-taugliche
///   Absatzstruktur – siehe doc/plan/12-DIN5008.md und 13-Anschreiben-KI.md)
/// - Strukturierte CV-Daten
/// - Die Stellenanzeige klar als **Daten** markiert (XML-Tags), um
///   Prompt-Injection aus gescrapeten Anzeigen zu erschweren
class CoverLetterPromptBuilder {
  CoverLetterPromptBuilder._();

  /// LLMs neigen zu langen Antworten – das Anschreiben muss auf eine Seite.
  ///
  /// Reasoning-Modelle (Gemini 2.5+/3.x) verbrauchen Token für ihre interne
  /// Gedankenkette UND den sichtbaren Text. `maxOutputTokens` begrenzt die
  /// SUMME aus beidem – ist sie zu klein, wird der sichtbare Text mitten im
  /// Satz abgeschnitten (`finishReason: MAX_TOKENS`). 16384 gibt deshalb
  /// reichlich Spielraum; die Länge wird eh per Prompt auf ~350 Wörter
  /// begrenzt (die eigentliche Antwort braucht nur ~800 Token).
  static const int maxOutputTokens = 16384;

  /// Maximale Token-Zahl für die interne Gedankenkette von Reasoning-Modellen.
  ///
  /// Ein Bewerbungsanschreiben ist eine einfache, klar definierte Aufgabe –
  /// dafür reicht minimales Denken (Google empfiehlt bei "Simple tasks"
  /// minimal/low thinking). Je weniger Tokens fürs Denken verbraucht werden,
  /// desto mehr Budget bleibt für den sichtbaren Text. 1024 ist der
  /// dokumentierte Mindestwert für Thinking-Modelle.
  static const int thinkingBudget = 1024;

  static const double temperature = 0.7;

  static String build(CvData cvData, Application application) {
    final buffer = StringBuffer();

    buffer.writeln(
      'Du bist eine erfahrene Bewerbungsberaterin und schreibst ein '
      'Anschreiben auf Deutsch für die folgende Stelle.',
    );
    buffer.writeln();
    buffer.writeln('Strenge Regeln:');
    buffer.writeln(
      '- Erfinde KEINE Fakten. Verwende ausschließlich die unten angegebenen '
      'Lebenslauf-Daten und Informationen aus der Stellenanzeige.',
    );
    buffer.writeln(
      '- Schreibe reinen Fließtext: keine Listen, keine Überschriften, kein '
      'Markdown (keine Sternchen, Raute oder Backticks), keine Emojis.',
    );
    buffer.writeln(
      '- Beginne mit der Anrede "Sehr geehrte Damen und Herren," und beende '
      'den Text mit "Mit freundlichen Grüßen" gefolgt vom Namen in einer '
      'neuen Zeile.',
    );
    buffer.writeln(
      '- Strukturiere den Text in höchstens 5 Absätze, getrennt durch '
      'Leerzeilen. Jeder Absatz ist ein zusammenhängender Textblock ohne '
      'manuelle Zeilenumbrüche.',
    );
    buffer.writeln(
      '- Das Anschreiben muss auf eine Din-A4-Seite passen (ca. 250–350 Wörter).',
    );
    buffer.writeln();

    buffer.writeln('<lebenslauf>');
    buffer.writeln(_formatCvData(cvData));
    buffer.writeln('</lebenslauf>');
    buffer.writeln();

    buffer.writeln('<stellenanzeige>');
    buffer.writeln('Position: ${application.jobTitle}');
    buffer.writeln('Unternehmen: ${application.company}');
    if (application.companyAddress?.isNotEmpty == true) {
      buffer.writeln('Adresse: ${application.companyAddress}');
    }
    buffer.writeln('Beschreibung:');
    buffer.writeln(
      application.jobDescription ??
          '(Keine Beschreibung verfügbar – formuliere allgemein passend zur Position.)',
    );
    buffer.writeln('</stellenanzeige>');

    return buffer.toString();
  }

  static String _formatCvData(CvData cvData) {
    final buffer = StringBuffer();
    final personal = cvData.personalData;

    buffer.writeln('Name: ${personal.fullName}');

    if (cvData.workExperience.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Berufserfahrung:');
      for (final job in cvData.workExperience) {
        final start = job.startDate.year;
        final end = job.isCurrent ? 'heute' : '${job.endDate!.year}';
        buffer.write('- ${job.position} bei ${job.company} ($start-$end)');
        if (job.description?.isNotEmpty == true) {
          buffer.write(': ${_firstSentences(job.description!, 2)}');
        }
        buffer.writeln();
      }
    }

    if (cvData.education.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Ausbildung:');
      for (final edu in cvData.education) {
        buffer.writeln(
          '- ${edu.degree}, ${edu.institution} '
          '(${edu.startDate.year}-${edu.endDate?.year ?? 'heute'})',
        );
      }
    }

    if (cvData.certificates.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Zertifikate:');
      for (final cert in cvData.certificates) {
        buffer.writeln('- ${cert.name} (${cert.issuer})');
      }
    }

    if (cvData.skills.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        'Kenntnisse: ${cvData.skills.map((s) => s.name).join(', ')}',
      );
    }

    return buffer.toString();
  }

  /// Kürzt lange Beschreibungen auf die ersten [count] Sätze,
  /// damit der Prompt kompakt bleibt.
  static String _firstSentences(String text, int count) {
    final sentences = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+'));
    final taken = sentences.take(count).join(' ');
    return taken.length > 200 ? '${taken.substring(0, 197)}…' : taken;
  }
}
