// util/cahce/imagecache.dart — the three in-memory image caches of the original (directory name `cahce` is the original's spelling):
//   Imagecache  (class 1443, `LinkedHashMap<String, Uint8List> _cache` 0x4df0)   encoded image bytes by url, at most 50 entries
//   Imagecache2 (class 1442, `LinkedHashMap<String, Uint8List> _cache` 0x4de0)   second bytes cache, at most 10 entries
//   Imagecache3 (class 1441, `LinkedHashMap<String, String> _cache` 0x4e00)      url -> local file path, at most 10 entries
// put (0x22bcdc / 0x22be28 / 0x22bf74): an existing key is removed first, the value is added at the end, then the oldest keys are
// dropped while the map is longer than the cap; get only reads.
import 'dart:collection';
import 'dart:typed_data';

class _Fifo<V> {
  final LinkedHashMap<String, V> _m = LinkedHashMap();
  final int max;
  _Fifo(this.max);

  V? get(String key) => _m[key];

  void put(String key, V value) {
    _m.remove(key);
    _m[key] = value;
    while (_m.length > max) {
      _m.remove(_m.keys.first);
    }
  }

  void remove(String key) => _m.remove(key);
  void clear() => _m.clear();
  int get length => _m.length;
}

abstract class Imagecache {
  static const int maxEntries = 50;
  static final _Fifo<Uint8List> _cache = _Fifo(maxEntries);
  static Uint8List? get(String url) => _cache.get(url);
  static void put(String url, Uint8List bytes) => _cache.put(url, bytes);
  static void remove(String url) => _cache.remove(url);
  static void clear() => _cache.clear();
  static int get length => _cache.length;
}

abstract class Imagecache2 {
  static const int maxEntries = 10;
  static final _Fifo<Uint8List> _cache = _Fifo(maxEntries);
  static Uint8List? get(String key) => _cache.get(key);
  static void put(String key, Uint8List bytes) => _cache.put(key, bytes);
  static void remove(String key) => _cache.remove(key);
  static void clear() => _cache.clear();
  static int get length => _cache.length;
}

abstract class Imagecache3 {
  static const int maxEntries = 10;
  static final _Fifo<String> _cache = _Fifo(maxEntries);
  static String? get(String url) => _cache.get(url);
  static void put(String url, String path) => _cache.put(url, path);
  static void remove(String url) => _cache.remove(url);
  static void clear() => _cache.clear();
  static int get length => _cache.length;
}
