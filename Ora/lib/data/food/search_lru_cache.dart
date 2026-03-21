import 'dart:collection';

class SearchLruCache<K, V> {
  SearchLruCache({
    required this.maxEntries,
    required this.ttl,
  }) : assert(maxEntries > 0);

  final int maxEntries;
  final Duration ttl;
  final LinkedHashMap<K, _CacheEntry<V>> _entries =
      LinkedHashMap<K, _CacheEntry<V>>();

  V? get(K key) {
    final now = DateTime.now();
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (now.isAfter(entry.expiresAt)) {
      return null;
    }
    _entries[key] = entry;
    return entry.value;
  }

  void set(K key, V value) {
    _entries.remove(key);
    _entries[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
    _evict();
  }

  void remove(K key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }

  void pruneExpired() {
    final now = DateTime.now();
    final expired = _entries.entries
        .where((item) => now.isAfter(item.value.expiresAt))
        .map((item) => item.key)
        .toList(growable: false);
    for (final key in expired) {
      _entries.remove(key);
    }
  }

  void _evict() {
    pruneExpired();
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

class _CacheEntry<V> {
  const _CacheEntry({
    required this.value,
    required this.expiresAt,
  });

  final V value;
  final DateTime expiresAt;
}
