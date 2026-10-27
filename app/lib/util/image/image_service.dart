// util/image/image_service.dart — class 1328 `ImageService`: image work off the UI isolate (original: a long-lived isolate with a
// `ReceivePort` (static 0x4d40), entry `_isolateEntry` 0x236484, tasks wrapped in `_ComputeTask` 0x18 with a reply port).
// This port runs each task in a short-lived isolate through [ReadIsolate] (same effect, no port bookkeeping), which is also what
// keeps it testable. Tasks: read intrinsic sizes of a batch of images, warm the size cache.
import 'dart:io';
import 'dart:ui' show Size;

import '../../read/api/read_file_store.dart';
import 'cache.dart';
import 'image_size.dart';

abstract class ImageService {
  /// Sizes of many local images in one background task; unreadable files are missing from the result.
  static Future<Map<String, Size>> readSizes(Iterable<String> paths) async {
    final list = paths.toList();
    final out = <String, Size>{};
    final todo = <String>[];
    for (final p in list) {
      final c = ImageCache.sizes[p];
      if (c != null) {
        out[p] = c;
      } else {
        todo.add(p);
      }
    }
    if (todo.isEmpty) return out;
    final res = await ReadIsolate.run(() => _readSizesSync(todo));
    res.forEach((path, wh) {
      final s = Size(wh.$1, wh.$2);
      ImageCache.sizes[path] = s;
      out[path] = s;
    });
    return out;
  }

  static Map<String, (double, double)> _readSizesSync(List<String> paths) {
    final m = <String, (double, double)>{};
    for (final p in paths) {
      final s = p.startsWith('data:') ? ImageSizeReader.fromDataUri(p) : ImageSizeReader.fromFile(File(p));
      if (s != null) m[p] = (s.width, s.height);
    }
    return m;
  }
}
