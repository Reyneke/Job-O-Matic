import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/models/job_offer.dart';
import 'package:job_o_matic/data/services/api/api_client.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/api/serp_api_service.dart';
import 'package:logging/logging.dart';

void main() {
  group('SerpApiService', () {
    late SerpApiService service;

    SerpApiService build(
      MockClient mockClient, {
      Future<String?> Function()? keyLoader,
    }) {
      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      return SerpApiService(
        client: apiClient,
        keyService: ApiKeyService(),
        keyLoader: keyLoader ?? () async => 'test-key',
      );
    }

    test('parses a job from a google_jobs response', () async {
      service = build(MockClient((request) async {
        expect(request.url.host, 'serpapi.com');
        expect(request.url.queryParameters['engine'], 'google_jobs');
        expect(request.url.queryParameters['gl'], 'de');
        return http.Response(
          jsonEncode(_sampleResponse()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }));

      final jobs = await service.search(query: 'Flutter', location: 'Berlin');

      expect(jobs, hasLength(1));
      final job = jobs.first;
      expect(job.id, 'serp-test-1');
      expect(job.title, 'Flutter Entwickler (m/w/d)');
      expect(job.company, 'Beispiel GmbH');
      expect(job.location, 'Berlin, Deutschland');
      expect(
        job.url,
        'https://www.google.com/search?ibp=htl;jobs&q=flutter',
      );
      expect(job.source, 'serpapi');
      expect(job.employmentType, EmploymentType.fullTime);
      expect(job.workModel, WorkModel.remote);
      expect(job.publishedAt, isNull);
    });

    test('combines description and job_highlights', () async {
      service = build(MockClient(
          (request) async => http.Response(jsonEncode(_sampleResponse()), 200)));

      final jobs = await service.search(query: 'Flutter');
      final description = jobs.first.description!;

      expect(description, contains('Entwicklung von Flutter-Apps'));
      expect(description, contains('- Erfahrung mit Dart'));
      expect(description, contains('- Homeoffice möglich'));
    });

    test('maps Part-time schedule to partTime employment type', () async {
      final data = _sampleResponse();
      final jobMap = (data['jobs_results'] as List).first
          as Map<String, dynamic>;
      jobMap['detected_extensions'] = {
        'schedule_type': 'Part-time',
      };
      // Neutrale Beschreibung ohne Remote-/Homeoffice-Hinweis, damit der
      // WorkModel-Fallback keinen falschen Wert liefert.
      jobMap['description'] = 'Allgemeine Buerotactigkeiten in Hamburg.';
      jobMap['job_highlights'] = <Object>[];
      service = build(MockClient(
          (request) async => http.Response(jsonEncode(data), 200)));

      final jobs = await service.search(query: 'Flutter');
      expect(jobs.first.employmentType, EmploymentType.partTime);
      // Kein work_from_home und keine remote-Beschreibung → unbewertbar.
      expect(jobs.first.workModel, isNull);
    });

    test('parses salary from detected_extensions', () async {
      final data = _sampleResponse();
      final jobMap = (data['jobs_results'] as List).first
          as Map<String, dynamic>;
      (jobMap['detected_extensions'] as Map<String, dynamic>)
          ['salary_range'] = '60.000 € – 80.000 €';
      service = build(MockClient((request) async => http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'})));

      final jobs = await service.search(query: 'Flutter');
      expect(jobs.first.salaryRange, '60.000 € – 80.000 €');
    });

    test('returns empty list when jobs_results is missing', () async {
      service = build(MockClient(
          (request) async => http.Response(jsonEncode({'search_metadata': {}}),
              200)));

      final jobs = await service.search(query: 'Nichts');
      expect(jobs, isEmpty);
    });

    test('throws JobApiException when the key is missing', () async {
      service = build(MockClient((request) async => http.Response('', 500)),
          keyLoader: () async => null);

      expect(
        () => service.search(query: 'Flutter'),
        throwsA(isA<JobApiException>()),
      );
    });

    test('throws JobApiException on non-200 response', () async {
      service = build(
          MockClient((request) async => http.Response('server error', 500)));

      expect(
        () => service.search(query: 'Flutter'),
        throwsA(isA<JobApiException>()),
      );
    });

    test('throws JobApiException when response contains an error object',
        () async {
      service = build(MockClient((request) async => http.Response(
          jsonEncode({
            'error': 'Quota exceeded - limit reached',
          }),
          200)));

      expect(
        () => service.search(query: 'Flutter'),
        throwsA(isA<JobApiException>()),
      );
    });
  });
}

/// Beispiel-Response der SerpAPI-Google-Jobs-Suche.
Map<String, dynamic> _sampleResponse() {
  return {
    'search_metadata': {'id': 'x'},
    'jobs_results': [
      {
        'job_id': 'serp-test-1',
        'title': 'Flutter Entwickler (m/w/d)',
        'company_name': 'Beispiel GmbH',
        'location': 'Berlin, Deutschland',
        'description': 'Entwicklung von Flutter-Apps.\n',
        'job_highlights': [
          {
            'title': 'Qualifikationen',
            'items': ['Erfahrung mit Dart', 'Teamfähigkeit'],
          },
          {
            'title': 'Vorteile',
            'items': ['Homeoffice möglich'],
          },
        ],
        'detected_extensions': {
          'schedule_type': 'Full-time',
          'work_from_home': true,
        },
        'share_link': 'https://www.google.com/search?ibp=htl;jobs&q=flutter',
      }
    ],
  };
}
