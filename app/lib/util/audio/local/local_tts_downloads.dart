// util/audio/local/local_tts_downloads.dart — 下载模型 (tts_setting.dart 0xfe860c): the model list `static/down.json`.
// The original fetches `https://api.qread.xyz/static/down.json`; the replica asks the own server (`Common.apiBase` +
// `static/down.json`, uploaded with `qread-admin set-static down`). Format, from the parser closure 0x60da5c: one JSON object
// {"<shown name>": "<url>", …}; entries whose value is null or empty are skipped, keys and values are read as text, order kept.
// Not an object → `获取下载地址失败`; nothing usable → `暂无可用下载地址`; one entry → opened at once; several → a sheet to pick
// from; errors → `获取下载地址失败：<e>`. The original opens the chosen url in the browser (LaunchMode.externalApplication).
// Replica: a url that names a model archive or a vocos `.onnx` is downloaded inside the app with progress and imported right away
// (see [isDirect]); other urls (web pages) still open in the browser.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../../common/app_dirs.dart';
import '../../../common/common.dart';
import 'local_tts_files.dart';

abstract class LocalTtsDownloads {
  static const String endpoint = 'static/down.json';

  /// Client for the list and the downloads; tests point it at a local server.
  static Dio? dio;

  static Dio get _dio => dio ??= Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

  static String get listUrl => Common.url(endpoint);

  /// The entries of `down.json`; null when the reply is not a JSON object (`获取下载地址失败`). Throws on network errors.
  static Future<Map<String, String>?> fetchList() async {
    final r = await _dio.get<List<int>>(listUrl, options: Options(responseType: ResponseType.bytes));
    final Object? v;
    try {
      v = jsonDecode(utf8.decode(r.data ?? const [], allowMalformed: true));
    } on FormatException {
      return null;
    }
    return v is Map ? parse(v) : null;
  }

  /// The parser of the original (0x60da5c): `{k: v}` → `{'$k': '$v'}` for every non-empty value.
  static Map<String, String> parse(Map<dynamic, dynamic> v) {
    final out = <String, String>{};
    v.forEach((k, val) {
      if (val == null) return;
      final s = '$val'.trim();
      if (s.isEmpty) return;
      out['$k'] = s;
    });
    return out;
  }

  /// Whether [url] is a file the app can import itself (an archive or a vocos vocoder) rather than a page to open (replica).
  static bool isDirect(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    return LocalTtsFiles.isArchive(path) || LocalTtsFiles.isVocoderFile(path);
  }

  /// The local name a download of [url] gets.
  static String fileName(String url) {
    final b = p.basename(Uri.tryParse(url)?.path ?? url);
    return b.isEmpty ? 'model.zip' : Uri.decodeComponent(b);
  }

  /// Downloads [url] into `<documents>/cache/local_tts_download/` and returns the file (a partial file is removed on failure).
  static Future<File> download(String url, {void Function(int received, int total)? onProgress, CancelToken? cancel}) async {
    final dir = Directory(AppDirs.path('cache', 'local_tts_download'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final target = File(p.join(dir.path, fileName(url)));
    final part = File('${target.path}.part');
    try {
      await _dio.download(url, part.path, onReceiveProgress: onProgress, cancelToken: cancel);
      if (target.existsSync()) target.deleteSync();
      return part.renameSync(target.path);
    } catch (_) {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
  }

  /// Removes downloaded files once they are imported.
  static void clean(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
