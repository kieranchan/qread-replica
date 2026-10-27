// util/image/image_size.dart — intrinsic image size from the file header (PNG, JPEG, GIF, WebP, BMP, SVG width/height), without
// decoding. The layout engine needs the size of every image of a chapter before anything is drawn; the original looks sizes up
// in an image cache (`_imagescahce`, 0x23be88) filled by `ImageService`; this reads them from the first bytes instead.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'cache.dart';

abstract class ImageSizeReader {
  /// Size of the encoded image in [b], or null when the format is unknown / truncated.
  static Size? fromBytes(Uint8List b) {
    if (b.length < 10) return null;
    // PNG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 && b.length >= 24) {
      final bd = ByteData.sublistView(b);
      return _ok(bd.getUint32(16).toDouble(), bd.getUint32(20).toDouble());
    }
    // GIF
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      final bd = ByteData.sublistView(b);
      return _ok(bd.getUint16(6, Endian.little).toDouble(), bd.getUint16(8, Endian.little).toDouble());
    }
    // JPEG
    if (b[0] == 0xFF && b[1] == 0xD8) return _jpeg(b);
    // WebP
    if (b.length >= 30 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45) return _webp(b);
    // BMP
    if (b[0] == 0x42 && b[1] == 0x4D && b.length >= 26) {
      final bd = ByteData.sublistView(b);
      return _ok(bd.getInt32(18, Endian.little).abs().toDouble(), bd.getInt32(22, Endian.little).abs().toDouble());
    }
    // SVG (text)
    final head = utf8.decode(b.length > 2048 ? Uint8List.sublistView(b, 0, 2048) : b, allowMalformed: true);
    if (head.contains('<svg')) return _svg(head);
    return null;
  }

  static Size? _ok(double w, double h) => w > 0 && h > 0 ? Size(w, h) : null;

  static Size? _jpeg(Uint8List b) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        i += 2;
        continue;
      }
      final len = (b[i + 2] << 8) | b[i + 3];
      // SOF0..SOF15 except DHT (C4), JPG (C8), DAC (CC)
      if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        return _ok(w.toDouble(), h.toDouble());
      }
      i += 2 + len;
    }
    return null;
  }

  static Size? _webp(Uint8List b) {
    final bd = ByteData.sublistView(b);
    final fmt = String.fromCharCodes(b.sublist(12, 16));
    if (fmt == 'VP8X') {
      final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return _ok(w.toDouble(), h.toDouble());
    }
    if (fmt == 'VP8L') {
      final v = bd.getUint32(21, Endian.little);
      return _ok((1 + (v & 0x3FFF)).toDouble(), (1 + ((v >> 14) & 0x3FFF)).toDouble());
    }
    if (fmt == 'VP8 ') {
      return _ok((bd.getUint16(26, Endian.little) & 0x3FFF).toDouble(), (bd.getUint16(28, Endian.little) & 0x3FFF).toDouble());
    }
    return null;
  }

  static Size? _svg(String head) {
    double? num(String attr) {
      final m = RegExp('$attr\\s*=\\s*["\']([0-9.]+)').firstMatch(head);
      return m == null ? null : double.tryParse(m.group(1)!);
    }

    final w = num('width');
    final h = num('height');
    if (w != null && h != null) return _ok(w, h);
    final vb = RegExp(r'viewBox\s*=\s*"[^"]*?\s([0-9.]+)\s+([0-9.]+)"').firstMatch(head);
    if (vb != null) return _ok(double.parse(vb.group(1)!), double.parse(vb.group(2)!));
    return null;
  }

  /// Size of a local file (reads at most the first 64 KB; JPEGs with huge EXIF blocks may need more, so it falls back to the
  /// whole file once).
  static Size? fromFile(File f) {
    try {
      if (!f.existsSync()) return null;
      final raf = f.openSync();
      try {
        final n = raf.lengthSync() < 65536 ? raf.lengthSync() : 65536;
        final s = fromBytes(raf.readSync(n));
        if (s != null || raf.lengthSync() <= 65536) return s;
      } finally {
        raf.closeSync();
      }
      return fromBytes(f.readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  /// `data:image/...;base64,....` URIs.
  static Size? fromDataUri(String uri) {
    final i = uri.indexOf('base64,');
    if (i < 0) return null;
    try {
      return fromBytes(base64Decode(uri.substring(i + 7)));
    } catch (_) {
      return null;
    }
  }

  /// A resolver for `CalculateChapter.imageSizeOf` (file path or data URI), memoised in [ImageCache.sizes].
  static Future<Size?> resolve(String src) async {
    final cached = ImageCache.sizes[src];
    if (cached != null) return cached;
    final s = src.startsWith('data:') ? fromDataUri(src) : fromFile(File(src));
    if (s != null) ImageCache.sizes[src] = s;
    return s;
  }
}
