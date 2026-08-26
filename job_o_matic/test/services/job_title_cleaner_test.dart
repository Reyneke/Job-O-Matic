import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/api/job_title_cleaner.dart';

void main() {
  group('JobTitleCleaner', () {
    test('entfernt "| Jobs at X" Suffix', () {
      const raw =
          'Senior Flutter Developer / Client Engineer, '
          'AI-Native and Rust-Friendly (m/f/d) | Jobs at Bliq';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(
        cleaned,
        'Senior Flutter Developer / Client Engineer, '
        'AI-Native and Rust-Friendly (m/f/d)',
      );
    });

    test('entfernt "- Jobs bei X" Suffix', () {
      const raw = 'Flutter Entwickler - Jobs bei Bliq';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, 'Flutter Entwickler');
    });

    test('entfernt "| Careers at X" Suffix', () {
      const raw = 'Senior Backend Engineer | Careers at Acme';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, 'Senior Backend Engineer');
    });

    test('entfernt "| X Recruiting" Suffix', () {
      const raw = 'DevOps Engineer | Talent Recruiting';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, 'DevOps Engineer');
    });

    test('lässt Titel ohne Suffix unverändert', () {
      const raw = 'Senior Flutter Developer (m/f/d)';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, raw);
    });

    test('gibt leeren String bei leerem Input zurück', () {
      expect(JobTitleCleaner.cleanJobTitle(''), '');
    });

    test('normalisiert doppelte Leerzeichen', () {
      const raw = 'Flutter   Developer   (m/w/d)';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, 'Flutter Developer (m/w/d)');
    });

    test('schneidet nicht bei Titel mit Bindestrich als Teil ab', () {
      const raw = 'Senior-Architekten-Entwickler (m/f/d)';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, 'Senior-Architekten-Entwickler (m/f/d)');
    });

    test('normalisiert Mojibake-En-Dash und entfernt Site-Suffix', () {
      // En-Dash "–" (U+2013, UTF-8 E2 80 93) als Windows-1252 interpretiert
      // ergibt "â€“" (â + € + " = U+00E2 U+20AC U+201C). Ohne Normalisierung
      // schlägt die Trennzeichen-Regex fehl und der Site-Suffix bleibt.
      const raw =
          'Flutter Entwickler '
          '\u00e2\u20ac\u201c StudySmarter \u00e2\u20ac\u201c Talents bei Flutter';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      // Der Cleaner entfernt NUR den letzten Suffix (Talents bei Flutter)
      expect(cleaned, 'Flutter Entwickler StudySmarter');
    });

    test('normalisiert Mojibake-Em-Dash und entfernt Site-Suffix', () {
      // Em-Dash "—" (U+2014, UTF-8 E2 80 94) als Windows-1252 interpretiert
      // ergibt "â€œ" (â + € + " = U+00E2 U+20AC U+201D).
      const raw =
          'Flutter Entwickler '
          '\u00e2\u20ac\u201d StudySmarter \u00e2\u20ac\u201d Talents bei Flutter';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, 'Flutter Entwickler StudySmarter');
    });

    test('entfernt Portal-Suffix mit Mojibake-En-Dash vollständig', () {
      // Realszenario aus dem Log: Titel mit "|" + Portal-Suffix,
      // der Mojibake-En-Dashes enthält (StudySmarter-Portal).
      const raw =
          'Flutter Entwickler bei NEON Software Solutions | '
          'Jetzt bewerben! \u00e2\u20ac\u201c StudySmarter '
          '\u00e2\u20ac\u201c Talents bei Flutter Entwickler';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, 'Flutter Entwickler bei NEON Software Solutions');
    });

    test('normalisiert Mojibake bei deutschen Umlauten', () {
      // ü (U+00FC, UTF-8 C3 BC) als Windows-1252 interpretiert ergibt "Ã¼"
      const raw = 'Flutter Entwickler f\u00c3\u00bcr Studienplattform';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned, 'Flutter Entwickler für Studienplattform');
    });

    test('normalisiert Mojibake-Anführungszeichen', () {
      // Right single quote "'" (U+2019, UTF-8 E2 80 99) als Windows-1252
      // interpretiert ergibt "â€™" (â + € + ™ = U+00E2 U+20AC U+2122)
      const raw =
          'Flutter Entwickler '
          '\u00e2\u20ac\u2122 with more text here';
      final cleaned = JobTitleCleaner.cleanJobTitle(raw);
      expect(cleaned.contains('\u00e2\u20ac\u2122'), isFalse);
      expect(cleaned.contains('\u2019'), isTrue);
    });
  });
}
