import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/ai/cover_letter_ai_service.dart';
import 'package:job_o_matic/models/application.dart';
import 'package:job_o_matic/models/cv_data.dart';

/// Fake-Implementierung zur Überprüfung des Interface-Vertrags.
class FakeCoverLetterAiService implements CoverLetterAiService {
  @override
  String get providerName => 'Fake';

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async {
    return 'Sehr geehrte Damen und Herren,\n\n'
        'mit großem Interesse habe ich Ihre Stellenausschreibung als '
        '${application.jobTitle} bei ${application.company} gelesen.\n\n'
        'Mit freundlichen Grüßen';
  }
}

class ThrowingCoverLetterAiService implements CoverLetterAiService {
  @override
  String get providerName => 'Throwing';

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async {
    throw const CoverLetterAiException('Kontingent erschöpft');
  }
}

Application _sampleApplication() => Application(
      id: 1,
      jobTitle: 'Flutter Entwickler',
      company: 'Bliq',
      jobUrl: 'https://example.com/job/1',
      createdAt: DateTime(2026, 8, 24),
    );

CvData _sampleCvData() => CvData(
      personalData: PersonalData(
        firstName: 'Max',
        lastName: 'Mustermann',
      ),
      skills: [const Skill(name: 'Dart', proficiency: 0.9)],
    );

void main() {
  group('CoverLetterAiService (Interface-Vertrag)', () {
    test('liefert reinen Fließtext ohne Markdown', () async {
      final service = FakeCoverLetterAiService();
      final text = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(text, isNotEmpty);
      expect(text.contains('**'), isFalse, reason: 'Kein Markdown erlaubt');
      expect(text.contains('#'), isFalse, reason: 'Keine Überschriften erlaubt');
      expect(text.startsWith('- '), isFalse, reason: 'Keine Listen erlaubt');
    });

    test('verwendet Jobdaten aus der Application', () async {
      final service = FakeCoverLetterAiService();
      final text = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(text, contains('Flutter Entwickler'));
      expect(text, contains('Bliq'));
    });

    test('providerName ist nicht leer', () {
      expect(FakeCoverLetterAiService().providerName, isNotEmpty);
    });
  });

  group('CoverLetterAiException', () {
    test('enthält Nachricht', () {
      const exception = CoverLetterAiException('Kontingent erschöpft');
      expect(exception.toString(), contains('Kontingent erschöpft'));
      expect(exception.message, 'Kontingent erschöpft');
    });

    test('enthält Ursache, wenn vorhanden', () {
      const exception = CoverLetterAiException(
        'Request fehlgeschlagen',
        cause: 'HTTP 500',
      );
      expect(exception.toString(), contains('HTTP 500'));
    });

    test('wird vom Service geworfen und kann gefangen werden', () async {
      final service = ThrowingCoverLetterAiService();

      await expectLater(
        service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(isA<CoverLetterAiException>()),
      );
    });
  });
}
