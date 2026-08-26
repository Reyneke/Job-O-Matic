import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/models/application.dart';

void main() {
  group('Application.coverLetterText (Persistenz Phase 1)', () {
    final now = DateTime(2026, 8, 24, 12, 30);

    test('ist standardmäßig null', () {
      final app = Application(
        id: 1,
        jobTitle: 'Flutter Entwickler',
        company: 'Bliq',
        jobUrl: 'https://example.com/job/1',
        createdAt: now,
      );
      expect(app.coverLetterText, isNull);
    });

    test('wird im Konstruktor gesetzt', () {
      final app = Application(
        id: 1,
        jobTitle: 'Flutter Entwickler',
        company: 'Bliq',
        jobUrl: 'https://example.com/job/1',
        createdAt: now,
        coverLetterText: 'Sehr geehrte Damen und Herren,',
      );
      expect(app.coverLetterText, 'Sehr geehrte Damen und Herren,');
    });

    test('copyWith setzt den Text', () {
      final app = Application(
        id: 1,
        jobTitle: 'Flutter Entwickler',
        company: 'Bliq',
        jobUrl: 'https://example.com/job/1',
        createdAt: now,
      );
      final updated = app.copyWith(coverLetterText: 'Neuer Text');
      expect(updated.coverLetterText, 'Neuer Text');
      // Original bleibt unverändert
      expect(app.coverLetterText, isNull);
    });

    test('copyWith behält bestehenden Text bei anderen Änderungen', () {
      final app = Application(
        id: 1,
        jobTitle: 'Flutter Entwickler',
        company: 'Bliq',
        jobUrl: 'https://example.com/job/1',
        createdAt: now,
        coverLetterText: 'Gespeicherter Brief',
      );
      final updated =
          app.copyWith(status: ApplicationStatus.completed, pdfPath: '/x.pdf');
      expect(updated.coverLetterText, 'Gespeicherter Brief');
    });

    test('JSON-Roundtrip mit Text', () {
      final app = Application(
        id: 7,
        jobTitle: 'Flutter Entwickler',
        company: 'Bliq',
        jobUrl: 'https://example.com/job/1',
        createdAt: now,
        coverLetterText: 'Absatz 1\n\nAbsatz 2',
      );
      final restored = Application.fromJson(app.toJson());
      expect(restored.coverLetterText, 'Absatz 1\n\nAbsatz 2');
    });

    test('JSON-Roundtrip ohne Text', () {
      final app = Application(
        id: 8,
        jobTitle: 'Flutter Entwickler',
        company: 'Bliq',
        jobUrl: 'https://example.com/job/1',
        createdAt: now,
      );
      final json = app.toJson();
      expect(json.containsKey('coverLetterText'), isTrue);
      expect(json['coverLetterText'], isNull);

      final restored = Application.fromJson(json);
      expect(restored.coverLetterText, isNull);
    });
  });
}
