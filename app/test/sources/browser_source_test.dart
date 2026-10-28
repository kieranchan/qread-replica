// The built-in 「浏览器」 时光源 (util/source/browser_source.dart) and the in-app browser's 阅读模式 that uses it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/common.dart';
import 'package:newread/common/nav.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/web/chrome_inapp.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/source/browser_source.dart';
import 'package:newread/util/source/browser_source_page.dart';
import 'package:newread/util/source/js_engine.dart';
import 'package:newread/util/source/run.dart';
import 'package:newread/util/source/source.dart';
import 'package:newread/util/toast.dart';
import 'package:newread/util/webbook/model/book_source.dart';

import '../support/env.dart';
import 'support.dart';
import 'time_source_support.dart';

const String _page = 'https://site.test/book/70114/';
const String _html = '<html><head><title>重建聊斋最新章节_笔趣阁</title><meta property="og:novel:author" content="野亮"></head><body><a href="1.html">第一章</a></body></html>';

/// Pumps with slices of real time until [done]: the flow mixes widget timers with real I/O (storage, the fake engine's microtasks).
Future<void> untilReal(WidgetTester t, bool Function() done, {int max = 200}) async {
  for (var i = 0; i < max && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'condition not reached; toasts: ${Toast.log}; dialogs: ${find.byType(AlertDialog).evaluate().length}; sheets: ${find.byType(BottomSheet).evaluate().length}');
}

void main() {
  late TestDevice dev;
  setUp(() async {
    dev = await freshArea();
    SourceJsEngine.create = FakeSourceEngine.new;
    FakeSourceEngine.created.clear();
    BrowserSource.remotePage = '';
  });
  tearDown(() async {
    await SourceRun.clear();
    BrowserSource.remotePage = '';
    dev.delete();
  });

  test('origins: `<page>@chrome` belongs to the 浏览器 source; the store hands it out without keeping it', () {
    expect(BrowserSource.originOf(_page), '$_page@chrome');
    expect(BrowserSource.isOrigin('$_page@chrome'), isTrue);
    expect(BrowserSource.isOrigin('@chrome'), isFalse);
    expect(BrowserSource.isOrigin(_page), isFalse);
    expect(BrowserSource.pageUrl('$_page@chrome'), _page);
    expect(BrowserSource.pageUrl('https://other.test/'), 'https://other.test/');

    final raw = Sourcedata.byUrl('$_page@chrome');
    expect(raw, isNotNull);
    expect(raw!['bookSourceName'], '浏览器');
    expect(raw['html'], browserSourcePage);
    expect(BaseSource.isTimeSource(raw), isTrue);
    final s = BookSource.fromJson(raw);
    expect(s.isTimeSource, isTrue);
    expect(s.bookSourceUrl, '$_page@chrome');
    expect(s.toBaseSource().htmlIsUrl, isFalse);
    expect(Sourcedata.sourceByUrl('$_page@chrome')!.bookSourceName, '浏览器');
    expect(Sourcedata.raw.where((m) => m['bookSourceName'] == '浏览器'), isEmpty);
    expect(Sourcedata.byUrl('https://unknown.test/'), isNull);
  });

  test('the built-in page declares the entry points and calls no outside service', () {
    for (final fn in ['search', 'info', 'getinfo', 'chapter', 'content']) {
      expect(browserSourcePage, contains('async function $fn('), reason: fn);
    }
    expect(browserSourcePage, contains("'CookieJar'"));
    expect(browserSourcePage, isNot(contains('qread.xyz')));
    expect(browserSourcePage, isNot(contains('<script src=')));
    expect(BrowserSource.looksLikePage(browserSourcePage), isTrue);
    expect(BrowserSource.looksLikePage('<html></html>'), isFalse);
  });

  test('server copy: a fetched page replaces the built-in one, a 404 drops it, errors keep it', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var mode = 'page';
    const remote = '<html><script>async function getinfo(h,u){} async function chapter(t,b){} /* server copy */</script></html>';
    server.listen((req) async {
      if (mode == 'page') {
        req.response.headers.contentType = ContentType.html;
        req.response.write(remote);
      } else if (mode == 'junk') {
        req.response.write('<html>nothing</html>');
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final oldBase = Common.apiBase;
    Common.apiBase = 'http://127.0.0.1:${server.port}';
    try {
      expect(await BrowserSource.refresh(), isTrue);
      expect(BrowserSource.page, remote);
      expect(Sourcedata.byUrl('$_page@chrome')!['html'], remote);
      expect(await Storage.read(BrowserSource.remoteKey), remote);
      // start-up reads the cached copy back
      BrowserSource.remotePage = '';
      await BrowserSource.load();
      expect(BrowserSource.page, remote);
      mode = 'junk';
      expect(await BrowserSource.refresh(), isFalse);
      expect(BrowserSource.page, remote);
      mode = '404';
      expect(await BrowserSource.refresh(), isFalse);
      expect(BrowserSource.page, browserSourcePage);
      expect(await Storage.read(BrowserSource.remoteKey), '');
      await server.close(force: true);
      expect(await BrowserSource.refresh(), isFalse);
      expect(BrowserSource.page, browserSourcePage);
    } finally {
      Common.apiBase = oldBase;
      await server.close(force: true);
    }
  });

  testWidgets('阅读模式: the open page is parsed by the 浏览器 source and the detail page opens with the book', (t) async {
    final opened = <Book>[];
    Nav.openBook = (c, b) async => opened.add(b);
    await t.runAsync(() async {
      await Storage.write('neverShowReadingModeHint', 'true');
      await Storage.setBool('useReplaceRule', true);
    });
    await t.pumpWidget(app(const ChromeInappPage(url: _page)));
    await idle(t);
    final c = FakeWebController.created.single;
    expect(c.url.value, _page);
    c.evalResults['outerHTML'] = _html;
    await act(t, () => t.tap(find.byKey(const Key('chrome_menu'))));
    await act(t, () => t.tap(find.text('阅读模式')));
    await untilReal(t, () => opened.isNotEmpty || Toast.log.any((m) => m.contains('失败')));
    expect(Toast.log.where((m) => m.contains('失败')), isEmpty);
    final b = opened.single;
    expect(b.bookUrl, _page);
    expect(b.origin, '$_page@chrome');
    expect(b.name, '重建聊斋最新章节_笔趣阁');
    expect(b.author, '野亮');
    expect(b.tocUrl, _page);
    expect(b.isinfo, isTrue);
    expect(b.useReplaceRule, isTrue);
    // the page ran as a 时光源 of its own (one runner per page) and got the html, not a url to fetch
    final e = FakeSourceEngine.created.single;
    expect(e.html, browserSourcePage.trim());
    expect(e.baseUrl, '$_page@chrome');
    expect(e.page!.calls.single, startsWith('getinfo('));
    expect(e.page!.calls.single, contains('重建聊斋'));
    expect(e.loadedUrls, isEmpty);
    expect(SourceRun.sourcerun.keys, ['$_page@chrome']);
  });

  testWidgets('阅读模式: the start page has no site; the hint dialog can be declined', (t) async {
    final opened = <Book>[];
    Nav.openBook = (c, b) async => opened.add(b);
    await t.pumpWidget(app(const ChromeInappPage(key: Key('home'))));
    await idle(t);
    await act(t, () => t.tap(find.byKey(const Key('chrome_menu'))));
    await act(t, () => t.tap(find.text('阅读模式')));
    await untilReal(t, () => Toast.log.contains('请先打开一个网站'));
    // a site (a new page: the key keeps Flutter from reusing the start page's state), but the hint is declined
    await t.pumpWidget(app(const ChromeInappPage(key: Key('site'), url: _page)));
    await idle(t);
    await act(t, () => t.tap(find.byKey(const Key('chrome_menu'))));
    await act(t, () => t.tap(find.text('阅读模式')));
    await untilReal(t, () => find.text('阅读模式可以将目录页转换成书本，请确保在目录页使用阅读模式。').evaluate().isNotEmpty);
    await act(t, () => t.tap(find.text('取消')));
    await untilReal(t, () => find.text('取消').evaluate().isEmpty);
    expect(opened, isEmpty);
    expect(FakeSourceEngine.created, isEmpty);
  });
}
