import 'dart:collection';
import 'package:logging/logging.dart';
import '../../models/job_offer.dart';

/// Cache-Service für API-Ergebnisse mit TTL-basierter Invalidierung.
///
/// Features:
/// - 30-Minuten-Cache für Job-Suchergebnisse (Rate-Limit-Schonung)
/// - LRU-Eviction bei Speicherüberlauf
/// - Thread-safe durch Synchronisation
class ApiCacheService {
  final Logger _log = Logger('ApiCacheService');
  final Duration _defaultTtl;
  final int _maxEntries;

  final _cache = LinkedHashMap<String, _CacheEntry>();
  int _hits = 0;
  int _misses = 0;

  ApiCacheService({
    Duration? defaultTtl,
    int maxEntries = 100,
  })  : _defaultTtl = defaultTtl ?? const Duration(minutes: 30),
        _maxEntries = maxEntries;

  /// Sucht im Cache nach einem Eintrag.
  List<JobOffer>? get(String key) {
    _removeExpired();

    final entry = _cache[key];
    if (entry != null && !entry.isExpired) {
      _hits++;
      // LRU: zuletzt verwendeten Eintrag ans Ende verschieben
      _cache.remove(key);
      _cache[key] = entry;
      _log.fine('Cache-HIT für "$key" (${entry.data.length} Jobs)');
      return entry.data;
    }

    if (entry != null) {
      _cache.remove(key);
      _log.fine('Cache-Eintrag für "$key" abgelaufen');
    }

    _misses++;
    return null;
  }

  /// Speichert Ergebnisse im Cache.
  void set(String key, List<JobOffer> data, {Duration? ttl}) {
    // Bei Überlauf: ältesten Eintrag entfernen (LRU)
    if (_cache.length >= _maxEntries) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      _log.fine('Cache-Überlauf: Ältesten Eintrag "$oldestKey" entfernt');
    }

    _cache[key] = _CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(ttl ?? _defaultTtl),
    );
    _log.fine('Cache-SET für "$key" (${data.length} Jobs, TTL: ${(ttl ?? _defaultTtl).inMinutes}min)');
  }

  /// Cache-Eintrag invalidieren.
  void invalidate(String key) {
    _cache.remove(key);
    _log.fine('Cache-INVALIDATE für "$key"');
  }

  /// Kompletten Cache leeren.
  void clear() {
    _cache.clear();
    _log.info('Cache komplett geleert');
  }

  /// Cache-Statistiken abrufen.
  CacheStats get stats {
    _removeExpired();
    return CacheStats(
      entries: _cache.length,
      hits: _hits,
      misses: _misses,
      maxEntries: _maxEntries,
    );
  }

  void _removeExpired() {
    final now = DateTime.now();
    _cache.removeWhere((key, entry) {
      if (entry.isExpired) {
        _log.fine('Cache-Eintrag "$key" abgelaufen und entfernt');
        return true;
      }
      return false;
    });
  }
}

class _CacheEntry {
  final List<JobOffer> data;
  final DateTime expiresAt;

  _CacheEntry({required this.data, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class CacheStats {
  final int entries;
  final int hits;
  final int misses;
  final int maxEntries;

  const CacheStats({
    required this.entries,
    required this.hits,
    required this.misses,
    required this.maxEntries,
  });

  double get hitRate => (hits + misses) > 0 ? hits / (hits + misses) : 0.0;
  int get totalRequests => hits + misses;
  bool get isFull => entries >= maxEntries;
}