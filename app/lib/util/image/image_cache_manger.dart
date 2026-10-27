// util/image/image_cache_manger.dart — on-disk image cache (`<documents>/images/<md5(url)>.<ext>`, class 1333 `ImgCacheManger`) and the url
// value classes `HeaderUrl` (class 1331: url + request headers) and `JsUrl` (class 1332: url produced by a script; the source engine in
// `util/webbook` evaluates `js`, this class only carries it).
//
// URL option syntax of book sources (Legado): `http://host/a.png,{"headers":{"Referer":"..."}}`; [HeaderUrl.parse] understands it.
// Downloads use an injectable [ImageFetcher] so tests run against a local server. TODO(asm 0x236484): the original's cache lives in an
// isolate (`ImageService._isolateEntry`); here the fetch is a plain async call.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../read/api/read_file_store.dart';
import '../../read/api/read_storage_root.dart';
import '../cahce/imagecache.dart';

class HeaderUrl {
  final String url;
  final Map<String, String> headers;

  const HeaderUrl(this.url, [this.headers = const {}]);

  /// `url` or `url,{json options}`; only the `headers` option is read.
  factory HeaderUrl.parse(String raw) {
    final s = raw.trim();
    final i = s.indexOf(',{');
    if (i < 0) return HeaderUrl(s);
    final url = s.substring(0, i);
    try {
      final opt = jsonDecode(s.substring(i + 1));
      final h = opt is Map ? opt['headers'] : null;
      if (h is Map) return HeaderUrl(url, {for (final e in h.entries) '${e.key}': '${e.value}'});
      if (h is String) {
        final hm = jsonDecode(h);
        if (hm is Map) return HeaderUrl(url, {for (final e in hm.entries) '${e.key}': '${e.value}'});
      }
    } catch (_) {}
    return HeaderUrl(url);
  }

  @override
  String toString() => url;
}

class JsUrl {
  final String js;
  final String baseUrl;

  const JsUrl(this.js, [this.baseUrl = '']);
}

typedef ImageFetcher = Future<Uint8List> Function(HeaderUrl url);

abstract class ImgCacheManger {
  static Dio dio = Dio(BaseOptions(
    responseType: ResponseType.bytes,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Replaceable in tests.
  static ImageFetcher fetcher = _defaultFetch;

  /// Maximum size of the disk cache in bytes (oldest files are removed first by [trim]).
  static int maxBytes = 300 * 1024 * 1024;

  static Future<Uint8List> _defaultFetch(HeaderUrl u) async {
    final r = await dio.get<List<int>>(u.url, options: Options(headers: u.headers, responseType: ResponseType.bytes));
    final code = r.statusCode ?? 0;
    if (code < 200 || code >= 300 || r.data == null) throw HttpException('图片下载失败: $code ${u.url}');
    return Uint8List.fromList(r.data!);
  }

  static Directory get dir => ReadStorageRoot.sub(ReadStorageRoot.images);

  static String _extOf(Uint8List d) {
    if (d.length > 3 && d[0] == 0xFF && d[1] == 0xD8) return 'jpg';
    if (d.length > 4 && d[0] == 0x89 && d[1] == 0x50) return 'png';
    if (d.length > 3 && d[0] == 0x47 && d[1] == 0x49) return 'gif';
    if (d.length > 12 && d[0] == 0x52 && d[8] == 0x57) return 'webp';
    return 'img';
  }

  /// Local file for [url] (a plain url or `url,{options}`): from the memory / disk cache, else downloaded. Null on failure.
  static Future<File?> fileFor(String url) async {
    final u = HeaderUrl.parse(url);
    final cached = Imagecache3.get(u.url);
    if (cached != null && File(cached).existsSync()) return File(cached);
    final d = dir..createSync(recursive: true);
    final key = ReadFileStore.md5Hex(u.url);
    for (final e in d.listSync()) {
      if (e is File && e.path.split(RegExp(r'[\\/]')).last.startsWith('$key.')) {
        Imagecache3.put(u.url, e.path);
        return e;
      }
    }
    try {
      final bytes = await fetcher(u);
      final f = File('${d.path}/$key.${_extOf(bytes)}');
      f.writeAsBytesSync(bytes, flush: true);
      Imagecache3.put(u.url, f.path);
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Bytes for [url] (memory cache first).
  static Future<Uint8List?> bytesFor(String url) async {
    final u = HeaderUrl.parse(url);
    final m = Imagecache.get(u.url);
    if (m != null) return m;
    final f = await fileFor(url);
    if (f == null) return null;
    final b = f.readAsBytesSync();
    Imagecache.put(u.url, b);
    return b;
  }

  /// Deletes the oldest files until the cache is below [maxBytes].
  static int trim() {
    final d = dir;
    if (!d.existsSync()) return 0;
    final files = d.listSync().whereType<File>().toList()..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    var total = files.fold<int>(0, (n, f) => n + f.lengthSync());
    var removed = 0;
    for (final f in files) {
      if (total <= maxBytes) break;
      total -= f.lengthSync();
      f.deleteSync();
      removed++;
    }
    return removed;
  }

  static Future<void> clear() async {
    final d = dir;
    if (d.existsSync()) d.deleteSync(recursive: true);
    Imagecache.clear();
    Imagecache2.clear();
    Imagecache3.clear();
  }
}
