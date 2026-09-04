import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:job_o_matic/data/models/job_offer.dart';
import 'package:job_o_matic/data/services/api/adzuna_api_service.dart';
import 'package:job_o_matic/data/services/api/api_client.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';

/// ApiKeyService-Fake: liefert Werte aus einer Map statt echter
/// flutter_secure_storage-Ablage (im Unit-Test kein Plattform-Channel).
class _FakeKeyService extends ApiKeyService {
  final Map<String, String> values;

  _FakeKeyService(this.values);

  @override
  Future<String?> loadKey(String name) async => values[name];

  @override
  Future<String> loadAdzunaCountry() async {
    final country =
        (values[ApiKeyService.adzunaCountry]?.trim().toLowerCase() ?? 'de');
    return country.isEmpty ? 'de' : country;
  }
}

void main() {
  group('AdzunaApiService', () {
    late Map<String, String> keys;

    AdzunaApiService build(http.Client client) {
      final apiClient = ApiClient(
        logger: Logger('AdzunaApiServiceTest'),
        client: client,
        keyService: _FakeKeyService(keys),
      );
      return AdzunaApiService(
        client: apiClient,
        keyService: _FakeKeyService(keys),
      );
    }

    setUp(() {
      keys = {
        'adzuna_app_id': 'my_app_id',
        'adzuna_api_key': 'my_api_key',
      };
    });

    test('search builds URL with configured country and credentials',
        () async {
      keys['adzuna_country'] = 'gb';
      late Uri captured;
      final service = build(MockClient((request) async {
        captured = request.url;
        return http.Response(jsonEncode({'results': <Object>[]}), 200);
      }));

      final jobs = await service.search(query: 'Flutter', page: 1, size: 10);

      expect(captured.host, 'api.adzuna.com');
      expect(captured.path, '/v1/api/jobs/gb/search/1');
      expect(captured.queryParameters['app_id'], 'my_app_id');
      expect(captured.queryParameters['app_key'], 'my_api_key');
      expect(captured.queryParameters['what'], 'Flutter');
      expect(captured.queryParameters['results_per_page'], '10');
      expect(jobs, isEmpty);
    });

    test('search defaults to market "de" when no country is stored',
        () async {
      late Uri captured;
      final service = build(MockClient((request) async {
        captured = request.url;
        return http.Response(jsonEncode({'results': <Object>[]}), 200);
      }));

      await service.search(query: 'Flutter');

      expect(captured.path, '/v1/api/jobs/de/search/1');
    });

    test('HTTP 401 throws AUTH_FAIL JobApiException incl. market hint',
        () async {
      keys['adzuna_country'] = 'de';
      final service = build(MockClient((request) async {
        return http.Response(
          jsonEncode({'exception': 'AUTH_FAIL'}),
          401,
        );
      }));

      await expectLater(
        service.search(query: 'Flutter'),
        throwsA(isA<JobApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('AUTH_FAIL'))
            .having((e) => e.message, 'message', contains('de'))),
      );
    });

    test('throws when App-ID/API-Key are missing', () async {
      keys = {};
      final service = build(
          MockClient((request) async => http.Response('{}', 200)));

      await expectLater(
        service.search(query: 'Flutter'),
        throwsA(isA<JobApiException>().having(
            (e) => e.message,
            'message',
            contains('nicht konfiguriert'))),
      );
    });
  });
}
