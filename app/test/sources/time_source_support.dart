// Test doubles of the 时光源 runtime: a web-view engine that records what the app loads / evaluates and plays the page
// (test/fixtures/sources/time_source.html) in Dart, and the HTTP server that page talks to. The host has no web view, so
// [FakeTimePage] is a line-by-line Dart copy of the fixture's functions; it only runs functions the loaded html declares and talks to
// the app exclusively through the registered `callHandler` handlers, like the real page.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:newread/util/source/js_engine.dart';

class FakeSourceEngine extends SourceJsEngine {
  static final List<FakeSourceEngine> created = [];
  final SourceJsEngineOptions options;
  final Map<String, JsHandler> handlers = {};
  final List<String> evaluated = [];
  final List<String> loadedUrls = [];
  String? html;
  String? baseUrl;
  FakeTimePage? page;
  bool _disposed = false;

  FakeSourceEngine(this.options) {
    created.add(this);
  }

  /// What the page's `window.flutter_inappwebview.callHandler(name, …args)` gets.
  Future<Object?> callHandler(String name, [List<dynamic> args = const []]) async {
    final h = handlers[name];
    if (h == null) throw StateError('no handler $name');
    return await h(args);
  }

  @override
  void addJavaScriptHandler(String name, JsHandler handler) => handlers[name] = handler;

  @override
  Future<void> loadData(String html, {required String baseUrl}) async {
    this.html = html;
    this.baseUrl = baseUrl;
    final p = page = FakeTimePage(this, html, baseUrl);
    scheduleMicrotask(() async {
      await p.boot();
      onLoadStop?.call(baseUrl);
    });
  }

  /// Background pages: the navigation goes through [onNavigate] first (when intercepting), then the page "loads".
  @override
  Future<void> loadUrl(String url, {Map<String, String>? headers, String? body}) async {
    loadedUrls.add(url);
    final nav = onNavigate;
    if (options.intercept && nav != null && !await nav(url)) return;
    html = '<html><body>$url</body></html>';
    scheduleMicrotask(() => onLoadStop?.call(url));
  }

  static final RegExp _wrapper = RegExp(r'''var id="([^"]+)";[\s\S]*?const result = await ([\s\S]*?);\n\s*window\.flutter_inappwebview''');

  @override
  Future<Object?> evaluateJavascript(String source) async {
    evaluated.add(source);
    if (source == 'navigator.userAgent') return 'FakeWebKit/1.0';
    if (source == 'document.documentElement.outerHTML') return html ?? '';
    final m = _wrapper.firstMatch(source);
    final p = page;
    if (m != null && p != null) unawaited(p.run(m.group(1)!, m.group(2)!));
    return null;
  }

  @override
  bool get disposed => _disposed;

  @override
  Future<void> dispose() async => _disposed = true;
}

/// The fixture page, played in Dart.
class FakeTimePage {
  final FakeSourceEngine e;
  final String html;
  final String baseUrl;
  final Set<String> declared;
  final List<String> calls = [];

  /// `callbackjs(event, book)` calls of every page: (event, book name).
  static final List<(String, String)> events = [];

  FakeTimePage(this.e, this.html, this.baseUrl) : declared = {for (final m in RegExp(r'async function (\w+)\(').allMatches(html)) m.group(1)!};

  /// The page's start-up: `CookieJar(isCookieJar)` when it has the bridge.
  Future<void> boot() async {
    if (!html.contains("'CookieJar'")) return;
    final m = RegExp(r'var isCookieJar\s*=\s*(true|false)').firstMatch(html);
    await e.callHandler('CookieJar', [m == null ? true : m.group(1) == 'true']);
  }

  /// Turns the JavaScript of one call into a function name and its arguments.
  static (String, List<dynamic>) parseCall(String expr) {
    final ev = RegExp(r'^\(async function\(\)\{ return await eval\(("(?:[^"\\]|\\.)*")\); \}\)\(\)$').firstMatch(expr.trim());
    if (ev != null) return parseCall(jsonDecode(ev.group(1)!) as String);
    final m = RegExp(r'^(\w+)\(([\s\S]*)\)$').firstMatch(expr.trim());
    if (m == null) throw FormatException('not a call: $expr');
    final args = m.group(2)!.trim();
    if (args.isEmpty) return (m.group(1)!, const []);
    final json = args.replaceAllMapped(RegExp(r"'((?:[^'\\]|\\.)*)'"), (x) => jsonEncode(x.group(1)));
    return (m.group(1)!, jsonDecode('[$json]') as List<dynamic>);
  }

  /// The wrapper of util/source/baswebview.dart: run, then `call(id, result)`; errors give `call(id, "")` and `log(message)`.
  Future<void> run(String id, String expr) async {
    try {
      final (name, args) = parseCall(expr);
      if (!declared.contains(name)) throw StateError('ReferenceError: $name is not defined');
      calls.add(expr);
      final result = await _fn(name, args);
      await e.callHandler('call', [id, result]);
    } catch (err) {
      await e.callHandler('call', [id, '']);
      await e.callHandler('log', ['$err']);
    }
  }

  Future<Object?> h(String name, [List<dynamic> args = const []]) => e.callHandler(name, args);

  Future<Map> get(String url, [Map<String, String> headers = const {}]) async =>
      (await h('http', ['get', url, '', jsonEncode(headers), true, ''])) as Map;

  Future<String> server() async {
    final s = '${await h('cache.get', ['server']) ?? ''}';
    return s.isNotEmpty ? s : Uri.parse(baseUrl).origin;
  }

  Map<String, dynamic> toBook(String s, Map b) => {
        'bookUrl': '$s/book/${b['id']}',
        'name': b['name'],
        'author': b['author'],
        'kind': b['kind'],
        'coverUrl': b['cover'],
        'intro': b['intro'],
        'tocUrl': '$s/book/${b['id']}',
        'wordCount': b['words'],
        'type': 0,
        'latestChapterTitle': b['last'],
      };

  Future<Object?> _fn(String name, List<dynamic> a) async {
    switch (name) {
      case 'search':
        final s = await server();
        final r = await get('$s/search?key=${Uri.encodeComponent('${a[0]}')}&page=${a[1]}', {'X-Test': 'yes'});
        final list = (jsonDecode('${r['data']}') as Map)['data'] as List;
        return jsonEncode([for (final b in list) toBook(s, b as Map)]);
      case 'info':
        final r = await get('${a[0]}/info');
        final b = jsonDecode('${r['data']}') as Map;
        final book = toBook(await server(), b)
          ..['bookUrl'] = a[0]
          ..['intro'] = '@html:<p>${b['intro']}</p>'
          ..['tocUrl'] = await h('base64encode', [jsonEncode({'id': b['id']})]);
        return jsonEncode(book);
      case 'chapter':
        final id = (jsonDecode('${await h('base64decode', [a[0]])}') as Map)['id'];
        final r = await get('${await server()}/catalog?id=$id');
        return jsonEncode([
          for (final c in jsonDecode('${r['data']}') as List)
            {'name': c['title'], 'chapterId': c['url'], 'index': 0, 'isPay': false, 'isVip': c['vip'] == true, 'isVolume': false, 'tag': ''}
        ]);
      case 'content':
        return (await get('${a[0]}'))['data'];
      case 'getfinds':
        final s = await server();
        return jsonEncode([
          {'title': '线路', 'type': 2, 'chars': [s, '$s/v2'], 'default': s, 'action': "applyFilter('线路')"},
          {'title': '男频', 'url': '$s/find?c=male&page={{page}}'},
          {'title': '书源设置', 'url': '$s/settings.html', 'type': 1, 'width': 3},
          {'title': '筛选', 'type': 3, 'action': "applyFilter('筛选')"},
          {'title': '签到', 'type': 4, 'action': 'checkin()'},
          {'title': '分组'},
        ]);
      case 'applyFilter':
        final v = await h('cache.get', [a[0]]);
        if (a[0] == '线路') await h('cache.set', ['server', v]);
        await h('refreshExplore');
        return null;
      case 'checkin':
        return 'checked';
      case 'find':
        final s = await server();
        final r = await get('${a[0]}'.replaceAll('{{page}}', '${a[1]}'));
        return jsonEncode([for (final b in (jsonDecode('${r['data']}') as Map)['data'] as List) toBook(s, b as Map)]);
      case 'getloginurl':
        if (await h('cache.get', ['loginmode']) == 'form') {
          return jsonEncode([
            {'name': '账号', 'type': 'text'},
            {'name': '密码', 'type': 'password'},
            {'name': '检查', 'type': 'button', 'action': 'checkin()'},
          ]);
        }
        return '${await server()}/login.html';
      case 'login':
        final info = jsonDecode('${await h('cache.get', ['LoginInfo'])}'.isEmpty ? '{}' : '${await h('cache.get', ['LoginInfo'])}') as Map;
        final body = 'user=${Uri.encodeQueryComponent('${info['账号'] ?? ''}')}&pass=${Uri.encodeQueryComponent('${info['密码'] ?? ''}')}';
        await h('http', ['post', '${await server()}/login', body, '{}', true, '']);
        return '';
      case 'pay':
        return 'paid:${a[1]}';
      case 'imagedecrypt':
        return base64Decode('${a[1]}').reversed.toList();
      case 'gethelp':
        return '@html:<b>帮助</b>内容';
      case 'shouldOverrideUrlLoading':
        return !'${a[0]}'.contains('/book/');
      case 'callbackjs':
        events.add((('${a[0]}'), (jsonDecode('${a[1]}') as Map)['name'] as String? ?? ''));
        return '${a[0]}'.startsWith('long');
      case 'filter':
        return '${await server()}/filter.html';
      case 'findfilter':
        return '${a[0]}'.contains('c=male') ? 'data:text/html;base64,PGI+562b6YCJPC9iPg==' : '';
      case 'hang':
        return Completer<Object?>().future;
    }
    throw StateError('ReferenceError: $name is not defined');
  }
}

/// The site the fixture page reads.
class TimeServer {
  final HttpServer server;
  final List<HttpRequest> requests = [];
  final List<String> bodies = [];
  final String page;
  int pageStatus = 200;

  TimeServer._(this.server, this.page) {
    server.listen(_handle);
  }

  static Future<TimeServer> start(String page) async => TimeServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), page);

  String get base => 'http://127.0.0.1:${server.port}';

  static Map<String, Object> book(String id, String name, String words) =>
      {'id': id, 'name': name, 'author': '作者$id', 'kind': '玄幻', 'cover': '', 'intro': '简介$id', 'words': words, 'last': '第二章'};

  Future<void> _json(HttpResponse r, Object v) async {
    r.headers.contentType = ContentType.json;
    r.write(jsonEncode(v));
    await r.close();
  }

  Future<void> _handle(HttpRequest q) async {
    requests.add(q);
    final body = await utf8.decoder.bind(q).join();
    bodies.add(body);
    final r = q.response;
    final path = q.uri.path;
    final page = int.tryParse(q.uri.queryParameters['page'] ?? '1') ?? 1;
    switch (path) {
      case '/page.html':
        r.statusCode = pageStatus;
        r.headers.contentType = ContentType.html;
        if (pageStatus == 200) r.write(this.page);
        await r.close();
      case '/search':
      case '/find':
        await _json(r, {'data': page > 1 ? [] : [book('1', '测试书', '12.3万'), book('2', '另一本', '')]});
      case '/book/1/info':
        await _json(r, book('1', '测试书', '123456'));
      case '/catalog':
        await _json(r, [
          {'title': '第一章', 'url': '$base/c/1'},
          {'title': '第二章', 'url': '$base/c/2', 'vip': true},
        ]);
      case '/c/1':
        r.headers.set('content-type', 'text/html; charset=gbk');
        r.add(Uint8List.fromList(gbk.encode('<p>第一段内容</p><p>第二段&nbsp;内容</p><img src="http://img.test/x.png">')));
        await r.close();
      case '/login':
        final f = Uri.splitQueryString(body);
        r.headers.add('set-cookie', 'token=t-${f['user']}; Path=/');
        await _json(r, {'ok': true});
      case '/redirect':
        r.statusCode = 302;
        r.headers.set('location', '/me');
        await r.close();
      case '/me':
        await _json(r, {'cookie': q.headers.value('cookie') ?? '', 'type': q.headers.value('content-type') ?? '', 'body': body});
      default:
        r.statusCode = 404;
        await r.close();
    }
  }

  Future<void> close() => server.close(force: true);
}
