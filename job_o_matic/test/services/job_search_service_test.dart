import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/models/job_offer.dart';
import 'package:job_o_matic/data/services/api/api_cache_service.dart';
import 'package:job_o_matic/data/services/api/api_client.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/api/ba_api_service.dart';
import 'package:job_o_matic/data/services/api/serp_api_service.dart';
import 'package:job_o_matic/data/services/api/careerjet_api_service.dart';
import 'package:job_o_matic/data/services/api/job_search_service.dart';
import 'package:logging/logging.dart';

void main() {
  group('JobSearchService', () {
    late JobSearchService service;
    late MockClient mockClient;
    int baRequests = 0;

    JobSearchService build({
      List<Map<String, dynamic>> Function(int page)? baResponse,
      ApiCacheService? cache,
      WorkModel? workModelFromBa,
    }) {
      baRequests = 0;
      mockClient = MockClient((request) async {
        baRequests++;
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        final list = baResponse!(page);
        return http.Response(
          jsonEncode({
            'ergebnisliste': list,
            'maxErgebnisse': list.length,
            'page': page,
            'size': 20,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      return JobSearchService(
        baService: BaApiService(client: apiClient),
        cacheService: cache,
      );
    }

    Map<String, dynamic> sampleJob() => {
          'referenznummer': '12345',
          'stellenangebotsTitel': 'Flutter Developer',
          'firma': 'Bewerbungsfirma',
          'stellenlokationen': [
            {'adresse': {'ort': 'Berlin'}},
          ],
          'datumErsteVeroeffentlichung': '2026-07-01',
        };

    test('forwards page and size to BA', () async {
      service = build(baResponse: (page) => [sampleJob()]);
      await service.searchJobs(query: 'Flutter', page: 2, size: 20);
      expect(baRequests, 1);
    });

    test('caches empty results and reuses them (short TTL)', () async {
      service = build(
        baResponse: (page) => <Map<String, dynamic>>[],
        cache: ApiCacheService(
          defaultTtl: const Duration(minutes: 30),
          maxEntries: 10,
        ),
      );

      final first = await service.searchJobs(query: 'Nichts');
      expect(first.jobs, isEmpty);
      final second = await service.searchJobs(query: 'Nichts');
      expect(second.jobs, isEmpty);
      // Zweite Anfrage darf nicht das Netz treffen (gecacht).
      expect(baRequests, 1);
    });

    test('adds page to the cache key', () async {
      service = build(
        baResponse: (page) => [sampleJob()],
        cache: ApiCacheService(
          defaultTtl: const Duration(minutes: 30),
          maxEntries: 10,
        ),
      );

      await service.searchJobs(query: 'Flutter', page: 1);
      await service.searchJobs(query: 'Flutter', page: 2);
      // Verschiedene Seiten = verschiedene Cache-Keys → beide treffen das Netz.
      expect(baRequests, 2);
    });

    test('workModel filter passes through jobs without an indication', () async {
      service = build(
        baResponse: (page) => [sampleJob()],
        workModelFromBa: WorkModel.remote,
      );

      final result =
          await service.searchJobs(query: 'Flutter', workModel: WorkModel.remote);
      // BA-Jobs haben keine Beschreibung/WorkModel → unbewertbar → durchlassen.
      expect(result.jobs, hasLength(1));
    });

    test('falls back to SerpAPI when BA returns no results', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'serpapi.com') {
          return http.Response(
            jsonEncode({
              'jobs_results': [
                {
                  'job_id': 'serp-1',
                  'title': 'Flutter Developer (SerpAPI)',
                  'company_name': 'SerpFirma',
                  'location': 'Hamburg, Deutschland',
                  'description': 'Flutter-Entwicklung',
                  'share_link': 'https://serp.example/job/serp-1',
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // BA liefert keine Ergebnisse → SerpAPI-Fallback muss greifen.
        return http.Response(
          jsonEncode({
            'ergebnisliste': <Object>[],
            'maxErgebnisse': 0,
            'page': 1,
            'size': 20,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mockClient,
      );
      final serpService = SerpApiService(
        client: apiClient,
        keyService: ApiKeyService(),
        keyLoader: () async => 'test-key',
      );
      service = JobSearchService(
        baService: BaApiService(client: apiClient),
        serpService: serpService,
      );

      final result = await service.searchJobs(query: 'Flutter');

      expect(result.jobs, hasLength(1));
      expect(result.jobs.first.source, 'serpapi');
      expect(result.jobs.first.title, 'Flutter Developer (SerpAPI)');
    });

    test('fills the threshold with Careerjet first (SerpAPI not called)',
        () async {
      int serpCalls = 0;
      final mock = MockClient((request) async {
        if (request.url.host == 'search.api.careerjet.net') {
          // Careerjet liefert 10 Jobs → Schwelle erreicht, SerpAPI darf nicht
          // mehr angefragt werden (Careerjet steht VOR SerpAPI in der Kaskade).
          final jobs = List.generate(10, (i) => {
                'title': 'CJ Job $i',
                'company': 'CJFirma',
                'url': 'https://jobviewtrack.com/cj-$i',
              });
          return http.Response(
            jsonEncode({'type': 'JOBS', 'hits': 10, 'jobs': jobs}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.host == 'serpapi.com') {
          serpCalls++;
          return http.Response(
            jsonEncode({
              'jobs_results': [
                {
                  'job_id': 's-1',
                  'title': 'Serp Job',
                  'company_name': 'SerpFirma',
                  'share_link': 'https://serp.example/job/s-1',
                }
              ],
            }),
            200,
          );
        }
        // BA liefert keine Ergebnisse.
        return http.Response(
          jsonEncode({
            'ergebnisliste': <Object>[],
            'maxErgebnisse': 0,
            'page': 1,
            'size': 20,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mock,
      );
      final careerjet = CareerjetApiService(
        client: apiClient,
        keyService: ApiKeyService(),
        ipClient: MockClient(
            (request) async => http.Response(jsonEncode({'ip': '9.9.9.9'}), 200)),
        keyLoader: () async => 'careerjet-key',
      );
      final serp = SerpApiService(
        client: apiClient,
        keyService: ApiKeyService(),
        keyLoader: () async => 'serp-key',
      );
      service = JobSearchService(
        baService: BaApiService(client: apiClient),
        careerjetService: careerjet,
        serpService: serp,
      );

      final result = await service.searchJobs(query: 'Flutter');

      expect(result.jobs, hasLength(10));
      expect(result.jobs.every((j) => j.source == 'careerjet'), isTrue);
      expect(serpCalls, 0);
    });

    test('keeps SerpAPI as last fallback when Careerjet is empty', () async {
      final mock = MockClient((request) async {
        if (request.url.host == 'search.api.careerjet.net') {
          return http.Response(
            jsonEncode({'type': 'JOBS', 'hits': 0, 'jobs': <Object>[]}),
            200,
          );
        }
        if (request.url.host == 'serpapi.com') {
          return http.Response(
            jsonEncode({
              'jobs_results': [
                {
                  'job_id': 's-1',
                  'title': 'Serp Job (Fallback)',
                  'company_name': 'SerpFirma',
                  'share_link': 'https://serp.example/job/s-1',
                }
              ],
            }),
            200,
          );
        }
        // BA liefert keine Ergebnisse.
        return http.Response(
          jsonEncode({
            'ergebnisliste': <Object>[],
            'maxErgebnisse': 0,
            'page': 1,
            'size': 20,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: mock,
      );
      final careerjet = CareerjetApiService(
        client: apiClient,
        keyService: ApiKeyService(),
        ipClient: MockClient(
            (request) async => http.Response(jsonEncode({'ip': '9.9.9.9'}), 200)),
        keyLoader: () async => 'careerjet-key',
      );
      final serp = SerpApiService(
        client: apiClient,
        keyService: ApiKeyService(),
        keyLoader: () async => 'serp-key',
      );
      service = JobSearchService(
        baService: BaApiService(client: apiClient),
        careerjetService: careerjet,
        serpService: serp,
      );

      final result = await service.searchJobs(query: 'Flutter');

      expect(result.jobs, hasLength(1));
      expect(result.jobs.first.source, 'serpapi');
    });

  });
}