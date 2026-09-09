import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/services/api/api_client.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/api/ba_api_service.dart';
import 'package:job_o_matic/data/models/job_offer.dart';
import 'package:logging/logging.dart';

void main() {
  group('BaApiService', () {
    late BaApiService service;
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(_sampleResponse()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);
    });

    test('parses jobs from verified BA response structure', () async {
      final jobs = await service.search(query: 'Flutter', size: 1);

      expect(jobs, hasLength(1));
      final job = jobs.first;

      expect(job.id, '12265-487930_JB5205113-S');
      expect(job.title, 'Ingenieur (m/w/d) Testautomatisierung Flutter und Dart');
      expect(job.company, 'FERCHAU GmbH Niederlassung Mannheim');
      expect(job.location, 'Mannheim');
      expect(job.url, 'https://www.arbeitsagentur.de/jobsuche/job/12265-487930_JB5205113-S');
      expect(job.source, 'ba');
      expect(job.publishedAt, DateTime(2026, 7, 24));
    });

    test('parses salary range from gehaltsspanne fields', () async {
      final jobs = await service.search(query: 'Flutter', size: 1);
      final job = jobs.first;

      expect(job.salaryRange, '45.000 € – 78.000 €');
    });

    test('parses employment type from arbeitszeitVollzeit', () async {
      final jobs = await service.search(query: 'Flutter', size: 1);
      final job = jobs.first;

      expect(job.employmentType, EmploymentType.fullTime);
    });

    test('handles multiple locations by joining with comma', () async {
      mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(_sampleResponseWithMultipleLocations()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      final jobs = await service.search(query: 'Flutter', size: 1);
      expect(jobs.first.location, 'Mannheim, Heidelberg');
    });

    test('returns empty list when ergebnisliste is missing', () async {
      mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'maxErgebnisse': 0, 'page': 1, 'size': 1}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      final jobs = await service.search(query: 'NichtVorhanden', size: 1);
      expect(jobs, isEmpty);
    });

    test('throws JobApiException on non-200 response', () async {
      mockClient = MockClient((request) async {
        return http.Response('error', 500);
      });

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      expect(
        () => service.search(query: 'Flutter'),
        throwsA(isA<JobApiException>()),
      );
    });

    test('base64EncodeRefnr kodiert eine Referenznummer URL-sicher', () {
      expect(
        BaApiService.base64EncodeRefnr('10001-1002716922-S'),
        'MTAwMDEtMTAwMjcxNjkyMi1T',
      );
    });

    test('fetchJobDetails parst die jobdetails-Antwort', () async {
      mockClient = MockClient((request) async {
        expect(request.url.path, contains('/jobdetails/'));
        return http.Response(
          jsonEncode(_sampleDetailsResponse()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      final details = await service.fetchJobDetails('12265-487930_JB5205113-S');

      expect(details.title, 'Ingenieur (m/w/d) Testautomatisierung Flutter und Dart');
      expect(details.company, 'FERCHAU GmbH Niederlassung Mannheim');
      expect(details.description, contains('Wir freuen uns auf Ihre Bewerbung'));
      expect(details.externalUrl, isNull);
      expect(details.primaryAddress, 'Jüdenstr. 31, 68163 Mannheim');
    });

    test('fetchJobDetails wirft JobApiException bei HTTP-Fehler', () async {
      mockClient = MockClient((request) async => http.Response('error', 500));

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      expect(
        () => service.fetchJobDetails('12265-487930_JB5205113-S'),
        throwsA(isA<JobApiException>()),
      );
    });

    test('marketStats zählt externe vs. interne Anzeigen (externeUrl)', () async {
      final items = [
        _sampleSearchItem(),
        _sampleSearchItem()..['externeUrl'] = 'https://www.get-in-it.de/job/1',
        _sampleSearchItem()..['externeUrl'] = 'https://firma.de/job/2',
      ];
      mockClient = MockClient((request) async => http.Response(
            jsonEncode({'ergebnisliste': items}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      final jobs = await service.search(query: 'Flutter');
      expect(jobs, hasLength(3));

      final stats = service.marketStats;
      expect(stats.searchedOffers, 3);
      expect(stats.externalOffers, 2);
      expect(stats.internalOffers, 1);
      expect(stats.externalShare, closeTo(2 / 3, 0.0001));
    });

    test('erkennt auch externeURL/allianzpartnerName in Such-Treffern', () async {
      final items = [
        _sampleSearchItem()..['externeURL'] = 'https://x.de/a',
        _sampleSearchItem()..['allianzpartnerName'] = 'get in GmbH',
        _sampleSearchItem(),
      ];
      mockClient = MockClient((request) async => http.Response(
            jsonEncode({'ergebnisliste': items}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      await service.search(query: 'Flutter');
      expect(service.marketStats.externalOffers, 2);
    });

    test('fetchJobDetails zählt interne Details-Abrufe', () async {
      mockClient = MockClient((request) async => http.Response(
            jsonEncode(_sampleDetailsResponse()),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      await service.fetchJobDetails('12265-487930_JB5205113-S');
      final stats = service.marketStats;
      expect(stats.detailsChecked, 1);
      expect(stats.externalDetails, 0);
      expect(stats.internalDetails, 1);
    });

    test('fetchJobDetails zählt externen Details-Abruf', () async {
      mockClient = MockClient((request) async => http.Response(
            jsonEncode(_sampleDetailsResponse(external: true)),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      service = BaApiService(client: apiClient);

      final details =
          await service.fetchJobDetails('12265-487930_JB5205113-S');
      expect(details.externalUrl, isNotNull);
      final stats = service.marketStats;
      expect(stats.detailsChecked, 1);
      expect(stats.externalDetails, 1);
      expect(stats.internalDetails, 0);
    });

    test('marketStats ohne Abrufe: Ratio 0.0', () {
      final stats = service.marketStats;
      expect(stats.searchedOffers, 0);
      expect(stats.externalOffers, 0);
      expect(stats.detailsChecked, 0);
      expect(stats.externalShare, 0.0);
      expect(stats.externalShareOfDetails, 0.0);
    });
  });
}

/// Ein einzelnes gültiges Such-Item (Basis ohne externe Felder). Die
/// Statistik-Tests versehen eine Kopie je nach Fall mit `externeUrl`/
/// `externeURL`/`allianzpartnerName`.
Map<String, dynamic> _sampleSearchItem() {
  return {
    'stellenangebotsart': 'ARBEIT',
    'stellenangebotsTitel': 'Teststelle (m/w/d)',
    'arbeitszeitVollzeit': true,
    'stellenlokationen': [
      {
        'adresse': {
          'plz': '68163',
          'ort': 'Mannheim',
          'region': 'BADEN_WUERTTEMBERG',
          'land': 'DEUTSCHLAND',
        }
      }
    ],
    'datumErsteVeroeffentlichung': '2026-07-24',
    'firma': 'Beispiel GmbH',
    'referenznummer': '12265-487930_JB5205113-S',
  };
}

/// Verifizierte BA-API-Response (Stand: 2026-07-26).
Map<String, dynamic> _sampleResponse() {
  return {
    'ergebnisliste': [
      {
        'stellenangebotsart': 'ARBEIT',
        'stellenangebotsTitel':
            'Ingenieur (m/w/d) Testautomatisierung Flutter und Dart',
        'arbeitszeitVollzeit': true,
        'gehaltsspanneVon': 45000.0,
        'gehaltsspanneBis': 78000.0,
        'stellenlokationen': [
          {
            'adresse': {
              'plz': '68163',
              'ort': 'Mannheim',
              'region': 'BADEN_WUERTTEMBERG',
              'land': 'DEUTSCHLAND',
            }
          }
        ],
        'datumErsteVeroeffentlichung': '2026-07-24',
        'hauptberuf': 'Ingenieur/in - Automatisierungstechnik',
        'firma': 'FERCHAU GmbH Niederlassung Mannheim',
        'referenznummer': '12265-487930_JB5205113-S',
        'alleBerufe': ['Ingenieur/in - Automatisierungstechnik'],
      }
    ],
    'maxErgebnisse': 1234,
    'page': 1,
    'size': 1,
  };
}

/// Response mit mehreren Standorten.
Map<String, dynamic> _sampleResponseWithMultipleLocations() {
  final data = _sampleResponse();
  final job = (data['ergebnisliste'] as List).first as Map<String, dynamic>;
  job['stellenlokationen'] = [
    {
      'adresse': {
        'plz': '68163',
        'ort': 'Mannheim',
        'region': 'BADEN_WUERTTEMBERG',
        'land': 'DEUTSCHLAND',
      }
    },
    {
      'adresse': {
        'plz': '69115',
        'ort': 'Heidelberg',
        'region': 'BADEN_WUERTTEMBERG',
        'land': 'DEUTSCHLAND',
      }
    },
  ];
  return data;
}

/// Verifizierte `jobdetails`-Antwort der BA (Stand: 2026-09-07).
/// Mit [external] wird die Antwort als externe/Allianz-Anzeige markiert.
Map<String, dynamic> _sampleDetailsResponse({bool external = false}) {
  final map = <String, dynamic>{
    'stellenangebotsart': 'ARBEIT',
    'stellenangebotsTitel':
        'Ingenieur (m/w/d) Testautomatisierung Flutter und Dart',
    'stellenangebotsBeschreibung':
        'Willkommen im Team! Wir freuen uns auf Ihre Bewerbung.',
    'arbeitszeitVollzeit': true,
    'firma': 'FERCHAU GmbH Niederlassung Mannheim',
    'referenznummer': '12265-487930_JB5205113-S',
    'stellenlokationen': [
      {
        'adresse': {
          'strasseHausnummer': 'Jüdenstr. 31',
          'plz': '68163',
          'ort': 'Mannheim',
          'region': 'BADEN_WUERTTEMBERG',
          'land': 'DEUTSCHLAND',
        }
      }
    ],
  };
  if (external) {
    map['externeURL'] = 'https://www.get-in-it.de/jobsuche/p201881';
    map['allianzpartnerName'] = 'get in GmbH';
  }
  return map;
}
