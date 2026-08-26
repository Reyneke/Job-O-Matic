import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/services/ai/cover_letter_ai_service.dart';
import 'package:job_o_matic/data/services/ai/groq_cover_letter_ai_service.dart';
import 'package:job_o_matic/data/services/ai/mistral_cover_letter_ai_service.dart';
import 'package:job_o_matic/data/services/ai/fallback_cover_letter_ai_service.dart';
import 'package:job_o_matic/models/application.dart';
import 'package:job_o_matic/models/cv_data.dart';
import 'package:logging/logging.dart';

http.Response _chatResponse(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

const String _validLetter =
    'Sehr geehrte Damen und Herren,\n\n'
    'mit großem Interesse habe ich Ihre Stellenausschreibung als Flutter '
    'Entwickler bei der Bliq gelesen. Als Diplom-Ingenieur mit fundierten '
    'Kenntnissen in Dart und C++ möchte ich meine Erfahrung in der '
    'Cross-Platform-Entwicklung in Ihr Team einbringen.\n\n'
    'In meiner bisherigen Tätigkeit habe ich mehrfach eigenverantwortlich '
    'Softwareprojekte konzipiert, umgesetzt und im Betrieb betreut.\n\n'
    'Gerne überzeuge ich Sie in einem persönlichen Gespräch von meinen '
    'Fähigkeiten.\n\n'
    'Mit freundlichen Grüßen\n'
    'Max Mustermann';

Application _sampleApplication() => Application(
      id: 7,
      jobTitle: 'Flutter Entwickler',
      company: 'Bliq',
      jobUrl: 'https://example.com/job/7',
      createdAt: DateTime(2026, 8, 24),
    );

CvData _sampleCvData() => CvData(
      personalData: PersonalData(firstName: 'Max', lastName: 'Mustermann'),
    );

class FailingService implements CoverLetterAiService {
  @override
  String get providerName => 'Failing';

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async {
    throw const CoverLetterAiException('Kontingent erschöpft');
  }
}

void main() {
  group('MistralCoverLetterAiService', () {
    test('ruft die Mistral Chat-API mit Bearer-Token auf', () async {
      http.Request? captured;
      final service = MistralCoverLetterAiService(
        logger: Logger('Test'),
        apiKeyLoader: () async => 'mistral-key',
        client: MockClient((request) async {
          captured = request;
          return _chatResponse(_validLetter);
        }),
      );

      final result = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result, contains('Sehr geehrte Damen und Herren,'));
      expect(captured!.url.host, 'api.mistral.ai');
      expect(captured!.url.path, '/v1/chat/completions');
      expect(captured!.headers['Authorization'], 'Bearer mistral-key');

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['model'], MistralCoverLetterAiService.defaultModel);
      expect(
          (body['messages'] as List).first['content'],
          contains('<stellenanzeige>'));
    });

    test('providerName enthält Modell und Anbieter', () {
      final service = MistralCoverLetterAiService();
      expect(service.providerName, startsWith('Mistral ('));
    });
  });

  group('GroqCoverLetterAiService', () {
    test('ruft die Groq Chat-API mit dem Standardmodell auf', () async {
      http.Request? captured;
      final service = GroqCoverLetterAiService(
        logger: Logger('Test'),
        apiKeyLoader: () async => 'groq-key',
        client: MockClient((request) async {
          captured = request;
          return _chatResponse(_validLetter);
        }),
      );

      final result = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result, isNotEmpty);
      expect(captured!.url.host, 'api.groq.com');
      expect(captured!.url.path, '/openai/v1/chat/completions');
      expect(captured!.headers['Authorization'], 'Bearer groq-key');

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['model'], GroqCoverLetterAiService.defaultModel);
    });
  });
  group('OpenAI-kompatible Fehlerbehandlung', () {
    test('wirft Exception ohne API-Key', () async {
      final service = MistralCoverLetterAiService(
        logger: Logger('Test'),
        apiKeyLoader: () async => null,
        client: MockClient((request) async => _chatResponse(_validLetter)),
      );

      await expectLater(
        service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(isA<CoverLetterAiException>()),
      );
    });

    test('wirft Exception bei HTTP-Fehler', () async {
      final service = GroqCoverLetterAiService(
        logger: Logger('Test'),
        apiKeyLoader: () async => 'key',
        client: MockClient(
          (request) async => http.Response('error', 500),
        ),
      );

      await expectLater(
        service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(isA<CoverLetterAiException>()),
      );
    });

    test('wirft Exception bei leerer choices-Liste', () async {
      final service = MistralCoverLetterAiService(
        logger: Logger('Test'),
        apiKeyLoader: () async => 'key',
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode({'choices': []}), 200),
        ),
      );

      await expectLater(
        service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(isA<CoverLetterAiException>()),
      );
    });

    test('sanitized Markdown aus der Antwort', () async {
      const markdownLetter = '**Sehr geehrte Damen und Herren,**\n\n'
          '- Erster Punkt mit ausreichend Text um lang genug zu sein\n'
          '- Zweiter Punkt mit ebenfalls genügend Zeichen für die Prüfung\n'
          '- Dritter Punkt rundet die Liste ab damit alles plausibel bleibt';
      final service = GroqCoverLetterAiService(
        logger: Logger('Test'),
        apiKeyLoader: () async => 'key',
        client: MockClient(
          (request) async => _chatResponse(markdownLetter),
        ),
      );

      final result = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result.contains('**'), isFalse);
      expect(result.startsWith('- '), isFalse);
    });
  });
  group('FallbackCoverLetterAiService', () {
    test('nutzt den ersten Anbieter, wenn er erfolgreich ist', () async {
      var secondCalled = false;
      final chain = FallbackCoverLetterAiService([
        _SuccessfulService('Erster'),
        _CountingService('Zweiter', () => secondCalled = true),
      ]);

      final result = await chain.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result, 'Brief von Erster');
      expect(secondCalled, isFalse);
      expect(chain.providerName, contains('Erster'));
      expect(chain.providerName, contains('→'));
    });

    test('fällt auf den nächsten Anbieter zurück', () async {
      final chain = FallbackCoverLetterAiService([
        FailingService(),
        _SuccessfulService('Zweiter'),
      ]);

      final result = await chain.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result, 'Brief von Zweiter');
    });

    test('bricht nach erstem Erfolg ab (keine weiteren Aufrufe)', () async {
      final calls = <String>[];
      final chain = FallbackCoverLetterAiService([
        FailingService(),
        FailingService(),
        _RecordingService('C', calls),
        _SuccessfulService('D'),
      ]);

      final result = await chain.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result, 'Brief von D');
    });

    test('wirft Exception, wenn ALLE Anbieter fehlschlagen', () async {
      final chain = FallbackCoverLetterAiService([
        FailingService(),
        FailingService(),
      ]);

      await expectLater(
        chain.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(
          isA<CoverLetterAiException>().having(
            (e) => e.message,
            'message',
            contains('Alle KI-Anbieter fehlgeschlagen'),
          ),
        ),
      );
    });

    test('wirft Exception bei leerer Kette', () async {
      final chain = FallbackCoverLetterAiService([]);

      await expectLater(
        chain.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(isA<CoverLetterAiException>()),
      );
    });
  });
}

/// Hilfs-Services für die Fallback-Ketten-Tests.
class _SuccessfulService implements CoverLetterAiService {
  _SuccessfulService(this.name);

  final String name;

  @override
  String get providerName => name;

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async =>
      'Brief von $name';
}

class _CountingService extends _SuccessfulService {
  _CountingService(super.name, this.onCall);

  final void Function() onCall;

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async {
    onCall();
    return super.generateCoverLetter(cvData: cvData, application: application);
  }
}

class _RecordingService implements CoverLetterAiService {
  _RecordingService(this.name, this.calls);

  final String name;
  final List<String> calls;

  @override
  String get providerName => name;

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async {
    calls.add(name);
    throw CoverLetterAiException('$name nicht erreichbar');
  }
}

