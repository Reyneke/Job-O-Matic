import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/models/job_offer.dart';
import 'package:job_o_matic/data/services/api/api_client.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/api/careerjet_api_service.dart';
import 'package:job_o_matic/data/services/api/stable_hash.dart';
import 'package:logging/logging.dart';

void main() {
  group('CareerjetApiService', () {
    late CareerjetApiService service;

    /// Standard-IP-Echo: liefert eine gültige IP, damit kein echter Abruf
    /// von api.ipify.org nötig ist.
    MockClient okIpClient() => MockClient((request) async {
          expect(request.url.host, 'api.ipify.org');
          return http.Response(jsonEncode({'ip': '1.2.3.4'}), 200);
        });

    CareerjetApiService build(
      MockClient searchClient, {
      MockClient? ipClient,
      Future<String?> Function()? keyLoader,
    }) {
      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: searchClient,
      );
      return CareerjetApiService(
        client: apiClient,
        keyService: ApiKeyService(),
        ipClient: ipClient ?? okIpClient(),
        keyLoader: keyLoader ?? () async => 'test-key',
      );
    }

    String basicAuth(String key) =>
        'Basic ${base64Encode(utf8.encode('$key:'))}';

    test('sends request to Careerjet with required params + basic auth',
        () async {
      service = build(MockClient((request) async {
        expect(request.url.host, 'search.api.careerjet.net');
        expect(request.url.path, '/v4/query');
        expect(request.url.queryParameters['locale_code'], 'de_DE');
        expect(request.url.queryParameters['keywords'], 'Flutter');
        expect(request.url.queryParameters['pagesize'], '20');
        expect(request.url.queryParameters['page'], '1');
        expect(request.url.queryParameters['user_ip'], '1.2.3.4');
        expect(request.url.queryParameters['user_agent'], 'Job-O-Matic/1.0');
        expect(request.url.queryParameters['location'], 'Berlin');
        expect(request.url.queryParameters['radius'], '25');
        expect(request.headers['Authorization'], basicAuth('test-key'));
        return http.Response(jsonEncode(_sampleResponse()), 200,
            headers: {'content-type': 'application/json'});
      }));

      final jobs =
          await service.search(query: 'Flutter', location: 'Berlin');

      expect(jobs, hasLength(1));
    });
    test('parses a job from the Careerjet response', () async {
      service = build(MockClient((request) async =>
          http.Response(jsonEncode(_sampleResponse()), 200)));

      final jobs = await service.search(query: 'Flutter');
      expect(jobs, hasLength(1));

      final job = jobs.first;
      expect(job.title, 'Flutter Entwickler (m/w/d)');
      expect(job.company, 'Beispiel GmbH');
      expect(job.location, 'Berlin, Deutschland');
      expect(job.url, 'https://jobviewtrack.com/cj-test-1');
      expect(job.source, 'careerjet');
      expect(job.id,
          fnv1a32('https://jobviewtrack.com/cj-test-1').toString());
      expect(job.salaryRange, '60.000 - 80.000 EUR');
      // Beschreibung enthält „Remote“ → Arbeitsmodell ableitbar.
      expect(job.workModel, WorkModel.remote);
      expect(job.employmentType, isNull);
    });



    test('tolerates string company and string locations', () async {
      final data = _sampleResponse();
      final jobMap = (data['jobs'] as List).first as Map<String, dynamic>;
      jobMap['company'] = 'Beispiel GmbH';
      jobMap['locations'] = 'Berlin';
      jobMap.remove('salary_min');
      jobMap.remove('salary_max');
      jobMap['salary'] = '60k - 80k';
      service = build(MockClient((request) async =>
          http.Response(jsonEncode(data), 200)));

      final jobs = await service.search(query: 'Flutter');
      expect(jobs, hasLength(1));
      expect(jobs.first.company, 'Beispiel GmbH');
      expect(jobs.first.location, 'Berlin');
      expect(jobs.first.salaryRange, '60k - 80k');
    });

    test('returns empty list when the response has no jobs', () async {
      service = build(MockClient((request) async => http.Response(
          jsonEncode({'type': 'JOBS', 'hits': 0}), 200)));

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

    test('throws JobApiException with hint on 401/403 (auth)', () async {
      service =
          build(MockClient((request) async => http.Response('forbidden', 403)));

      expect(
        () => service.search(query: 'Flutter'),
        throwsA(isA<JobApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('uses the fallback IP when the echo service fails', () async {
      service = build(
        MockClient((request) async {
          expect(request.url.queryParameters['user_ip'], '0.0.0.0');
          return http.Response(jsonEncode(_sampleResponse()), 200);
        }),
        // IP-Echo antwortet nicht mit 2xx → Fallback greift.
        ipClient: MockClient((request) async => http.Response('error', 500)),
      );

      final jobs = await service.search(query: 'Flutter');
      expect(jobs, hasLength(1));
    });
  });
}

/// Beispiel-Response der Careerjet-API (Suchstruktur).
Map<String, dynamic> _sampleResponse() {
  return {
    'type': 'JOBS',
    'hits': 1,
    'pages': 1,
    'jobs': [
      {
        'title': 'Flutter Entwickler (m/w/d)',
        'company': {'display_name': 'Beispiel GmbH'},
        'locations': ['Berlin', 'Deutschland'],
        'url': 'https://jobviewtrack.com/cj-test-1',
        'date': 'Wed, 15 Nov 2025 19:13:43 GMT',
        'description': 'Entwicklung von Flutter-Apps. Remote möglich.',
        'salary_min': 60000,
        'salary_max': 80000,
        'salary_currency_code': 'EUR',
        'salary_type': 'Y',
      }
    ],
  };
}
