import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/ai/cover_letter_prompt_builder.dart';
import 'package:job_o_matic/models/application.dart';
import 'package:job_o_matic/models/cv_data.dart';

void main() {
  final application = Application(
    id: 1,
    jobTitle: 'Flutter Entwickler',
    company: 'Bliq',
    jobUrl: 'https://example.com/job/1',
    jobDescription: 'Wir suchen einen Flutter Entwickler.',
    createdAt: DateTime(2026, 8, 24),
  );

  final cvData = CvData(
    personalData: PersonalData(firstName: 'Max', lastName: 'Mustermann'),
    skills: const [Skill(name: 'Dart', proficiency: 0.9)],
  );

  group('CoverLetterPromptBuilder', () {
    test('enthält die harte Regel "Erfinde KEINE Fakten"', () {
      final prompt = CoverLetterPromptBuilder.build(cvData, application);
      expect(prompt, contains('Erfinde KEINE Fakten'));
    });

    test('verbietet Markdown, Listen und Emojis', () {
      final prompt = CoverLetterPromptBuilder.build(cvData, application);
      expect(prompt, contains('kein Markdown'));
      expect(prompt, contains('keine Listen'));
      expect(prompt, contains('keine Emojis'));
    });

    test('begrenzt Länge im Prompt (5 Absätze, eine Din-A4-Seite)', () {
      final prompt = CoverLetterPromptBuilder.build(cvData, application);
      expect(prompt, contains('höchstens 5 Absätze'));
      expect(prompt, contains('Din-A4-Seite'));
    });

    test('markiert die Stellenanzeige als Daten (XML-Tags)', () {
      final prompt = CoverLetterPromptBuilder.build(cvData, application);
      expect(prompt, contains('<stellenanzeige>'));
      expect(prompt, contains('</stellenanzeige>'));
      expect(prompt, contains('<lebenslauf>'));
      expect(prompt, contains('</lebenslauf>'));
    });

    test('enthält Jobdaten', () {
      final prompt = CoverLetterPromptBuilder.build(cvData, application);
      expect(prompt, contains('Flutter Entwickler'));
      expect(prompt, contains('Bliq'));
      expect(prompt, contains('Wir suchen einen Flutter Entwickler.'));
    });

    test('enthält CV-Daten', () {
      final prompt = CoverLetterPromptBuilder.build(cvData, application);
      expect(prompt, contains('Max Mustermann'));
      expect(prompt, contains('Dart'));
    });

    test('nutzt Fallback-Text ohne Stellenbeschreibung', () {
      final appWithoutDescription = Application(
        id: 1,
        jobTitle: 'Flutter Entwickler',
        company: 'Bliq',
        jobUrl: '',
        createdAt: DateTime(2026, 8, 24),
      );
      final prompt =
          CoverLetterPromptBuilder.build(cvData, appWithoutDescription);
      expect(prompt, contains('Keine Beschreibung verfügbar'));
    });
  });
}
