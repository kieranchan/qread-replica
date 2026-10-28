// 时光源 background web views (util/source/webview.dart, the original `_Webview`), `getheader` (0xe8bfa8) and `setHtml` (0xea8320).
// A scripted engine plays the page events (load start / stop, navigations, resources, ajax) the platform web view would report.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/source.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/source/baswebview.dart';
import 'package:newread/util/source/http.dart';
import 'package:newread/util/source/inapp_engine.dart';
import 'package:newread/util/source/js_engine.dart';
import 'package:newread/util/source/run.dart';
import 'package:newread/util/source/source.dart';
import 'package:newread/util/source/webview.dart';

import '../support/env.dart';
import 'support.dart';
import 'time_source_support.dart';

/// A web view whose page is played by [script] once something is loaded.
class ScriptedEngine extends SourceJsEngine {
  static final List<ScriptedEngine> created = [];
  static Future<void> Function(ScriptedEngine e)? script;

  final SourceJsEngineOptions options;
  final List<String> evaluated = [];
  String html = '';
  String? loadedUrl;
  String? body;
  Map<String, String>? headers;
  String? baseUrl;
  bool challenge = false;
  Object? jsValue;
  bool _disposed = false;

  ScriptedEngine(this.options) {
    created.add(this);
  }

  @override
  void addJavaScriptHandler(String name, JsHandler handler) {}

  void _play() => scheduleMicrotask(() async => await script?.call(this));

  @override
  Future<void> loadData(String html, {required String baseUrl}) async {
    this.html = html;
    this.baseUrl = baseUrl;
    _play();
  }

  @override
  Future<void> loadUrl(String url, {Map<String, String>? headers, String? body}) async {
    loadedUrl = url;
    this.headers = headers;
    this.body = body;
    _play();
  }

  @override
  Future<Object?> evaluateJavascript(String source) async {
    evaluated.add(source);
    if (source == '!!window._cf_chl_opt') return challenge;
    if (source == 'document.documentElement.outerHTML') return html;
    return jsValue;
  }

  @override
  bool get disposed => _disposed;

  @override
  Future<void> dispose() async => _disposed = true;
}

Future<void> ms(int n) => Future<void>.delayed(Duration(milliseconds: n));

void main() {
  late TestDevice dev;
  setUp(() async {
    dev = await freshArea();
    ScriptedEngine.created.clear();
    ScriptedEngine.script = null;
    SourceJsEngine.create = ScriptedEngine.new;
    WebCookies.push = (_) async {};
    WebCookies.pull = (_) async {};
    WebCookies.pullAll = () async {};
    SourceUi.resetForTests();
    Webview.unit = const Duration(milliseconds: 20);
  });
  tearDown(() async {
    Webview.unit = const Duration(seconds: 1);
    await SourceRun.clear();
    dev.delete();
  });

  group('background web view (_Webview 0xe495c4)', () {
    late FakeSourceEngine page;
    setUp(() {
      page = FakeSourceEngine(const SourceJsEngineOptions());
      SourceHandlers.register(page, const BaseSource(bookSourceUrl: 'https://src.test', bookSourceName: '源'));
    });

    test('webviewajax(url, html, body, header, ajaxregex) answers the first finished matching XMLHttpRequest', () async {
      ScriptedEngine.script = (e) async {
        e.onLoadStart?.call('https://a.test/p');
        e.onAjax?.call(const AjaxEvent('https://a.test/other', 4, 'no'));
        e.onAjax?.call(const AjaxEvent('https://a.test/api/list?id=1', 1));
        e.onLoadStop?.call('https://a.test/p');
        await ms(30);
        e.onAjax?.call(const AjaxEvent('https://a.test/api/list?id=1', 4, '{"ok":1}'));
      };
      final v = await page.callHandler('webviewajax', ['https://a.test/p', '', 'k=v', '{"User-Agent":"ua3","X":"1"}', r'api/list']);
      expect(v, '{"ok":1}');
      final e = ScriptedEngine.created.single;
      expect(e.options.interceptAjax, isTrue);
      expect(e.options.userAgent, 'ua3');
      expect(e.loadedUrl, 'https://a.test/p');
      expect(e.body, 'k=v');
      expect(e.headers, {'X': '1', 'Content-Type': 'application/x-www-form-urlencoded'});
      expect(e.disposed, isTrue);
    });

    test('webviewajax with html loads it under the url; no matching request answers the page', () async {
      ScriptedEngine.script = (e) async {
        e.onAjax?.call(const AjaxEvent('https://a.test/x', 4, 'x'));
      };
      Webview.unit = const Duration(milliseconds: 5);
      final v = await page.callHandler('webviewajax', ['https://a.test/', '<p>page</p>', '', '{}', r'api/']);
      expect(v, '<p>page</p>');
      expect(ScriptedEngine.created.single.baseUrl, 'https://a.test/');
    });

    test('urlregex: a url written in the page (src / srcset, entities decoded) is found by the poll', () async {
      ScriptedEngine.script = (e) async {
        e.html = '<video poster="/p.jpg" src="https://v.test/a.m3u8?x=1&amp;y=2"></video>';
        e.onLoadStop?.call('https://v.test/');
      };
      final v = await page.callHandler('webview', ['https://v.test/', '', '', '', '{}', '', r'\.m3u8']);
      expect(v, 'https://v.test/a.m3u8?x=1&y=2');
    });

    test('urlregex: a loaded resource or a failed request matches too', () async {
      ScriptedEngine.script = (e) async {
        e.onResource?.call('https://v.test/style.css');
        e.onLoadError?.call('https://cdn.test/b.mp4');
      };
      expect(await page.callHandler('webview', ['https://v.test/', '', '', '', '{}', '', r'\.mp4$']), 'https://cdn.test/b.mp4');
    });

    test('overrideUrlRegex: the matching navigation is the answer and the navigation is not cancelled', () async {
      final allowed = <bool>[];
      ScriptedEngine.script = (e) async {
        allowed.add(await e.onNavigate!('https://v.test/start'));
        allowed.add(await e.onNavigate!('https://v.test/book/7'));
      };
      expect(await page.callHandler('webview', ['https://v.test/start', '', '', '', '{}', r'book/\d+', '']), 'https://v.test/book/7');
      expect(allowed, [true, true]);
    });

    test('quiet page: js answers 1 step after the last load stop; endjs runs on every load; later loads restart the wait', () async {
      ScriptedEngine.script = (e) async {
        e.jsValue = 'first';
        e.onLoadStop?.call('https://q.test/1');
        await ms(5);
        // a redirect before the wait ran out: the answer waits for the new page
        e.onLoadStart?.call('https://q.test/2');
        e.jsValue = {'v': 2};
        e.onLoadStop?.call('https://q.test/2');
      };
      final r = await Webview.load(const WebviewRequest(url: 'https://q.test/1', js: 'getValue()', endjs: 'tidy()'));
      expect(r, '{"v":2}');
      final e = ScriptedEngine.created.single;
      expect(e.evaluated.where((s) => s == 'tidy()').length, 2);
      expect(e.evaluated.last, 'getValue()');
    });

    test('a Cloudflare challenge page gets 5 steps instead of 1', () async {
      ScriptedEngine.script = (e) async {
        e.challenge = true;
        e.onLoadStop?.call('https://cf.test/');
      };
      final sw = Stopwatch()..start();
      final r = await Webview.load(const WebviewRequest(url: 'https://cf.test/', html: '<b>cf</b>'));
      expect(r, '<b>cf</b>');
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(90));
    });

    test('the url list of a page (0x1ab0f8)', () {
      expect(
        Webview.extractUrls('<img SRC="a.png"><img data-src="b.png" srcset="c.png 1x, d.png 2x"><div background="e.jpg"><img src="a.png">'),
        // attribute by attribute (`\bsrc` also sees data-src), srcset lists last
        ['a.png', 'b.png', 'e.jpg', 'c.png', 'd.png'],
      );
      expect(Webview.extractUrls(''), isEmpty);
    });
  });

  test('getheader (0xe8bfa8): values as text, stored cookies of the url (cut at @js) merged, the page wins', () {
    CookieStore.setCookie('https://h.test', 'a=1;b=2');
    final h = SourceHttp.getheader('https://h.test/x@js:java.ajax()', '{"n":3,"cookie":"b=9"}');
    expect(h['n'], '3');
    expect(h.containsKey('cookie'), isFalse);
    expect(CookieStore.cookieToMap(h['Cookie']!), {'a': '1', 'b': '9'});
    expect(SourceHttp.getheader('http2://h.test/', '{}')['Cookie'], isNotNull);
    expect(SourceHttp.getheader('ftp://h.test/', 'bad'), isEmpty);
  });

  test('setHtml (0xea8320) stores the new page of the source and drops its runner', () async {
    SourceJsEngine.create = FakeSourceEngine.new;
    final html = fixture('time_source.html');
    await Sourcedata.load();
    await Sources.add({'bookSourceUrl': 'https://set.test', 'bookSourceName': '换页', 'html': html});
    final run = await SourceRun.of(BaseSource(bookSourceUrl: 'https://set.test', bookSourceName: '换页', html: html));
    await run.waitReady();
    final engine = FakeSourceEngine.created.last;
    await engine.callHandler('setHtml', [html]);
    expect(SourceRun.sourcerun.containsKey('https://set.test'), isTrue, reason: 'same html: nothing changes');
    await engine.callHandler('setHtml', ['https://set.test/new.html']);
    expect(Sourcedata.byUrl('https://set.test')!['html'], 'https://set.test/new.html');
    await ms(1);
    expect(SourceRun.sourcerun.containsKey('https://set.test'), isFalse);
    expect(run.destroyed, isTrue);
  });
}
