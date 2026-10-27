// util/source/qhttp.dart - the app's HTTP worker contract (rule_engine.txt section 4): a request map `{url, body, header, move, timeout}`
// answered with `{success, currentUrl, cookie, isCookieJar, response, error}`. It backs the callbacks of a server-side engine
// (get/post/head, functions 0x1ca9cc / 0x1ca330 / 0x1ca99c) and any caller that prefers plain maps over [AppHttp].
import '../http.dart';
import '../legado/cookie_jar.dart';

abstract class QHttp {
  static Future<Map<String, dynamic>> get(Map<String, dynamic> req) => _perform('GET', req);
  static Future<Map<String, dynamic>> post(Map<String, dynamic> req) => _perform('POST', req);
  static Future<Map<String, dynamic>> head(Map<String, dynamic> req) => _perform('HEAD', req);

  /// Default timeout of the original (`Duration` 0x5f5e100 microseconds = 100 s).
  static const Duration defaultTimeout = Duration(seconds: 100);

  static Future<Map<String, dynamic>> _perform(String method, Map<String, dynamic> req) async {
    final url = '${req['url'] ?? ''}';
    try {
      final headers = <String, String>{};
      final h = req['header'] ?? req['headers'];
      if (h is Map) {
        h.forEach((k, v) => headers['$k'] = '$v');
      }
      final t = req['timeout'];
      final timeout = t is num ? Duration(milliseconds: t.toInt()) : defaultTimeout;
      final move = req['move'];
      final res = await AppHttp.send(HttpRequest(
        url: url,
        method: method,
        headers: headers,
        body: method == 'POST' ? (req['body'] == null ? null : '${req['body']}') : null,
        timeout: timeout,
        followRedirects: move is bool ? move : true,
        useCookieJar: req['isCookieJar'] is bool ? req['isCookieJar'] as bool : true,
      ));
      final cs = headers.entries.where((e) => e.key.toLowerCase() == 'charset').map((e) => e.value).firstOrNull;
      return {
        'success': res.statusCode < 400,
        'currentUrl': res.url,
        'cookie': CookieStore.getCookie(res.url),
        'isCookieJar': true,
        'response': method == 'HEAD' ? '' : AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType, charset: cs),
        'statusCode': res.statusCode,
        'error': res.statusCode < 400 ? '' : 'HTTP ${res.statusCode} ${res.statusMessage}',
      };
    } catch (e) {
      return {'success': false, 'currentUrl': url, 'cookie': '', 'isCookieJar': false, 'response': '', 'error': e.toString()};
    }
  }
}
