import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/api/job_title_cleaner.dart';

void main() {
  group('JobTitleCleaner', () {
    test('entfernt "| Jobs at X" Suffix', () {
      const raw = 'Senior Flutter Developer / Client Engineer, '
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
  });
}