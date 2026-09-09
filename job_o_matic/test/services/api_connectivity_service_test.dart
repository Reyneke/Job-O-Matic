import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/services/api/api_connectivity_service.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';

void main() {
  group('ApiConnectivityService', () {
    late Map<String, String> storedKeys;

    ApiConnectivityService build(http.Client client) {
      return ApiConnectivityService(
        keyService: ApiKeyService(),
        keyLoader: (name) async => storedKeys[name],
        client: client,
        timeout: const Duration(seconds: 2),
      );
    }

    setUp(() {
      storedKeys = {};
    });

    test('BA check reports ok on HTTP 200', () async {
      final service = build(MockClient((request) async {
        expect(request.url.host, 'rest.arbeitsagentur.de');
        return http.Response('{}', 200);
      }));

      final results = await service.checkAll();
      final ba = results.firstWhere((r) => r.serviceLabel == 'BA JOBBÖRSE');
      expect(ba.status, ApiConnectivityStatus.ok);
    });

    test('BA check uses public default key + User-Agent, ignores stored key',
        () async {
      // Ein gespeicherter (falscher) BA-Key darf den funktionierenden
      // öffentlichen Standard NICHT überschreiben (fix: HTTP-403-Bug).
      storedKeys = {ApiKeyService.baApiKey: 'veralteter-oder-falscher-key'};

      final service = build(MockClient((request) async {
        expect(request.url.host, 'rest.arbeitsagentur.de');
        final lowerHeaders =
            request.headers.map((k, v) => MapEntry(k.toLowerCase(), v));
        expect(lowerHeaders['x-api-key'], 'jobboerse-jobsuche');
        expect(lowerHeaders['user-agent'], 'Job-O-Matic/1.0');
        return http.Response('{}', 200);
      }));

      final results = await service.checkAll();
      final ba = results.firstWhere((r) => r.serviceLabel == 'BA JOBBÖRSE');
      expect(ba.status, ApiConnectivityStatus.ok);
    });

    test('Adzuna is notConfigured without keys', () async {
      final service = build(
          MockClient((request) async => http.Response('', 500)));

      final results = await service.checkAll();
      final adzuna = results.firstWhere((r) => r.serviceLabel == 'Adzuna');
      expect(adzuna.status, ApiConnectivityStatus.notConfigured);
    });

    test('Adzuna reports ok when keys are configured', () async {
      storedKeys = {'adzuna_app_id': 'app', 'adzuna_api_key': 'key'};
      final service = build(MockClient((request) async {
        expect(request.url.host, 'api.adzuna.com');
        return http.Response('{}', 200);
      }));

      final results = await service.checkAll();
      final adzuna = results.firstWhere((r) => r.serviceLabel == 'Adzuna');
      expect(adzuna.status, ApiConnectivityStatus.ok);
    });

    test('Adzuna check defaults to market "de" when no country is stored',
        () async {
      storedKeys = {'adzuna_app_id': 'app', 'adzuna_api_key': 'key'};
      final service = build(MockClient((request) async {
        expect(request.url.host, 'api.adzuna.com');
        expect(request.url.path, '/v1/api/jobs/de/search/1');
        return http.Response('{}', 200);
      }));

      final results = await service.checkAll();
      final adzuna = results.firstWhere((r) => r.serviceLabel == 'Adzuna');
      expect(adzuna.status, ApiConnectivityStatus.ok);
    });

    test('Adzuna check uses the configured market (e.g. gb)', () async {
      storedKeys = {
        'adzuna_app_id': 'app',
        'adzuna_api_key': 'key',
        'adzuna_country': 'gb',
      };
      final service = build(MockClient((request) async {
        expect(request.url.host, 'api.adzuna.com');
        expect(request.url.path, '/v1/api/jobs/gb/search/1');
        return http.Response('{}', 200);
      }));

      final results = await service.checkAll();
      final adzuna = results.firstWhere((r) => r.serviceLabel == 'Adzuna');
      expect(adzuna.status, ApiConnectivityStatus.ok);
    });

    test('Careerjet is notConfigured without key', () async {
      final service = build(
          MockClient((request) async => http.Response('', 500)));

      final results = await service.checkAll();
      final careerjet =
          results.firstWhere((r) => r.serviceLabel == 'Careerjet');
      expect(careerjet.status, ApiConnectivityStatus.notConfigured);
    });

    test('Careerjet reports ok + sends basic auth when key is configured',
        () async {
      storedKeys = {ApiKeyService.careerjetApiKey: 'k'};
      final expectedAuth =
          'Basic ${base64Encode(utf8.encode('k:'))}';
      final service = build(MockClient((request) async {
        expect(request.url.host, 'search.api.careerjet.net');
        expect(request.url.queryParameters['locale_code'], 'de_DE');
        expect(request.url.queryParameters['user_ip'], '127.0.0.1');
        expect(request.headers['Authorization'], expectedAuth);
        return http.Response('{}', 200);
      }));

      final results = await service.checkAll();
      final careerjet =
          results.firstWhere((r) => r.serviceLabel == 'Careerjet');
      expect(careerjet.status, ApiConnectivityStatus.ok);
    });

    test('reports failed on non-2xx status', () async {
      final service = build(
          MockClient((request) async => http.Response('nope', 401)));

      final results = await service.checkAll();
      final ba = results.firstWhere((r) => r.serviceLabel == 'BA JOBBÖRSE');
      expect(ba.status, ApiConnectivityStatus.failed);
    });

    test('reports failed on network error', () async {
      final service = build(
          MockClient((request) async => throw Exception('boom')));

      final results = await service.checkAll();
      final ba = results.firstWhere((r) => r.serviceLabel == 'BA JOBBÖRSE');
      expect(ba.status, ApiConnectivityStatus.failed);
    });
  });
}