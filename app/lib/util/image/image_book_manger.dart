// util/image/image_book_manger.dart — images of web books (class 1336 `ImageBookManger`, with its own `HeaderUrl` 1334 / `JsUrl` 1335 copies
// in the original): resolves the image urls found in chapter text (relative to the chapter url, with book-source headers) to local files
// through [ImgCacheManger]. The original also feeds images through the book's `imageDecode` JS; that script lives in the source engine
// (`util/webbook`) and can be supplied as [decoder].
import 'dart:io';
import 'dart:typed_data';

import 'image_cache_manger.dart';

export 'image_cache_manger.dart' show HeaderUrl, JsUrl;

/// Optional per-book image decoder (book source `imageDecode`): raw downloaded bytes -> displayable bytes.
typedef ImageDecoder = Future<Uint8List> Function(Uint8List bytes, String url);

abstract class ImageBookManger {
  /// Resolves [src] against [baseUrl] (the chapter url).
  static String resolveUrl(String baseUrl, String src) {
    final s = src.trim();
    if (s.startsWith('data:')) return s;
    final opt = s.indexOf(',{');
    final plain = opt < 0 ? s : s.substring(0, opt);
    final suffix = opt < 0 ? '' : s.substring(opt);
    if (plain.startsWith('http://') || plain.startsWith('https://')) return s;
    try {
      return '${Uri.parse(baseUrl).resolve(plain)}$suffix';
    } catch (_) {
      return s;
    }
  }

  /// Local file of a chapter image (downloaded on first use), or null.
  static Future<File?> imageFile(String baseUrl, String src, {Map<String, String> headers = const {}, ImageDecoder? decoder}) async {
    final full = resolveUrl(baseUrl, src);
    if (full.startsWith('data:')) return null;
    final u = HeaderUrl.parse(full);
    final withHeaders = headers.isEmpty ? u : HeaderUrl(u.url, {...headers, ...u.headers});
    if (decoder == null) return ImgCacheManger.fileFor(_encode(withHeaders));
    final bytes = await ImgCacheManger.bytesFor(_encode(withHeaders));
    if (bytes == null) return null;
    final decoded = await decoder(bytes, u.url);
    final f = File('${ImgCacheManger.dir.path}/decoded_${u.url.hashCode.toRadixString(16)}.img')..createSync(recursive: true);
    f.writeAsBytesSync(decoded, flush: true);
    return f;
  }

  static String _encode(HeaderUrl u) {
    if (u.headers.isEmpty) return u.url;
    final h = u.headers.entries.map((e) => '"${e.key}":"${e.value}"').join(',');
    return '${u.url},{"headers":{$h}}';
  }
}
