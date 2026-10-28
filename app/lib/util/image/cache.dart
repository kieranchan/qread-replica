// util/image/cache.dart — class 1337 `ImageCache` of the original (size 0x18: two fields, the image and its `MySize`, built by
// 0xeb348c / 0xeb35b0 and kept in a static `Map<String, ImageCache>`): the reader's lookup for image sizes keyed by source. Here a
// bounded map of intrinsic sizes, shared by the layout engine and the UI (the pictures themselves are Flutter's image cache).
import 'dart:collection';
import 'dart:ui' show Size;

class ImageCache {
  static const int maxEntries = 512;

  /// Intrinsic sizes by source (file path or `data:` URI), least recently inserted dropped first.
  static final ImageSizeCache sizes = ImageSizeCache();

  static void clear() => sizes.clear();
}

class ImageSizeCache {
  final LinkedHashMap<String, Size> _m = LinkedHashMap();

  Size? operator [](String key) {
    final v = _m.remove(key);
    if (v != null) _m[key] = v; // refresh
    return v;
  }

  void operator []=(String key, Size value) {
    _m.remove(key);
    _m[key] = value;
    while (_m.length > ImageCache.maxEntries) {
      _m.remove(_m.keys.first);
    }
  }

  int get length => _m.length;

  void clear() => _m.clear();
}
