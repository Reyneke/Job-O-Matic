import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/ai/cover_letter_sanitizer.dart';

void main() {
  group('CoverLetterSanitizer', () {
    test('entfernt Markdown-Fettdruck', () {
      final result = CoverLetterSanitizer.sanitize(
        '**Sehr geehrte Damen und Herren,**\n\nIch bewerbe mich.',
      );
      expect(result, contains('Sehr geehrte Damen und Herren,'));
      expect(result.contains('**'), isFalse);
    });

    test('entfernt Markdown-Kursivdruck und Code-Markierung', () {
      final result = CoverLetterSanitizer.sanitize(
        '*Mit* großem Interesse habe ich `Flutter` gelesen.',
      );
      expect(result.contains('*'), isFalse);
      expect(result.contains('`'), isFalse);
      expect(
        result,
        contains('Mit großem Interesse habe ich Flutter gelesen.'),
      );
    });

    test('entfernt Überschriften-Marker', () {
      final result = CoverLetterSanitizer.sanitize(
        '# Anschreiben\n\nHier mein Text.',
      );
      expect(result.contains('#'), isFalse);
      expect(result, contains('Anschreiben'));
    });

    test('entfernt Bullet-Points am Zeilenanfang', () {
      final result = CoverLetterSanitizer.sanitize(
        '- Erfahrung mit Flutter\n- Kenntnisse in Dart',
      );
      expect(result.startsWith('- '), isFalse);
      expect(result, contains('Erfahrung mit Flutter'));
    });

    test('entfernt Nummerierungen am Zeilenanfang', () {
      final result = CoverLetterSanitizer.sanitize(
        '1. Erster Punkt\n2) Zweiter Punkt',
      );
      expect(result, isNot(contains('1.')));
      expect(result, isNot(contains('2)')));
    });

    test(
      'normalisiert Absätze: harte Zeilenumbrüche werden zu Leerzeichen',
      () {
        final result = CoverLetterSanitizer.sanitize(
          'Erste Zeile\nzweite Zeile\n\ndritter Absatz',
        );
        expect(result, 'Erste Zeile zweite Zeile\n\ndritter Absatz');
      },
    );

    test('fasst mehrfache Leerzeichen zusammen', () {
      final result = CoverLetterSanitizer.sanitize(
        'Zu   viele     Leerzeichen',
      );
      expect(result, 'Zu viele Leerzeichen');
    });

    test('begrenzt die Anzahl der Absätze', () {
      const raw = 'A\n\nB\n\nC\n\nD\n\nE\n\nF\n\nG\n\nH';
      final result = CoverLetterSanitizer.sanitize(raw);
      expect(
        result.split('\n\n'),
        hasLength(CoverLetterSanitizer.maxParagraphs),
      );
    });

    test('begrenzt die Anzahl der Absätze mit eigenem Limit', () {
      const raw = 'A\n\nB\n\nC';
      final result = CoverLetterSanitizer.sanitize(raw, maxParagraphs: 2);
      expect(result.split('\n\n'), hasLength(2));
      expect(result, startsWith('A'));
    });

    test('entfernt Emojis', () {
      final result = CoverLetterSanitizer.sanitize(
        'Sehr geehrte Damen und Herren, 🚀 ich freue mich auf Ihre Rückmeldung.',
      );
      expect(result.contains('🚀'), isFalse);
      expect(result, contains('ich freue mich auf Ihre Rückmeldung.'));
    });

    test('behandelt Windows-Zeilenumbrüche', () {
      final result = CoverLetterSanitizer.sanitize(
        'Absatz eins\r\n\r\nAbsatz zwei',
      );
      expect(result, 'Absatz eins\n\nAbsatz zwei');
    });

    test('gibt leeren String bei leerem Input zurück', () {
      expect(CoverLetterSanitizer.sanitize(''), '');
      expect(CoverLetterSanitizer.sanitize('   \n\n  \n'), '');
    });
  });

  group('CoverLetterSanitizer.isGarbage', () {
    const validLetter =
        'Sehr geehrte Damen und Herren,\n\n'
        'mit großem Interesse bewerbe ich mich bei Bliq für die Position als '
        'Flutter Entwickler. Als Diplom-Ingenieur mit mehrjähriger Erfahrung '
        'in der Softwareentwicklung bringe ich fundierte Kenntnisse in Dart und '
        'C++ mit. Gerne überzeuge ich Sie in einem persönlichen Gespräch von '
        'meinen Fähigkeiten.\n\n'
        'Mit freundlichen Grüßen\n'
        'Matthias Struck';

    test('erkennt leere/zu kurze Texte als korrupt', () {
      expect(CoverLetterSanitizer.isGarbage(''), isTrue);
      expect(CoverLetterSanitizer.isGarbage('   '), isTrue);
      expect(CoverLetterSanitizer.isGarbage('Kurz'), isTrue);
    });

    test('erkennt Reasoning-Gedankenkette als korrupt', () {
      const thoughtChain =
          '5: Formal closing (optional or combined with 4 to respect the '
          '5-paragraph limit).* Keep it to 4 or 5 paragraphs.\n'
          '**Refining Text to meet the requirements...';
      // Der Text enthält weder Anrede noch Grußformel und Reasoning-Marker.
      expect(CoverLetterSanitizer.isGarbage(thoughtChain), isTrue);
    });

    test('erkennt abgeschnittenen (verstümmelten) Text als korrupt', () {
      const truncated =
          'Sehr geehrte Damen und Herren,\n\n'
          'mit großem Interesse bewerbe ich mich bei Bliq für die Position als '
          'Senior Flutter Developer und Client Engineer. Als Diplom-Ingenieur fü';
      // Beginnt korrekt, aber bricht ab – keine Grußformel.
      expect(CoverLetterSanitizer.isGarbage(truncated), isTrue);
    });

    test('erkennt nummerierte Modell-Planung als korrupt', () {
      const planned =
          '1: Opening paragraph\n\n'
          '2: Introduce experience\n\n'
          '3: Highlight skills\n\n'
          '4: Closing statement';
      expect(CoverLetterSanitizer.isGarbage(planned), isTrue);
    });

    test('bewertet gültiges deutsches Anschreiben als NICHT korrupt', () {
      expect(CoverLetterSanitizer.isGarbage(validLetter), isFalse);
    });
  });
}
