import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/rss.dart';
import 'package:newread/models/article.dart';
import 'package:newread/pages/rss/debug.dart';
import 'package:newread/pages/rss/rss_articles.dart';
import 'package:newread/pages/rss/rss_history.dart';
import 'package:newread/pages/rss/rss_setting.dart';
import 'package:newread/pages/rss/rss_webview.dart';
import 'package:newread/pages/rss_page.dart';
import 'package:newread/pages/source/source_setting.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';
import 'package:newread/util/webbook/model/rss_source.dart';

import '../support/env.dart';
import '../util/fake_site.dart';
import 'support.dart';

/// A paged news list: /list (page 1, next -> /list2), /list2 (last page), `/a/<n>` article pages.
class PagedSite {
  final HttpServer server;
  PagedSite(this.server);
  String get base => 'http://127.0.0.1:${server.port}';

  static Future<PagedSite> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((req) {
      final p = req.uri.path;
      String body;
      if (p == '/list') {
        body = '<html><body><div class="item"><a href="/a/1">文章一</a></div><div class="item"><a href="/a/2">文章二</a></div>'
            '<a id="next" href="/list2">下一页</a></body></html>';
      } else if (p == '/list2') {
        body = '<html><body><div class="item"><a href="/a/3">文章三</a></div><div class="item"><a href="/a/1">文章一</a></div></body></html>';
      } else if (p.startsWith('/a/')) {
        body = '<html><body><div id="body"><p>正文${p.substring(3)}</p></div><div class="ad">广告</div></body></html>';
      } else {
        req.response.statusCode = 404;
        body = 'nf';
      }
      req.response.headers.contentType = ContentType.html;
      req.response.add(utf8.encode(body));
      req.response.close();
    });
    return PagedSite(s);
  }

  Map<String, dynamic> source() => {
        'sourceUrl': base,
        'sourceName': '分页站',
        'sortUrl': '全部::$base/list',
        'ruleArticles': 'class.item',
        'ruleTitle': 'tag.a@text',
        'ruleLink': 'tag.a@href',
        'ruleNextPage': 'id.next@href',
        'ruleContent': 'id.body@html',
      };
}

void main() {
  late TestDevice dev;
  late FakeSite site;
  late PagedSite paged;
  setUpAll(() async {
    site = await FakeSite.start();
    paged = await PagedSite.start();
  });
  tearDownAll(() async {
    await site.close();
    await paged.server.close(force: true);
  });
  setUp(() async => dev = await freshArea());
  tearDown(() => dev.delete());

  test('RssPager: rule paging follows the next url, drops duplicates and ends on the last page', () async {
    final pager = RssPager(paged.source());
    final sorts = await pager.sorts();
    expect(sorts, [('全部', '${paged.base}/list')]);
    final tab = RssTabState(sorts.first.$1, sorts.first.$2);
    await pager.next(tab);
    expect(tab.items.map((a) => a.title), ['文章一', '文章二']);
    expect(tab.items.first.link, '${paged.base}/a/1');
    expect((tab.page, tab.end, tab.nextUrl), (1, false, '${paged.base}/list2'));
    await pager.next(tab);
    expect(tab.items.map((a) => a.title), ['文章一', '文章二', '文章三']); // 文章一 again is not added twice
    expect(tab.end, isTrue);
    await pager.next(tab); // no more requests once ended
    expect(tab.page, 2);
  });

  test('RssPager: a plain feed (default parser, no sortUrl) gives one page', () async {
    final pager = RssPager({'sourceUrl': '${site.base}/rss', 'sourceName': 'Feed'});
    final sorts = await pager.sorts();
    expect(sorts.single.$2, '${site.base}/rss');
    final tab = RssTabState('', sorts.single.$2);
    await pager.next(tab);
    expect(tab.items.map((a) => a.title), ['First post', 'Second post']);
    expect(tab.end, isTrue);
    expect(tab.error, isNull);
  });

  test('history store keeps the newest first without duplicates', () async {
    await RssHistoryStore.add('https://h', Article(title: 'a', link: '1'));
    await RssHistoryStore.add('https://h', Article(title: 'b', link: '2'));
    await RssHistoryStore.add('https://h', Article(title: 'a2', link: '1'));
    expect((await RssHistoryStore.load('https://h')).map((a) => a.title), ['a2', 'b']);
    await RssHistoryStore.clear('https://h');
    expect(await RssHistoryStore.load('https://h'), isEmpty);
  });

  test('local RSS debug logs the list and the content step and keeps both page sources', () async {
    final out = await runRssDebug(RssSource.fromJson(paged.source()));
    final log = out.lines.join('\n');
    expect(log, contains('︽列表页解析完成 2'));
    expect(log, contains('≡标题:文章一'));
    expect(log, contains('正文1'));
    expect(log, contains('︽正文页解析完成'));
    expect(out.sources['列表源码'], contains('文章二'));
    expect(out.sources['正文源码'], contains('广告'));
    expect(rssContentHtml('<p>x</p>', style: 'p{}'), allOf(contains('<style>p{}</style>'), contains('<body><p>x</p></body>')));
  });

  testWidgets('订阅 tab: enabled sources only, search and group filter', (t) async {
    await t.runAsync(() async {
      await Rssdata.load();
      await RssSources.importJson(fixture('rss_sources.json'));
    });
    await t.pumpWidget(app(const RssPage()));
    await idle(t);
    expect(find.text('订阅'), findsOneWidget);
    expect(find.text('新闻站'), findsOneWidget);
    expect(find.text('单页'), findsOneWidget);
    expect(find.text('博客'), findsNothing); // disabled
    await t.enterText(find.byKey(const Key('rss_search')), '新闻');
    await t.pump();
    expect(find.text('单页'), findsNothing);
    await t.enterText(find.byKey(const Key('rss_search')), '');
    await t.pump();
    await t.tap(find.byKey(const Key('rss_group_menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('新闻').last);
    await t.pumpAndSettle();
    expect(find.text('新闻站'), findsOneWidget);
    expect(find.text('单页'), findsNothing);
  });

  testWidgets('article list: first page from the engine, layout switch persisted per source', (t) async {
    await t.pumpWidget(app(RssArticles(source: paged.source())));
    await idleUntil(t, () => find.text('文章二').evaluate().isNotEmpty);
    expect(find.text('文章一'), findsOneWidget);
    expect(find.text('分页站'), findsOneWidget);
    await act(t, () => t.tap(find.byKey(const Key('rss_articles_menu'))));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.text('切换布局')));
    await idle(t);
    expect(Storage.getInt('rsstype${paged.base}'), 1); // list -> card
    expect(find.text('文章一'), findsOneWidget);
    await t.pump(const Duration(seconds: 30)); // the HTTP client's idle timer
  });

  testWidgets('article page renders the extracted content with the source style', (t) async {
    final src = {...paged.source(), 'style': 'p{color:red}'};
    await t.pumpWidget(app(WebviewRssPage(source: src, article: Article(title: '文章一', link: '${paged.base}/a/1'))));
    await idleUntil(t, () => FakeWebController.created.isNotEmpty && FakeWebController.created.last.loads.isNotEmpty);
    final load = FakeWebController.created.last.loads.single;
    expect(load, startsWith('html:${paged.base}/a/1:'));
    expect(load, contains('正文1'));
    expect(load, contains('<style>p{color:red}</style>'));
    expect(load, isNot(contains('广告')));
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('the source\'s shouldOverrideUrlLoading keeps matching links out of the web view', (t) async {
    final src = {...paged.source(), 'shouldOverrideUrlLoading': 'url.indexOf("/book/") > -1 ? "true" : "false"'};
    await t.pumpWidget(app(WebviewRssPage(source: src, article: Article(title: '文章一', link: '${paged.base}/a/1'))));
    await idleUntil(t, () => FakeWebController.created.isNotEmpty && FakeWebController.created.last.loads.isNotEmpty);
    final web = FakeWebController.created.last;
    bool? blocked, passed;
    await t.runAsync(() async {
      blocked = await web.navigate('https://site.test/book/12');
      passed = await web.navigate('https://site.test/page/3');
    });
    expect(blocked, isFalse);
    expect(passed, isTrue);
    await t.pump(const Duration(seconds: 30));
  });

  testWidgets('RSS manager: import from a file through the preview', (t) async {
    SourceImport.pickFileText = () async => fixture('rss_sources.json');
    await t.runAsync(() => Rssdata.load());
    await t.pumpWidget(app(const RssSettingPage()));
    await idle(t);
    await act(t, () => t.tap(find.byKey(const Key('rss_setting_menu'))));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.text('本地导入')));
    await idleUntil(t, () => find.byKey(const Key('rss_import_ok')).evaluate().isNotEmpty);
    expect(find.text('新增'), findsNWidgets(3));
    await act(t, () => t.tap(find.byKey(const Key('rss_import_ok'))));
    await idleUntil(t, () => Toast.log.isNotEmpty);
    expect(Rssdata.raw.length, 3);
    expect(Toast.log, contains('轻悦时光新增3条订阅源，更新0条订阅源'));
    expect(Rssdata.byUrl('https://news.example.com')!['vendorExtra'], 'keep');
  });
}
