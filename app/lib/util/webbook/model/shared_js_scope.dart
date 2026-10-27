// util/webbook/model/shared_js_scope.dart - the source's `jsLib`: JavaScript that runs before every rule script of that source. Upstream
// Legado evaluates it once into a shared Rhino scope; here the text is prepended to each script (parsed ASTs/compiled code are cached by
// the runtimes). `jsLib` may also be a JSON object `{"name": "https://.../lib.js"}`: every URL is downloaded (once, cached) and concatenated.
import 'dart:convert';

import '../../http.dart';
import '../util/cache_manager.dart';
import 'base_source.dart';

abstract class SharedJsScope {
  static final Map<String, String> _resolved = {};

  /// The JavaScript to prepend for [source] (null when it has no jsLib).
  static Future<String?> jsLibOf(BaseSource? source) async {
    final lib = source?.jsLib;
    if (lib == null || lib.trim().isEmpty) return null;
    final t = lib.trim();
    if (!t.startsWith('{')) return lib;
    final cacheKey = '${source!.getKey()}\u0001$t';
    final hit = _resolved[cacheKey];
    if (hit != null) return hit;
    Object? d;
    try {
      d = jsonDecode(t);
    } catch (_) {
      return lib; // not JSON after all: a JS object literal is not valid on its own, but let the engine report it
    }
    if (d is! Map) return lib;
    final sb = StringBuffer();
    for (final v in d.values) {
      final url = '$v';
      final key = 'jsLib:$url';
      var text = CacheManager.getString(key);
      if (text == null) {
        final res = await AppHttp.send(HttpRequest(url: url, useCookieJar: false));
        text = AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType);
        if (res.isSuccessful) CacheManager.put(key, text, saveTimeSeconds: 86400);
      }
      sb.writeln(text);
    }
    return _resolved[cacheKey] = sb.toString();
  }

  static void clear() => _resolved.clear();
}
