// util/cahce/imagecache.dart — the three in-memory image caches of the original (directory name `cahce` is the original's spelling):
//   Imagecache  (class 1443, `LinkedHashMap<String, Uint8List> _cache` 0x4df0)   encoded image bytes by url
//   Imagecache2 (class 1442, `LinkedHashMap<String, Uint8List> _cache` 0x4de0)   second bytes cache (decoded / re-encoded variants)
//   Imagecache3 (class 1441, `LinkedHashMap<String, String> _cache` 0x4e00)      url -> local file path
// The bounds are not recoverable (TODO(asm 0x4df0)); the byte caches are limited by total size, the path cache by entry count.
import 'dart:collection';
import 'dart:typed_data';

class _ByteLru {
  final LinkedHashMap<String, Uint8List> _m = LinkedHashMap();
  int _bytes = 0;
  final int maxBytes;
  _ByteLru(this.maxBytes);

  Uint8List? get(String key) {
    final v = _m.remove(key);
    if (v != null) _m[key] = v;
    return v;
  }

  void put(String key, Uint8List value) {
    final old = _m.remove(key);
    if (old != null) _bytes -= old.length;
    if (value.length > maxBytes) return;
    _m[key] = value;
    _bytes += value.length;
    while (_bytes > maxBytes && _m.isNotEmpty) {
      final k = _m.keys.first;
      _bytes -= _m.remove(k)!.length;
    }
  }

  void remove(String key) {
    final old = _m.remove(key);
    if (old != null) _bytes -= old.length;
  }

  void clear() {
    _m.clear();
    _bytes = 0;
  }

  int get length => _m.length;
  int get totalBytes => _bytes;
}

abstract class Imagecache {
  static final _ByteLru _cache = _ByteLru(64 * 1024 * 1024);
  static Uint8List? get(String url) => _cache.get(url);
  static void put(String url, Uint8List bytes) => _cache.put(url, bytes);
  static void remove(String url) => _cache.remove(url);
  static void clear() => _cache.clear();
  static int get length => _cache.length;
  static int get totalBytes => _cache.totalBytes;
}

abstract class Imagecache2 {
  static final _ByteLru _cache = _ByteLru(32 * 1024 * 1024);
  static Uint8List? get(String key) => _cache.get(key);
  static void put(String key, Uint8List bytes) => _cache.put(key, bytes);
  static void remove(String key) => _cache.remove(key);
  static void clear() => _cache.clear();
  static int get length => _cache.length;
}

abstract class Imagecache3 {
  static const int maxEntries = 2000;
  static final LinkedHashMap<String, String> _cache = LinkedHashMap();

  static String? get(String url) {
    final v = _cache.remove(url);
    if (v != null) _cache[url] = v;
    return v;
  }

  static void put(String url, String path) {
    _cache.remove(url);
    _cache[url] = path;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static void remove(String url) => _cache.remove(url);
  static void clear() => _cache.clear();
  static int get length => _cache.length;
}
