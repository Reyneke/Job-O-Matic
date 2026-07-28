import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/api/api_cache_service.dart';
import 'package:job_o_matic/data/models/job_offer.dart';

void main() {
  group('ApiCacheService', () {
    late ApiCacheService cacheService;

    setUp(() {
      cacheService = ApiCacheService(
        defaultTtl: const Duration(minutes: 30),
        maxEntries: 10,
      );
    });

    test('get returns null for missing key', () {
      expect(cacheService.get('nonexistent'), isNull);
    });

    test('set and get stores and retrieves data', () {
      final jobs = [
        JobOffer(
          id: '1',
          title: 'Test',
          company: 'Test Corp',
          url: 'https://example.com/job/1',
          source: 'test',
        ),
      ];

      cacheService.set('test-key', jobs);
      final retrieved = cacheService.get('test-key');

      expect(retrieved, isNotNull);
      expect(retrieved!.length, 1);
      expect(retrieved.first.id, '1');
    });

    test('get returns null after TTL expiry', () async {
      cacheService = ApiCacheService(
        defaultTtl: const Duration(milliseconds: 50),
        maxEntries: 10,
      );

      final jobs = [
        JobOffer(
          id: '1',
          title: 'Test',
          company: 'Test Corp',
          url: 'https://example.com/job/1',
          source: 'test',
        ),
      ];

      cacheService.set('expire-key', jobs);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(cacheService.get('expire-key'), isNull);
    });

    test('invalidate removes entry', () {
      final jobs = [
        JobOffer(
          id: '1',
          title: 'Test',
          company: 'Test Corp',
          url: 'https://example.com/job/1',
          source: 'test',
        ),
      ];

      cacheService.set('key', jobs);
      cacheService.invalidate('key');
      expect(cacheService.get('key'), isNull);
    });

    test('clear removes all entries', () {
      cacheService.set('a', [
        JobOffer(id: '1', title: 'A', company: 'C', url: 'url', source: 's')
      ]);
      cacheService.set('b', [
        JobOffer(id: '2', title: 'B', company: 'C', url: 'url2', source: 's')
      ]);

      cacheService.clear();

      expect(cacheService.get('a'), isNull);
      expect(cacheService.get('b'), isNull);
    });

    test('evicts oldest entries when maxEntries reached', () {
      for (int i = 0; i < 12; i++) {
        cacheService.set(
          'key-$i',
          [
            JobOffer(
              id: '$i',
              title: 'Job $i',
              company: 'Co',
              url: 'https://example.com/job/$i',
              source: 'test',
            ),
          ],
        );
      }

      // First entries should be evicted
      expect(cacheService.get('key-0'), isNull);
      expect(cacheService.get('key-1'), isNull);

      // Recent entries should still exist
      expect(cacheService.get('key-10'), isNotNull);
      expect(cacheService.get('key-11'), isNotNull);
    });

    test('stats provide accurate metrics', () {
      cacheService.get('miss');
      cacheService.get('miss2');

      final jobs = [
        JobOffer(
          id: '1',
          title: 'Test',
          company: 'Co',
          url: 'url',
          source: 's',
        ),
      ];
      cacheService.set('hit-key', jobs);
      cacheService.get('hit-key');

      final stats = cacheService.stats;
      expect(stats.hits, 1);
      expect(stats.misses, 2);
      expect(stats.hitRate, closeTo(0.333, 0.01));
    });
  });
}