// A fake book site served from 127.0.0.1 for the engine tests (no internet): HTML, JSON, GBK pages, POST search, paging, cookies,
// redirects, gzip and flaky endpoints. Fixtures live in test/fixtures/engine/.
import 'dart:convert';
import 'dart:io';

import 'package:fast_gbk/fast_gbk.dart';

class FakeSite {
  final HttpServer server;
  final List<String> requests = [];
  final Map<String, int> hits = {};
  FakeSite._(this.server);

  String get base => 'http://127.0.0.1:${server.port}';

  static Future<FakeSite> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final site = FakeSite._(s);
    s.listen(site._handle);
    return site;
  }

  Future<void> close() => server.close(force: true);

  static String fixture(String name) => File('test/fixtures/engine/$name').readAsStringSync();

  String sourceJson(String name) => fixture(name).replaceAll('__BASE__', base);

  static List<int> _percentBytes(String s) {
    final out = <int>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '%' && i + 2 < s.length) {
        out.add(int.parse(s.substring(i + 1, i + 3), radix: 16));
        i += 3;
      } else if (c == '+') {
        out.add(0x20);
        i++;
      } else {
        out.addAll(utf8.encode(c));
        i++;
      }
    }
    return out;
  }

  static Map<String, List<int>> _rawParams(String raw) {
    final m = <String, List<int>>{};
    for (final part in raw.split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      final k = eq < 0 ? part : part.substring(0, eq);
      final v = eq < 0 ? '' : part.substring(eq + 1);
      m[k] = _percentBytes(v);
    }
    return m;
  }

  void _text(HttpRequest req, String body, {String type = 'text/html; charset=utf-8', int status = 200}) {
    req.response.statusCode = status;
    req.response.headers.set('content-type', type);
    req.response.add(utf8.encode(body));
    req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    requests.add('${req.method} ${req.uri}');
    hits[path] = (hits[path] ?? 0) + 1;
    final bodyBytes = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final body = utf8.decode(bodyBytes, allowMalformed: true);
    try {
      switch (path) {
        case '/html/search':
          return _text(req, fixture('search.html').replaceAll('__Q__', '${req.uri.queryParameters['q']}|p${req.uri.queryParameters['page']}|${req.headers.value('x-test')}'));
        case '/html/search_post':
          final ct = req.headers.contentType?.mimeType ?? '';
          return _text(req, fixture('search.html').replaceAll('__Q__', '$body|$ct'));
        case '/gbk/search':
          final wd = gbk.decode(_rawParams(req.uri.query)['wd'] ?? const [], allowMalformed: true);
          final html = fixture('search.html').replaceAll('__Q__', wd).replaceAll('<head>', '<head><meta http-equiv="Content-Type" content="text/html; charset=gbk">');
          req.response.headers.set('content-type', 'text/html');
          req.response.add(gbk.encode(html));
          return req.response.close();
        case '/gbk/header':
          req.response.headers.set('content-type', 'text/html; charset=GB2312');
          req.response.add(gbk.encode('<html><body><p id="t">你好，世界</p></body></html>'));
          return req.response.close();
        case '/book/1':
          return _text(req, fixture('book.html'));
        case '/book/2':
          return _text(req, fixture('book.html').replaceAll('斗破苍穹', '武动乾坤'));
        case '/book/1/toc':
          return _text(req, fixture('toc1.html'));
        case '/book/1/toc2':
          return _text(req, fixture('toc2.html'));
        case '/chapter/1':
          return _text(req, fixture('chapter1.html'));
        case '/chapter/1_2':
          return _text(req, fixture('chapter1_2.html'));
        case '/chapter/2':
          return _text(req, fixture('chapter2.html'));
        case '/chapter/3':
          return _text(req, fixture('chapter2.html').replaceAll('第二章 斗气大陆', '第三章 归来').replaceAll('斗气大陆的第二章', '第三章的内容'));
        case '/json/search':
          return _text(req, fixture('json_search.json').replaceAll('__Q__', '${req.uri.queryParameters['q']}|${req.uri.queryParameters['page']}'), type: 'application/json');
        case '/json/book/1':
          return _text(req, fixture('json_book.json'), type: 'application/json');
        case '/json/toc/1':
          return _text(req, fixture('json_toc.json'), type: 'application/json');
        case '/json/chapter/11':
          return _text(req, fixture('json_chapter.json'), type: 'application/json');
        case '/rss':
          return _text(req, fixture('rss.xml'), type: 'application/rss+xml');
        case '/cookie/set':
          req.response.headers.add('set-cookie', 'sid=abc123; Path=/; HttpOnly');
          req.response.headers.add('set-cookie', 'theme=dark; Path=/');
          return _text(req, 'set');
        case '/cookie/check':
          final c = req.headers.value('cookie') ?? '';
          return c.contains('sid=abc123') ? _text(req, 'ok:$c') : _text(req, 'denied', status: 403);
        case '/redir1':
          req.response.statusCode = 302;
          req.response.headers.set('location', '/redir2');
          return req.response.close();
        case '/redir2':
          req.response.statusCode = 301;
          req.response.headers.set('location', '$base/book/1');
          return req.response.close();
        case '/post-redir':
          req.response.statusCode = 302;
          req.response.headers.set('location', '/echo');
          return req.response.close();
        case '/gzip':
          req.response.headers.set('content-type', 'text/plain; charset=utf-8');
          req.response.headers.set('content-encoding', 'gzip');
          req.response.add(gzip.encode(utf8.encode('压缩内容 compressed')));
          return req.response.close();
        case '/flaky':
          if ((hits[path] ?? 0) <= 2) return _text(req, 'boom', status: 500);
          return _text(req, 'recovered');
        case '/bin':
          req.response.headers.set('content-type', 'application/octet-stream');
          req.response.add([0, 1, 2, 250, 255]);
          return req.response.close();
        case '/echo':
          final headers = <String, String>{};
          req.headers.forEach((k, v) => headers[k] = v.join(','));
          return _text(
              req,
              jsonEncode({
                'method': req.method,
                'path': path,
                'query': req.uri.query,
                'headers': headers,
                'body': body,
              }),
              type: 'application/json');
      }
      return _text(req, 'not found: $path', status: 404);
    } catch (e) {
      try {
        _text(req, 'server error $e', status: 500);
      } catch (_) {}
    }
  }
}
