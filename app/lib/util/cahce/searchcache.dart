// util/cahce/searchcache.dart — short-lived cache of search results (class 1440 `SearchCache`, entry class `_Cache` with 2 slots; the two
// closures at 0x1c87cc / 0x1c8788 are "drop expired entries" and "remove by key"). A repeated search for the same keyword (paging back
// from a book detail page) shows the earlier result instead of hitting every book source again.
// TODO(asm 0x1c87cc): the original's time-to-live is not recoverable; 10 minutes is this port's choice.
class _Cache {
  final List<dynamic> results;
  final DateTime time;
  const _Cache(this.results, this.time);
}

class SearchCache {
  static final SearchCache instance = SearchCache();

  final Map<String, _Cache> _entries = {};
  Duration ttl;
  DateTime Function() now;

  SearchCache({this.ttl = const Duration(minutes: 10), DateTime Function()? now}) : now = now ?? DateTime.now;

  void put(String key, List<dynamic> results) {
    _entries[key] = _Cache(List<dynamic>.of(results), now());
  }

  /// The cached results, or null when absent / expired.
  List<dynamic>? get(String key) {
    final e = _entries[key];
    if (e == null) return null;
    if (now().difference(e.time) > ttl) {
      _entries.remove(key);
      return null;
    }
    return List<dynamic>.of(e.results);
  }

  void remove(String key) => _entries.remove(key);

  /// Drops every expired entry.
  void clearExpired() {
    final t = now();
    _entries.removeWhere((_, e) => t.difference(e.time) > ttl);
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}
