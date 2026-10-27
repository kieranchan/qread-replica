// util/cookiejar.dart - cookie handling for Dio clients other than the engine's own transport (which manages cookies itself): a lenient
// jar backed by [CookieStore] (never throws on malformed cookies) and an interceptor that sends/stores them. The original's
// `LenientCookieJar` / `SafeCookieManager` / `http2hosts` live here.
import 'package:dio/dio.dart';

import 'legado/cookie_jar.dart';

/// Hosts that must be contacted over HTTP/2 only (the original keeps a list for `CookieClient` setups); empty by default here.
final List<String> http2hosts = <String>[];

class LenientCookieJar {
  /// `Cookie` request header value for [uri] ('' when none).
  String loadForRequest(Uri uri) => CookieStore.getCookie(uri.toString());

  /// Stores `Set-Cookie` header values received from [uri]; malformed entries are skipped.
  void saveFromResponse(Uri uri, List<String> setCookies) {
    try {
      CookieStore.saveFromResponse(uri.toString(), setCookies);
    } catch (_) {
      // lenient: a bad cookie must never fail the request
    }
  }
}

class SafeCookieManager extends Interceptor {
  final LenientCookieJar jar;
  SafeCookieManager([LenientCookieJar? jar]) : jar = jar ?? LenientCookieJar();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final c = jar.loadForRequest(options.uri);
      if (c.isNotEmpty && !options.headers.keys.any((k) => k.toLowerCase() == 'cookie')) {
        options.headers['cookie'] = c;
      }
    } catch (_) {}
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final sc = response.headers['set-cookie'];
      if (sc != null) jar.saveFromResponse(response.requestOptions.uri, sc);
    } catch (_) {}
    handler.next(response);
  }
}
