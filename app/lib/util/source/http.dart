// util/source/http.dart — the request behind the page's `http` handler (`callHandler('http', method, url, body, headersJson,
// followRedirects, contentType)`).
//
// Original: handler 0xea7dcc (instance, honours the page's `isCookieJar`) / 0xea6d40 (static, cookie jar always on), request
// 0xea6ed8: headers are a JSON string (`{` …); a POST without `Content-Type` gets `application/x-www-form-urlencoded` (an explicit
// content type argument wins); `get` / `head` / `post` go to an HTTP isolate (util/source/http.dart 0xe5678c: dio, manual
// redirects `重定向次数过多`, gzip/deflate/br, `http2://` = HTTP/2 over https, timeout 100 s) through the `posthasheader` message
// (0xea7274 `{url, body, myheader, move, isCookieJar, timeout}` -> `{success, cookie, responseData, error}`); the cookies of the
// answer are saved for the url when the cookie jar is on. A failed request answers `Response(method, statusCode 0, error)`.
//
// A headers argument that is a JSON object goes through `getheader` (0xe8bfa8): the values become text and, for http urls, the
// stored cookies of the url (the part before an `@js`, `http2` read as `https`) are merged into its `Cookie` header — also when the
// page switched its cookie jar off (the jar then only stops keeping the answer's cookies).
//
// Replica: the app's HTTP client (util/http.dart: cookie jar, redirects, gzip/deflate, charset detection incl. GBK/GB18030/Big5).
// `http2://` / `https2://` are sent as plain https (no HTTP/2 client here).
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../http.dart';
import '../legado/cookie_jar.dart';
import 'response.dart';

abstract class SourceHttp {
  /// Default timeout of the original's HTTP isolate (Duration 0x5f5e100 us).
  static const Duration timeout = Duration(seconds: 100);

  /// Parses the headers argument: a JSON object text (other text gives no headers).
  static Map<String, String> headersOf(Object? h) {
    final out = <String, String>{};
    Object? v = h;
    if (v is String) {
      final t = v.trim();
      if (!t.startsWith('{')) return out;
      try {
        v = jsonDecode(t);
      } catch (_) {
        return out;
      }
    }
    if (v is Map) v.forEach((k, val) => out['$k'] = val is String ? val : (val == null ? '' : '$val'));
    return out;
  }

  /// 0xe8bfa8 `getheader(url, headerJson)`: the header map of a JSON object text (values as text); for an http(s) [url] the
  /// stored cookies of the url (cut at `@js`) are merged into `Cookie` (the page's own values win).
  static Map<String, String> getheader(String url, Object? headers) {
    var u = url;
    final at = u.indexOf('@js');
    if (at >= 0) u = u.substring(0, at);
    final out = <String, String>{};
    try {
      final m = headers is Map ? headers : jsonDecode('$headers');
      if (m is! Map) throw const FormatException('not a map');
      m.forEach((k, v) => out['$k'] = v is String ? v : '$v');
    } catch (e) {
      debugPrint('getheader error $u,$headers');
    }
    if (u.startsWith('http')) {
      var key = 'Cookie';
      for (final k in out.keys) {
        if (k.toLowerCase() == key.toLowerCase()) key = k;
      }
      final stored = CookieStore.getCookie(u.replaceAll('http2', 'https'));
      final merged = CookieStore.cookieToMap(stored)..addAll(CookieStore.cookieToMap(out[key] ?? ''));
      final text = CookieStore.mapToCookie(merged) ?? '';
      if (text.isNotEmpty) {
        out.remove(key);
        out['Cookie'] = text;
      }
    }
    return out;
  }

  /// `http2://host` / `https2://host` -> `https://host`.
  static String normalizeUrl(String url) {
    final t = url.trim();
    final lower = t.toLowerCase();
    if (lower.startsWith('http2://')) return 'https://${t.substring(8)}';
    if (lower.startsWith('https2://')) return 'https://${t.substring(9)}';
    return t;
  }

  static bool _bool(Object? v, bool def) => v == null ? def : (v is bool ? v : !('$v' == 'false' || '$v' == '0' || '$v'.isEmpty));

  /// Runs one request for the page. Never throws: failures come back as [Response.error].
  static Future<Response> request({
    required String method,
    required String url,
    String body = '',
    Object? headers,
    Object? followRedirects,
    String contentType = '',
    bool isCookieJar = true,
  }) async {
    final m = method.trim().toLowerCase().isEmpty ? 'get' : method.trim().toLowerCase();
    try {
      final h = headers is String && headers.trim().startsWith('{') ? getheader(url, headers) : headersOf(headers);
      if (m == 'post') {
        final key = h.keys.firstWhere((k) => k.toLowerCase() == 'content-type', orElse: () => '');
        if (contentType.trim().isNotEmpty) {
          if (key.isNotEmpty) h.remove(key);
          h['Content-Type'] = contentType.trim();
        } else if (key.isEmpty) {
          h['Content-Type'] = 'application/x-www-form-urlencoded';
        }
      }
      final res = await AppHttp.send(HttpRequest(
        url: normalizeUrl(url),
        method: m.toUpperCase(),
        headers: h,
        body: m == 'post' ? body : null,
        timeout: timeout,
        followRedirects: _bool(followRedirects, true),
        useCookieJar: isCookieJar,
      ));
      return Response(
        method: m,
        data: m == 'head' ? '' : AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType),
        body: base64Encode(res.bodyBytes),
        headers: res.headers,
        statusCode: res.statusCode,
        statusMessage: res.statusMessage,
      );
    } catch (e) {
      return Response.error(m, e);
    }
  }
}
