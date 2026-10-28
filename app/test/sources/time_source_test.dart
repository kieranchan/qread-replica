// 时光源 runtime (util/source/): result parsing, the runner over a fake web view playing test/fixtures/sources/time_source.html,
// the bridge handlers (http, cache, cookie, browser hooks, background web view, conversions) and the BookSearchService / reader
// paths. Everything talks to a local test server.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/common/common.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/book.dart' as m;
import 'package:newread/models/source.dart';
import 'package:newread/pages/read/web_book_loader.dart';
import 'package:newread/pages/search/engine_book_search_service.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/chinese_utils.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/source/baswebview.dart';
import 'package:newread/util/source/cache.dart';
import 'package:newread/util/source/http.dart';
import 'package:newread/util/source/inapp_engine.dart';
import 'package:newread/util/source/js_engine.dart';
import 'package:newread/util/source/run.dart';
import 'package:newread/util/source/source.dart';
import 'package:newread/util/source/time_source_api.dart';
import 'package:newread/util/source/webview.dart';
import 'package:newread/util/webbook/model/book.dart' as wb;
import 'package:newread/util/webbook/model/book_source.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/env.dart';
import 'support.dart';
import 'time_source_support.dart';

late TimeServer site;

Map<String, dynamic> rawSource({String? html}) => {
      'bookSourceUrl': site.base,
      'bookSourceName': '测试时光源',
      'bookSourceGroup': '时光源',
      'html': html ?? fixture('time_source.html'),
      'login': true,
      'help': true,
      'enabled': true,
      'enabledExplore': true,
    };

BookSource engineSource({String? html}) => BookSource.fromJson(rawSource(html: html));

void installFakes() {
  FakeSourceEngine.created.clear();
  SourceJsEngine.create = FakeSourceEngine.new;
  WebCookies.push = (_) async {};
  WebCookies.pull = (_) async {};
  WebCookies.pullAll = () async {};
  SourceUi.resetForTests();
  SourceRuntime.webViewUA = null;
  SourceRuntime.packageInfo = () async => PackageInfo(appName: 'newread', packageName: 'test', version: '2.2.1026', buildNumber: '1026');
  SourceRun.readyTimeout = const Duration(seconds: 60);
}

void main() {
  late TestDevice dev;
  setUpAll(() async => site = await TimeServer.start(fixture('time_source.html')));
  tearDownAll(() => site.close());
  setUp(() async {
    dev = await freshArea();
    installFakes();
    site.requests.clear();
    site.bodies.clear();
    site.pageStatus = 200;
  });
  tearDown(() async {
    await SourceRun.clear();
    dev.delete();
  });

  group('parsing (the original _parse*Isolate functions)', () {
    test('jsArg normalises like 0xd576c', () {
      expect(jsArg(null), '');
      expect(jsArg('null'), '');
      expect(jsArg('"quoted \\"x\\""'), 'quoted "x"');
      expect(jsArg("'single'"), 'single');
      expect(jsArg(3.0), '3');
      expect(jsArg(true), 'true');
      expect(jsArg({'a': 1}), '{"a":1}');
      expect(jsArg('plain'), 'plain');
    });

    test('word counts become n万字 (0xe694ec)', () {
      expect(SourceParse.formatWordCount('12.3万'), '12万字');
      expect(SourceParse.formatWordCount('123456'), '12.35万字');
      expect(SourceParse.formatWordCount('30000字'), '3万字');
      expect(SourceParse.formatWordCount('3千'), '0.30万字');
      expect(SourceParse.formatWordCount(''), '0万字');
      expect(SourceParse.formatWordCount('未知'), '0万字');
    });

    test('books, book, chapters', () {
      final books = SourceParse.books(jsonEncode([
        {'bookUrl': 'u1', 'name': '书', 'author': '甲', 'type': 1, 'wordCount': '100万'},
        'not a book',
      ]));
      expect(books.single.bookUrl, 'u1');
      expect(books.single.type_, 1);
      expect(books.single.wordCount, '100万字');
      expect(SourceParse.books('[]'), isEmpty);
      expect(SourceParse.books(''), isEmpty);
      // a JSON string holding JSON (pages that stringify twice)
      expect(SourceParse.books(jsonEncode(jsonEncode([{'bookUrl': 'x'}]))).single.bookUrl, 'x');
      expect(SourceParse.book(jsonEncode({'bookUrl': 'b', 'intro': '@html:<p>x</p>'})).intro, '@html:<p>x</p>');
      expect(() => SourceParse.book('[]'), throwsFormatException);
      final ch = SourceParse.chapters(jsonEncode([
        {'name': '一', 'chapterId': 'c1', 'index': 9},
        {'name': '二', 'chapterId': 'c2', 'isVip': true},
        {'name': '🔒三', 'chapterId': 'c3', 'isVip': true, 'isPay': true},
      ]));
      expect([for (final c in ch) c.index], [0, 1, 2]);
      expect([for (final c in ch) c.name], ['一', '🔒二', '🔒三']);
      expect(ch[1].isVip, isTrue);
      expect(ch[2].isPay, isTrue);
    });

    test('explore entries: 时光源 kinds 0..4 map onto the engine kinds', () {
      final k = SourceParse.explores(jsonEncode([
        {'title': '列表', 'url': 'u?page={{page}}'},
        {'title': '网页', 'url': 'http://w', 'type': 1, 'useShouldOverrideUrlLoading': true},
        {'title': '下拉', 'type': 2, 'chars': ['a', 'b'], 'default': 'b', 'action': 'f()'},
        {'title': '输入', 'type': 3, 'action': 'g()'},
        {'title': '按钮', 'type': 4, 'action': 'h()'},
        {'title': '脚本', 'js': 'k()'},
        {'title': '标题'},
      ]));
      expect([for (final e in k) e.type], [
        ExploreKind.typeUrl,
        ExploreKind.typeWeb,
        ExploreKind.typeSelect,
        ExploreKind.typeText,
        ExploreKind.typeButton,
        ExploreKind.typeButton,
        ExploreKind.typeTitle,
      ]);
      expect(k[1].useShouldOverrideUrlLoading, isTrue);
      expect(k[2].chars, ['a', 'b']);
      expect(k[2].defaultValue, 'b');
      expect(k[5].action, 'k()');
      expect(k[6].width, 3);
    });

    test('a map is a 时光源 when it has an html engine and no Legado rules', () {
      expect(BaseSource.isTimeSource(rawSource(html: '<html></html>')), isTrue);
      expect(BaseSource.isTimeSource({'bookSourceUrl': 'u', 'html': '@yuedu{}'}), isFalse);
      expect(BaseSource.isTimeSource({'bookSourceUrl': 'u', 'html': '<p>', 'searchUrl': 's'}), isFalse);
      expect(BaseSource.isTimeSource({'bookSourceUrl': 'u', 'html': '<p>', 'isqread': true}), isFalse);
      expect(engineSource(html: '<p>').isTimeSource, isTrue);
      expect(BookSource.fromJson({'bookSourceUrl': 'u', 'bookSourceName': 'n', 'searchUrl': 's', 'html': '<p>'}).isTimeSource, isFalse);
      final b = BaseSource.fromJson(rawSource(html: 'https://x/page.html'));
      expect((b.login, b.help, b.htmlIsUrl), (true, true, true));
    });
  });

  group('runner (SourceRun over the fake web view)', () {
    test('loads the page once, waits for CookieJar, calls search with JSON arguments and parses the books', () async {
      final books = await SourceApi.search(engineSource(), '测试', useCache: false);
      expect(FakeSourceEngine.created, hasLength(1));
      final e = FakeSourceEngine.created.single;
      expect(e.html, fixture('time_source.html').trim());
      expect(e.baseUrl, site.base);
      expect(e.evaluated.any((s) => s.contains('const result = await search("测试",1,"search");')), isTrue);
      expect(e.evaluated.any((s) => s.contains("window.flutter_inappwebview.callHandler('call', id,result);")), isTrue);
      expect([for (final b in books) b.name], ['测试书', '另一本']);
      expect(books.first.origin, site.base);
      expect(books.first.originName, '测试时光源');
      expect(books.first.bookUrl, '${site.base}/book/1');
      expect(books.first.wordCount, '12万字');
      expect(books.last.wordCount, '0万字');
      expect(site.requests.first.headers.value('x-test'), 'yes');
      // the runner is reused; the page reported its user agent
      await SourceApi.search(engineSource(), '另一个', useCache: false);
      expect(FakeSourceEngine.created, hasLength(1));
      expect(SourceRuntime.webViewUA, 'FakeWebKit/1.0');
      expect(SourceRun.sourcerun.keys, [site.base]);
    });

    test('an edited html restarts the page; 重载 drops the runner', () async {
      await SourceApi.search(engineSource(), 'a', useCache: false);
      await SourceApi.search(engineSource(html: '${fixture('time_source.html')}\n<!-- v2 -->'), 'a', useCache: false);
      expect(FakeSourceEngine.created, hasLength(2));
      expect(FakeSourceEngine.created.first.disposed, isTrue);
      SourceApi.reloadSource(site.base);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(SourceRun.sourcerun, isEmpty);
      expect(FakeSourceEngine.created.last.disposed, isTrue);
    });

    test('info, toc (info first for a search result), content as reader text', () async {
      final hit = (await SourceApi.search(engineSource(), '测试', useCache: false)).first.toBook();
      final chapters = await SourceApi.chapters(engineSource(), hit);
      // the search result still had its book url as toc url: info() ran first and gave the real one
      expect(hit.tocUrl, base64Encode(utf8.encode('{"id":"1"}')));
      expect(hit.intro, '@html:<p>简介1</p>');
      expect(hit.wordCount, '12.35万字');
      expect([for (final c in chapters) c.title], ['第一章', '🔒第二章']);
      expect(chapters[1].isVip, isTrue);
      expect(chapters.first.chapterId, '${site.base}/c/1');
      final text = await SourceApi.content(engineSource(), hit, chapters.first);
      expect(text, '　　第一段内容\n　　第二段 内容\n　　<img src="http://img.test/x.png">');
      final page = FakeSourceEngine.created.single.page!;
      expect(page.calls.where((c) => c.startsWith('content(')).single, 'content("${site.base}/c/1","${site.base}/book/1",0)');
      expect(page.calls.where((c) => c.startsWith('chapter(')).single, startsWith('chapter("'));
    });

    test('audio books keep the media url the page returns', () {
      expect(TimeSourceApi.formatContent(' https://a/b.mp3 ', 1), 'https://a/b.mp3');
      expect(TimeSourceApi.formatContent('<p>x</p>', 0), '　　x');
    });

    test('discovery: entries cached until refreshExplore, select values stored with cache.set, actions run in the page', () async {
      final src = engineSource();
      final kinds = await SourceApi.exploreKinds(src);
      expect([for (final k in kinds) k.title], ['线路', '男频', '书源设置', '筛选', '签到', '分组']);
      expect(kinds[0].type, ExploreKind.typeSelect);
      expect(kinds[0].defaultValue, site.base);
      expect(kinds[2].type, ExploreKind.typeWeb);
      expect(await Storage.read(Baswebview.exploreKey(site.base)), contains('线路'));
      final page = FakeSourceEngine.created.single.page!;
      await SourceApi.exploreKinds(src);
      expect(page.calls.where((c) => c == 'getfinds()'), hasLength(1));

      final refreshed = <String>[];
      final sub = ExploreRefresh.stream.listen(refreshed.add);
      expect(await SourceApi.exploreAction(src, "applyFilter('线路')", key: '线路', value: '${site.base}/'), '');
      await Future<void>.delayed(Duration.zero);
      expect(await Cache(site.base).get('线路'), '${site.base}/');
      expect(await Cache(site.base).get('server'), '${site.base}/');
      expect(refreshed, [site.base]);
      expect(await Storage.read(Baswebview.exploreKey(site.base)), '');
      await sub.cancel();
      await Cache(site.base).set('server', site.base);
      final again = await SourceApi.exploreKinds(src);
      expect(again.first.defaultValue, '${site.base}/');
      expect(page.calls.where((c) => c == 'getfinds()'), hasLength(2));

      expect(await SourceApi.exploreAction(src, 'checkin()', key: '签到'), 'checked');
      final list = await SourceApi.explore(src, kinds[1].url!, page: 1);
      expect(list, hasLength(2));
      expect(await SourceApi.explore(src, kinds[1].url!, page: 2), isEmpty);
    });

    test('pay, imagedecrypt, help, login url, shouldOverrideUrlLoading', () async {
      final src = engineSource();
      final book = wb.Book(bookUrl: '${site.base}/book/1', origin: site.base)..tocUrl = 'x';
      final run = await TimeSourceApi.runOf(src);
      expect(await SourceApi.payAction(src, book, (await SourceApi.chapters(src, book..tocUrl = base64Encode(utf8.encode('{"id":"1"}'))))[1]),
          'paid:${site.base}/c/2');
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(await SourceApi.decodeImage(src, book, null, 'http://img', bytes), [3, 2, 1]);
      expect(await TimeSourceApi.help(src.toBaseSource()), '@html:<b>帮助</b>内容');
      expect(await TimeSourceApi.loginUrl(src.toBaseSource()), '${site.base}/login.html');
      expect(await run.shouldOverrideUrlLoading('${site.base}/book/2'), isFalse);
      expect(await run.shouldOverrideUrlLoading('${site.base}/other'), isTrue);
    });

    test('a page error answers "" and logs; a function that never answers times out', () async {
      final run = await SourceRun.of(BaseSource.fromJson(rawSource(html: '${fixture('time_source.html')}<script>async function hang(){}</script>')));
      final logs = <String>[];
      run.debugLog = logs.add;
      expect(await run.call('nothing()', const Duration(seconds: 5)), '');
      expect(logs.single, contains('ReferenceError'));
      expect(
        () => run.evalCall('hang()', const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>().having((e) => e.message, 'message', '等待函数执行超时')),
      );
    });

    test('a page that never calls CookieJar: 等待页面就绪超时', () async {
      SourceRun.readyTimeout = const Duration(milliseconds: 100);
      await expectLater(
        SourceApi.search(engineSource(html: '<html><script>async function search(){ return "[]"; }</script></html>'), 'x', useCache: false),
        throwsA(isA<TimeoutException>().having((e) => e.message, 'message', '等待页面就绪超时')),
      );
    });

    test('an html url is downloaded, kept, and the kept copy is used when the download fails', () async {
      final s = BaseSource.fromJson(rawSource(html: '${site.base}/page.html'));
      final logs = <String>[];
      final page = await SourceRun.loadPage(s, log: logs.add);
      expect(page.html, fixture('time_source.html').trim());
      expect(page.baseUrl, '${site.base}/page.html');
      expect(logs, ['获取html', '完成获取html']);
      site.pageStatus = 500;
      final cached = await SourceRun.loadPage(s, log: logs.add);
      expect(cached.html, page.html);
      expect(logs.last, startsWith('html 加载失败 使用缓存'));
      await Storage.delete(SourceRun.htmlCacheKey('${site.base}/page.html'));
      await expectLater(SourceRun.loadPage(s), throwsA(predicate((e) => '$e'.contains('获取在线书源失败'))));
      // the runner loads the fetched page under its own address
      site.pageStatus = 200;
      final books = await SourceApi.search(BookSource.fromJson(rawSource(html: '${site.base}/page.html')), '测试', useCache: false);
      expect(books, hasLength(2));
      expect(FakeSourceEngine.created.single.baseUrl, '${site.base}/page.html');
      // inline html pages without an http source url get a local address
      final local = await SourceRun.loadPage(const BaseSource(bookSourceUrl: 'mysource', html: '<p>'));
      expect(local.baseUrl, 'http://localhost/');
      await expectLater(SourceRun.loadPage(const BaseSource(bookSourceUrl: 'x', html: '@aes:abc')), throwsA(predicate((e) => '$e'.contains('解密失败'))));
    });

    test('the debugger runs search -> info -> toc -> content and keeps the page text output', () async {
      final lines = <String>[];
      final log = await SourceApi.debug(engineSource(), '测试', onLine: lines.add);
      expect(lines.any((l) => l.contains('︾开始解析搜索页')), isTrue);
      expect(lines.any((l) => l.contains('︽搜索页解析完成 2')), isTrue);
      expect(lines.any((l) => l.contains('︽目录页解析完成 2')), isTrue);
      expect(lines.last, contains('︽正文页解析完成'));
      expect(log.bodies['content'], contains('第一段内容'));
      expect(log.bodies['search'], contains('测试书'));
    });
  });

  group('handlers', () {
    late FakeSourceEngine e;
    const src = BaseSource(bookSourceUrl: 'https://src.test', bookSourceName: '源');
    setUp(() {
      e = FakeSourceEngine(const SourceJsEngineOptions());
      SourceHandlers.register(e, src, needhttp: true);
    });

    Future<Map> http(List<dynamic> a) async => (await e.callHandler('http', a)) as Map;

    test('the shared set is registered (0xe8af80)', () {
      expect(
        e.handlers.keys.toSet(),
        containsAll(<String>[
          'http', 'showvideoplay', 'getDirectoryList', 'getsourceurl', 'getWidth', 'getHeight', 'getsearch', 'showsvg', 'getsvg', 'addsvg',
          'refreshContent', 'getReadBook', 'searchbook', 'voice', 'addbook', 'toTraditional', 'toSimplified', 'buildNumber', 'version', 'id',
          'device', 'showToast', 'showLongToast', 'getWebViewUA', 'putLyric', 'cache.allget', 'cache.allset', 'cache.allremove', 'cache.get',
          'cache.set', 'cache.remove', 'cookie.get', 'cookie.getCookie', 'cookie.remove', 'cookie.set', 'cookie.setcookie', 'webview',
          'getdurChapterIndex', 'webviewajax', 'startBrowser', 'startBrowserWithShouldOverrideUrlLoading',
          'startBrowserDpWithShouldOverrideUrlLoading', 'startBrowserDp', 'startBrowserDpwithHtml', 'openurl', 'base64encode', 'base64decode',
          'getLoginUser', 'htmlToText', 'getVerificationCode', 'utf8ToGbkUrlEncoded',
        ]),
      );
      final plain = FakeSourceEngine(const SourceJsEngineOptions());
      SourceHandlers.register(plain, src);
      expect(plain.handlers.containsKey('http'), isFalse);
    });

    test('http: headers JSON, cookies sent and kept, POST content types, redirects, GBK text, errors', () async {
      CookieStore.setCookie(site.base, 'a=1');
      final me = await http(['get', '${site.base}/me', '', jsonEncode({'X-Test': 'yes'}), true, '']);
      expect(me['statusCode'], 200);
      expect(me['method'], 'get');
      expect((jsonDecode(me['data'] as String) as Map)['cookie'], 'a=1');
      expect(utf8.decode(base64Decode(me['body'] as String)), me['data']);
      expect((me['headers'] as Map)['content-type'], isNotEmpty);

      final form = await http(['post', '${site.base}/me', 'x=1', '{}', true, '']);
      expect((jsonDecode(form['data'] as String) as Map)['type'], startsWith('application/x-www-form-urlencoded'));
      final json = await http(['post', '${site.base}/me', '{"x":1}', '{}', true, 'application/json']);
      expect((jsonDecode(json['data'] as String) as Map)['type'], startsWith('application/json'));
      expect((jsonDecode(json['data'] as String) as Map)['body'], '{"x":1}');

      await http(['post', '${site.base}/login', 'user=me&pass=p', '{}', true, '']);
      expect(CookieStore.getKey(site.base, 'token'), 't-me');

      final followed = await http(['get', '${site.base}/redirect', '', '{}', true, '']);
      expect(followed['statusCode'], 200);
      final stopped = await http(['get', '${site.base}/redirect', '', '{}', false, '']);
      expect(stopped['statusCode'], 302);

      final gbkText = await http(['get', '${site.base}/c/1', '', '', true, '']);
      expect(gbkText['data'], contains('第一段内容'));

      final failed = await http(['get', 'http://127.0.0.1:1/x', '', '{}', true, '']);
      expect(failed['statusCode'], 0);
      expect(failed['statusMessage'], isNotEmpty);
      expect(failed['data'], '');
    });

    test('http without the cookie jar keeps no cookies; http2:// is sent as https', () async {
      await SourceHttp.request(method: 'post', url: '${site.base}/login', body: 'user=x', isCookieJar: false);
      expect(CookieStore.getKey(site.base, 'token'), '');
      expect(SourceHttp.normalizeUrl('http2://a.b/c'), 'https://a.b/c');
      expect(SourceHttp.normalizeUrl('https2://a.b/c'), 'https://a.b/c');
      expect(SourceHttp.headersOf('not json'), isEmpty);
      expect(SourceHttp.headersOf({'a': 1}), {'a': '1'});
    });

    test('cache.* per source and cache.all* shared; cookie.* on host names too', () async {
      await e.callHandler('cache.set', ['k', 'v']);
      expect(await e.callHandler('cache.get', ['k']), 'v');
      expect(await Cache('https://src.test').get('k'), 'v');
      expect(await Cache('https://other.test').get('k'), '');
      await e.callHandler('cache.set', ['obj', {'a': 1}]);
      expect(await e.callHandler('cache.get', ['obj']), '{"a":1}');
      await e.callHandler('cache.remove', ['k']);
      expect(await e.callHandler('cache.get', ['k']), '');
      await e.callHandler('cache.allset', ['g', '1']);
      expect(await Cache(Cache.all).get('g'), '1');
      expect(await e.callHandler('cache.allget', ['g']), '1');

      await e.callHandler('cookie.set', ['https://site.test/x', 'a=1;b=2']);
      expect(await e.callHandler('cookie.get', ['site.test']), 'a=1;b=2');
      expect(await e.callHandler('cookie.getCookie', ['site.test', 'b']), '2');
      expect(await e.callHandler('cookie.getCookie', ['site.test', 'zz']), isNull);
      await e.callHandler('cookie.setcookie', ['https://site.test', 'c', '3']);
      expect(CookieStore.getKey('https://site.test', 'c'), '3');
      await e.callHandler('cookie.remove', ['https://site.test']);
      expect(CookieStore.getCookie('https://site.test'), '');
    });

    test('conversions and app facts', () async {
      expect(await e.callHandler('base64encode', ['中文']), base64Encode(utf8.encode('中文')));
      expect(await e.callHandler('base64decode', [base64Encode(utf8.encode('中文'))]), '中文');
      expect(await e.callHandler('base64decode', ['%%%']), '');
      expect(await e.callHandler('utf8ToGbkUrlEncoded', ['中文a']), '%D6%D0%CE%C4%61');
      expect(await e.callHandler('toSimplified', ['書籍']), ChineseUtils.toSimplified('書籍'));
      expect(await e.callHandler('toTraditional', ['书籍']), ChineseUtils.toTraditional('书籍'));
      expect(await e.callHandler('htmlToText', ['<p>a</p><b>b</b>']), 'a\nb');
      expect(await e.callHandler('version'), '2.2.1026');
      expect(await e.callHandler('buildNumber'), '1026');
      Common.appid = 'device-1';
      expect(await e.callHandler('id'), 'device-1');
      expect(await e.callHandler('getsourceurl'), 'https://src.test');
      expect(await e.callHandler('getsearch'), -1);
      expect(await e.callHandler('getsvg'), isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await e.callHandler('device'), 'ios');
      debugDefaultTargetPlatformOverride = null;
      SourceRuntime.webViewUA = 'UA/1';
      expect(await e.callHandler('getWebViewUA'), 'UA/1');
    });

    test('browser, captcha, addbook and searchbook go to the UI hooks', () async {
      final opened = <SourceBrowserRequest>[];
      SourceUi.openBrowser = (r) async {
        opened.add(r);
        return '<html>done</html>';
      };
      expect(await e.callHandler('startBrowser', ['https://x/a', '标题', '{"User-Agent":"ua"}']), '<html>done</html>');
      await e.callHandler('startBrowserWithShouldOverrideUrlLoading', ['https://x/b', 't', '{}']);
      await e.callHandler('startBrowserDp', ['https://x/c', '段评']);
      await e.callHandler('startBrowserDpwithHtml', ['<p>h</p>', '段评']);
      expect([for (final r in opened) (r.url, r.overrideUrlLoading, r.half)], [
        ('https://x/a', false, false),
        ('https://x/b', true, false),
        ('https://x/c', false, true),
        ('https://src.test', false, true),
      ]);
      expect(opened.first.headers, {'User-Agent': 'ua'});
      expect(opened.first.source?.bookSourceUrl, 'https://src.test');
      expect(opened.last.html, '<p>h</p>');

      final captcha = <(String, Map<String, String>)>[];
      SourceUi.verificationCode = (u, h) async {
        captcha.add((u, h));
        return '1234';
      };
      expect(await e.callHandler('getVerificationCode', ['https://x/c.png', '{"a":"b"}']), '1234');
      expect(captcha.single.$1, 'https://x/c.png');
      expect(captcha.single.$2, {'a': 'b'});

      final books = <(String, String)>[];
      SourceUi.openBook = (s, b) async => books.add((s, b));
      await e.callHandler('addbook', ['https://x/book/1']);
      expect(books.single, ('https://src.test', 'https://x/book/1'));
      final searches = <(String, String)>[];
      SourceUi.searchBook = (s, k) async => searches.add((s, k));
      await e.callHandler('searchbook', ['关键词']);
      expect(searches.single, ('https://src.test', '关键词'));
      SourceUi.openUrl = (u, t) async => u == 'weixin://x' && t == 'text/plain';
      expect(await e.callHandler('openurl', ['weixin://x', 'text/plain']), isTrue);
    });

    test('webview: a background page answers its source, a js value or the matched override url', () async {
      expect(await e.callHandler('webview', ['https://w.test/', '', '<p>x</p>', '', '{}', '', '']), '<p>x</p>');
      expect(FakeSourceEngine.created.last.options.intercept, isTrue);
      expect(FakeSourceEngine.created.last.disposed, isTrue);
      expect(await e.callHandler('webview', ['https://w.test/book/9', '', '', '', '{"User-Agent":"ua2"}', r'book/\d+', '']), 'https://w.test/book/9');
      expect(FakeSourceEngine.created.last.options.userAgent, 'ua2');
      Webview.timeout = const Duration(milliseconds: 200);
      Webview.regexGrace = const Duration(milliseconds: 20);
      // no match: falls back to the page source
      expect(await e.callHandler('webview', ['https://w.test/a', '', '', '', '{}', '', r'\.m3u8']), contains('https://w.test/a'));
      Webview.timeout = const Duration(seconds: 60);
      Webview.regexGrace = const Duration(seconds: 5);
    });
  });

  group('BookSearchService and the reader loader', () {
    test('search, explore, detail, toc, content of a 时光源 through EngineBookSearchService', () async {
      await Sourcedata.load();
      await Sources.add(rawSource());
      expect(Sourcedata.exploreRaw.map((s) => s['bookSourceUrl']), contains(site.base));
      final svc = EngineBookSearchService();
      final source = Source.fromJson(Sourcedata.byUrl(site.base)!);
      final events = await svc.search('测试', sources: [source]).toList();
      expect(events, hasLength(1));
      final hit = events.single.first;
      expect((hit.name, hit.origin), ('测试书', site.base));

      final explores = await svc.exploreKinds(source);
      expect(explores.map((e) => e.type_), [ExploreKind.typeSelect, ExploreKind.typeUrl, ExploreKind.typeWeb, ExploreKind.typeText, ExploreKind.typeButton, ExploreKind.typeTitle]);
      expect(await svc.explore(source, explores[1].url, 1), hasLength(2));

      final detail = await svc.bookInfo(hit);
      expect(detail.intro, '@html:<p>简介1</p>');
      final chapters = await svc.chapters(detail);
      expect(chapters.map((c) => c.name), ['第一章', '🔒第二章']);
      expect(await svc.content(detail, chapters.first), contains('第二段 内容'));

      // change source finds the same book in the 时光源
      final candidates = await svc.changeSourceCandidates(m.Book(bookUrl: 'other', name: '测试书', author: '作者1', origin: 'x'), sources: [source]).toList();
      expect(candidates.expand((l) => l).map((b) => b.bookUrl), ['${site.base}/book/1']);

      // the reader: toc and chapter text through WebBookLoader
      final shelfBook = m.Book.fromJson(detail.toJson());
      final toc = await WebBookLoader.chapters(shelfBook);
      expect(toc, hasLength(2));
      final content = await WebBookLoader.loaderFor(shelfBook)(toc.first);
      expect(content.text, contains('第一段内容'));
      expect(content.blocks.length, greaterThanOrEqualTo(3)); // two paragraphs and the image
    });

    test('a 时光源 book variable lives in the source cache under the book url', () async {
      await Sourcedata.load();
      await Sources.add(rawSource());
      await Cache(site.base).set('${site.base}/book/1', '音色4');
      final run = await SourceRun.of(BaseSource.fromJson(rawSource()));
      // what the page reads with cache.getbookVariable(bookurl)
      expect(await FakeSourceEngine.created.single.callHandler('cache.get', ['${site.base}/book/1']), '音色4');
      expect(run.source.bookSourceUrl, site.base);
    });
  });
}
