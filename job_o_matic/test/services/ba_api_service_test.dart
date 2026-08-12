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
  });
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