// util/cahce/searchcache.dart — short-lived cache of source results (class 1440 `SearchCache`, entry class `_Cache` = value + expiry in
// epoch milliseconds; put 0x1c2258 stores `now + ttl`, the closure 0x1c87cc collects the keys whose expiry has passed, 0x1c8788
// removes them). The callers pass the time-to-live: 300000 ms for search results (0xfda6d8) and book info (0xe687b4), 120000 ms for
// the third user (0xed9e18). A repeated search for the same keyword shows the earlier result instead of hitting every source again.
class _Cache {
  final List<dynamic> results;
  final DateTime expires;
  const _Cache(this.results, this.expires);
}

class SearchCache {
  static final SearchCache instance = SearchCache();

  /// The original callers' lifetimes.
  static const Duration searchTtl = Duration(milliseconds: 300000);
  static const Duration shortTtl = Duration(milliseconds: 120000);

  final Map<String, _Cache> _entries = {};

  /// Lifetime used when [put] is not given one.
  Duration ttl;
  DateTime Function() now;

  SearchCache({this.ttl = searchTtl, DateTime Function()? now}) : now = now ?? DateTime.now;

  void put(String key, List<dynamic> results, {Duration? ttl}) {
    _entries[key] = _Cache(List<dynamic>.of(results), now().add(ttl ?? this.ttl));
  }

  /// The cached results, or null when absent / expired.
  List<dynamic>? get(String key) {
    final e = _entries[key];
    if (e == null) return null;
    if (e.expires.isBefore(now())) {
      _entries.remove(key);
      return null;
    }
    return List<dynamic>.of(e.results);
  }

  void remove(String key) => _entries.remove(key);

  /// Drops every expired entry (0x1c87cc + 0x1c8788).
  void clearExpired() {
    final t = now();
    final dead = [for (final e in _entries.entries) if (e.value.expires.isBefore(t)) e.key];
    dead.forEach(_entries.remove);
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}
