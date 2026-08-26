import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/services/ai/cover_letter_ai_service.dart';
import 'package:job_o_matic/data/services/ai/cover_letter_prompt_builder.dart';
import 'package:job_o_matic/data/services/ai/gemini_cover_letter_ai_service.dart';
import 'package:job_o_matic/models/application.dart';
import 'package:job_o_matic/models/cv_data.dart';
import 'package:logging/logging.dart';

http.Response _geminiResponse(String text) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'finishReason': 'STOP',
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

const String _validLetter =
    'Sehr geehrte Damen und Herren,\n\n'
    'mit großem Interesse habe ich Ihre Stellenausschreibung als Flutter '
    'Entwickler bei der Bliq gelesen. Als Diplom-Ingenieur mit mehrjähriger '
    'Erfahrung in der Softwareentwicklung bringe ich fundierte Kenntnisse in '
    'Dart und C++ mit, die ich in mehreren Projekten unter Beweis stellen '
    'konnte.\n\n'
    'Besonders reizt mich an der ausgeschriebenen Position die Verbindung von '
    'Cross-Platform-Entwicklung und modernen Architekturen. In meiner bisherigen '
    'Tätigkeit habe ich mehrfach eigenverantwortlich Apps konzipiert und '
    'umgesetzt.\n\n'
    'Gerne überzeuge ich Sie in einem persönlichen Gespräch von meinen '
    'Fähigkeiten.\n\n'
    'Mit freundlichen Grüßen\n'
    'Max Mustermann';

Application _sampleApplication() => Application(
  id: 42,
  jobTitle: 'Flutter Entwickler',
  company: 'Bliq',
  jobUrl: 'https://example.com/job/42',
  jobDescription:
      'Wir suchen einen Flutter Entwickler (m/w/d) für '
      'unser mobiles Team. Erfahrung mit Dart und REST-APIs erwünscht.',
  createdAt: DateTime(2026, 8, 24),
);

CvData _sampleCvData() => CvData(
  personalData: PersonalData(firstName: 'Max', lastName: 'Mustermann'),
  workExperience: [
    WorkExperience(
      company: 'Tech GmbH',
      position: 'Softwareentwickler',
      startDate: DateTime(2020, 1, 1),
      description:
          'Entwicklung von Cross-Platform-Apps. Pflege von '
          'REST-Schnittstellen.',
    ),
  ],
  education: [
    Education(
      institution: 'TFH Berlin',
      degree: 'Diplom-Ingenieur',
      startDate: DateTime(2010, 10, 1),
      endDate: DateTime(2015, 3, 31),
    ),
  ],
  skills: const [
    Skill(name: 'Dart', proficiency: 0.9),
    Skill(name: 'C++', proficiency: 0.8),
  ],
);

GeminiCoverLetterAiService _service({
  required http.Client client,
  Future<String?> Function()? apiKeyLoader,
}) {
  return GeminiCoverLetterAiService(
    logger: Logger('Test'),
    apiKeyLoader: apiKeyLoader ?? (() async => 'test-api-key'),
    client: client,
  );
}

void main() {
  group('GeminiCoverLetterAiService', () {
    test('erzeugt Anschreiben aus valider Gemini-Antwort', () async {
      http.Request? captured;
      final service = _service(
        client: MockClient((request) async {
          captured = request;
          return _geminiResponse(_validLetter);
        }),
      );

      final result = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result, contains('Sehr geehrte Damen und Herren,'));
      expect(result, contains('Mit freundlichen Grüßen'));
      // Sanitizing: kein Markdown im Ergebnis
      expect(result.contains('*'), isFalse);

      // Request-Prüfungen
      expect(captured!.url.host, 'generativelanguage.googleapis.com');
      expect(captured!.url.path, contains('/v1beta/models/'));
      expect(captured!.url.path, contains(':generateContent'));
      expect(captured!.url.queryParameters['key'], 'test-api-key');

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      final prompt = (body['contents'][0]['parts'][0] as Map)['text'] as String;

      // Prompt enthält Jobdaten, CV-Daten und die harten Regeln
      expect(prompt, contains('Flutter Entwickler'));
      expect(prompt, contains('Bliq'));
      expect(prompt, contains('Max Mustermann'));
      expect(prompt, contains('Dart'));
      expect(prompt, contains('<stellenanzeige>'));
      expect(prompt, contains('</stellenanzeige>'));
      expect(prompt, contains('Erfinde KEINE Fakten'));

      // GenerationConfig gesetzt
      expect(body['generationConfig'], isNotNull);
    });

    test('providerName enthält das Modell', () {
      final service = GeminiCoverLetterAiService(
        apiKeyLoader: () async => 'key',
        model: 'gemini-test-model',
      );
      expect(service.providerName, contains('gemini-test-model'));
    });

    test('Standardmodell ist ein verfügbares Gemini-Flash-Modell', () {
      // gemini-2.5-flash existiert nicht (HTTP 404); die Standard-Modelle
      // sind gemäß https://ai.google.dev/gemini-api/docs/models die
      // gemini-3.x-Flash-Modelle.
      final model = GeminiCoverLetterAiService.defaultModel;
      expect(model, isNotEmpty);
      expect(model, isNot('gemini-2.5-flash'));
      expect(
        model,
        anyOf(
          'gemini-3.5-flash',
          'gemini-3.6-flash',
          'gemini-3.7-flash',
          'gemini-3.5-flash-lite',
          'gemini-2.0-flash',
          'gemini-1.5-flash',
        ),
      );
    });

    test('wirft Exception ohne konfigurierten API-Key', () async {
      final service = _service(
        client: MockClient((request) async => _geminiResponse(_validLetter)),
        apiKeyLoader: () async => null,
      );

      await expectLater(
        service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(isA<CoverLetterAiException>()),
      );
    });

    test('wirft Exception bei leerem API-Key', () async {
      final service = _service(
        client: MockClient((request) async => _geminiResponse(_validLetter)),
        apiKeyLoader: () async => '  ',
      );

      await expectLater(
        service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(isA<CoverLetterAiException>()),
      );
    });
    test('wirft Exception bei HTTP-Fehler (500)', () async {
      final service = _service(
        client: MockClient(
          (request) async => http.Response('Internal Server Error', 500),
        ),
      );

      await expectLater(
        service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(
          isA<CoverLetterAiException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 500'),
          ),
        ),
      );
    });

    test(
      'wirft Exception bei fehlenden candidates (Sicherheitsfilter)',
      () async {
        final service = _service(
          client: MockClient(
            (request) async =>
                http.Response(jsonEncode({'candidates': []}), 200),
          ),
        );

        await expectLater(
          service.generateCoverLetter(
            cvData: _sampleCvData(),
            application: _sampleApplication(),
          ),
          throwsA(isA<CoverLetterAiException>()),
        );
      },
    );

    test('wirft Exception wenn Antwort zu kurz ist', () async {
      final service = _service(
        client: MockClient((request) async => _geminiResponse('Zu kurz.')),
      );

      await expectLater(
        service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        ),
        throwsA(
          isA<CoverLetterAiException>().having(
            (e) => e.message,
            'message',
            contains('zu kurz'),
          ),
        ),
      );
    });

    test('sanitized Markdown in der KI-Antwort weg', () async {
      const markdownLetter =
          '**Sehr geehrte Damen und Herren,**\n\n'
          '# Bewerbung\n\n'
          '- Punkt eins mit ausreichend Text um lang genug zu sein\n'
          '- Punkt zwei mit ebenfalls genügend Zeichen für die Prüfung hier\n'
          '- Punkt drei rundet die Liste ab damit alles plausibel bleibt\n'
          '- Punkt vier als letzter Eintrag der Liste für die Vollständigkeit';
      final service = _service(
        client: MockClient((request) async => _geminiResponse(markdownLetter)),
      );

      final result = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result.contains('**'), isFalse);
      expect(result.contains('#'), isFalse);
      expect(result.startsWith('- '), isFalse);
    });

    test('filtert thought-Parts von Reasoning-Modellen heraus', () async {
      // Gemini 2.5+/3.x (Reasoning-Modelle) liefern "thought"-Parts mit dem
      // Flag `thought: true` in der Antwort. Diese internen Gedanken dürfen
      // NICHT im Anschreiben landen – nur der sichtbare `text`.
      const thoughtText =
          '5: Formal closing (optional or combined with 4 to respect '
          'the 5-paragraph limit). Keep it to 4 or 5 paragraphs.';
      final service = _service(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': thoughtText, 'thought': true},
                      {'text': _validLetter},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final result = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(result, contains('Sehr geehrte Damen und Herren,'));
      expect(result, isNot(contains('Formal closing')));
      expect(result, isNot(contains('5-paragraph')));
    });

    test(
      'sendet thinkingConfig mit includeThoughts=false und thinkingBudget',
      () async {
        http.Request? captured;
        final service = _service(
          client: MockClient((request) async {
            captured = request;
            return _geminiResponse(_validLetter);
          }),
        );

        await service.generateCoverLetter(
          cvData: _sampleCvData(),
          application: _sampleApplication(),
        );

        final body = jsonDecode(captured!.body) as Map<String, dynamic>;
        final generationConfig =
            body['generationConfig'] as Map<String, dynamic>;
        expect(generationConfig['thinkingConfig'], {
          'includeThoughts': false,
          'thinkingBudget': CoverLetterPromptBuilder.thinkingBudget,
        });
        expect(
          generationConfig['maxOutputTokens'],
          GeminiCoverLetterAiService.outputBudgets.first,
        );
      },
    );

    test('erhöht Output-Budget bei MAX_TOKENS und liefert vollständige '
        'Antwort beim nächsten Versuch', () async {
      // Erste Antwort wird abgeschnitten (MAX_TOKENS), zweite (mit höherem
      // Budget) liefert das vollständige Anschreiben. Der Service muss
      // automatisch weitermachen statt den abgeschnittenen Text zu liefern.
      final sentBudgets = <int>[];
      const truncatedLetter =
          'Sehr geehrte Damen und Herren,\n\n'
          'mit großem Interesse bewerbe ich mich bei Bliq für die Position '
          'als Senior Flutter Developer. Als Diplom-Ingenieur fü';
      var calls = 0;
      final service = _service(
        client: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final cfg = body['generationConfig'] as Map<String, dynamic>;
          final maxTokens = cfg['maxOutputTokens'] as int;
          sentBudgets.add(maxTokens);
          if (calls < 2) {
            // Erste Antwort abgeschnitten.
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'MAX_TOKENS',
                    'content': {
                      'parts': [
                        {'text': truncatedLetter},
                      ],
                    },
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          // Zweite Antwort vollständig.
          return _geminiResponse(_validLetter);
        }),
      );

      final result = await service.generateCoverLetter(
        cvData: _sampleCvData(),
        application: _sampleApplication(),
      );

      expect(calls, 2);
      expect(result, contains('Sehr geehrte Damen und Herren,'));
      expect(result, isNot(contains('Als Diplom-Ingenieur fü')));
      // Budget muss im zweiten Versuch größer sein als im ersten.
      expect(sentBudgets, hasLength(2));
      expect(sentBudgets[1], greaterThan(sentBudgets[0]));
    });

    test(
      'bricht bei finishReason MAX_TOKENS ab (abgeschnittene Antwort)',
      () async {
        // Wenn das Token-Limit (Thinking + Output) erreicht wird, setzt Gemini
        // `finishReason: MAX_TOKENS`. Der Text endet dann mitten im Satz und
        // darf NICHT als fertiges Anschreiben gespeichert werden – stattdessen
        // CoverLetterAiException, damit Fallback/Neuversuch greifen.
        const truncatedLetter =
            'Sehr geehrte Damen und Herren,\n\n'
            'mit großem Interesse bewerbe ich mich bei Bliq für die Position als '
            'Senior Flutter Developer und Client Engineer. Als Diplom-Ingenieur fü';
        final service = _service(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'MAX_TOKENS',
                    'content': {
                      'parts': [
                        {'text': truncatedLetter},
                      ],
                    },
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );

        await expectLater(
          service.generateCoverLetter(
            cvData: _sampleCvData(),
            application: _sampleApplication(),
          ),
          throwsA(
            isA<CoverLetterAiException>().having(
              (e) => e.message,
              'message',
              contains('MAX_TOKENS'),
            ),
          ),
        );
      },
    );
  });
}
