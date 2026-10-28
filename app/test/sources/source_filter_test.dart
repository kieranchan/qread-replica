// 筛选 of 时光源 (pages/search/source_filter.dart): `filter()` for a single-source search (env `searchone`, 搜索分类 opens the page)
// and `findfilter(url)` for a discovery list (a filter button); the page opens in the source browser and the search / list runs
// again afterwards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/source.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';
import 'package:newread/pages/search/search_book_page.dart';
import 'package:newread/pages/search/search_page.dart';
import 'package:newread/pages/search/source_filter.dart';
import 'package:newread/util/source/baswebview.dart';
import 'package:newread/util/source/inapp_engine.dart';
import 'package:newread/util/source/js_engine.dart';
import 'package:newread/util/source/run.dart';
import 'package:newread/util/source/source.dart';
import 'package:newread/util/source/time_source_api.dart';
import 'package:newread/util/webbook/model/book_source.dart';

import '../shelf/support.dart' as shelf;
import '../support/env.dart';
import 'support.dart';
import 'time_source_support.dart';

const String url = 'https://ft.test';

Map<String, dynamic> raw() => {'bookSourceUrl': url, 'bookSourceName': '筛选源', 'html': fixture('time_source.html'), 'enabled': true};

void fakes() {
  FakeSourceEngine.created.clear();
  SourceJsEngine.create = FakeSourceEngine.new;
  WebCookies.push = (_) async {};
  WebCookies.pull = (_) async {};
  WebCookies.pullAll = () async {};
  SourceUi.resetForTests();
}

void main() {
  group('runtime', () {
    late TestDevice dev;
    setUp(() async {
      dev = await freshArea();
      fakes();
      await Sourcedata.load();
      await Sources.add(raw());
    });
    tearDown(() async {
      await SourceRun.clear();
      dev.delete();
    });

    test('filter() / findfilter(url) answers; which answers are pages; data: html', () async {
      final s = BookSource.fromJson(raw());
      expect(await TimeSourceApi.filter(s), '$url/filter.html');
      expect(await TimeSourceApi.findFilter(s, '$url/find?c=male&page={{page}}'), startsWith('data:text/html;base64,'));
      expect(await TimeSourceApi.findFilter(s, '$url/find?c=female'), '');
      expect(TimeSourceApi.isFilterPage('https://x'), isTrue);
      expect(TimeSourceApi.isFilterPage('data:text/html,<b>x</b>'), isTrue);
      expect(TimeSourceApi.isFilterPage(' https://x'), isFalse);
      expect(TimeSourceApi.isFilterPage('选项'), isFalse);
      expect(SourceFilter.dataHtml('data:text/html;base64,PGI+562b6YCJPC9iPg=='), '<b>筛选</b>');
      expect(SourceFilter.dataHtml('data:text/html,%3Cb%3Ex%3C%2Fb%3E'), '<b>x</b>');
      expect(SourceFilter.dataHtml('https://x'), isNull);
      // Legado sources have none
      expect(await SourceFilter.searchFilter(Source.fromJson({'bookSourceUrl': 'https://l.test', 'searchUrl': '/s'})), '');
    });

    test('a single-source search reaches the page as search(key, page, "searchone")', () async {
      final s = BookSource.fromJson(raw());
      await SourceApi.searchAll([s], '测试', env: 'searchone', onlyEnabled: false).toList();
      final calls = FakeSourceEngine.created.single.page!.calls;
      expect(calls.single, 'search("测试",1,"searchone")');
    });
  });

  Future<shelf.ShelfEnv> start(WidgetTester t, FakeBookSearchService engine) async {
    late shelf.ShelfEnv env;
    await t.runAsync(() async {
      env = await shelf.shelfEnv(engine: engine);
      fakes();
      await Sourcedata.load();
      await Sources.add(raw());
      // the runner starts outside the test zone (its idle sweeper is a real timer)
      await (await SourceRun.of(BaseSource.fromJson(raw()))).waitReady();
    });
    return env;
  }

  testWidgets('discovery list: a findfilter page adds the filter button; the list reloads after the page', (t) async {
    final engine = FakeBookSearchService(pages: {
      '$url|$url/find?c=male&page={{page}}': [
        [Book(bookUrl: '$url/b/1', name: '男频书', origin: url)],
      ],
    });
    final env = await start(t, engine);
    addTearDown(env.dispose);
    final opened = <SourceBrowserRequest>[];
    SourceUi.openBrowser = (r) async {
      opened.add(r);
      return '';
    };
    await t.pumpWidget(shelf.app(SearchPage(source: Source.fromJson(raw()), url: '$url/find?c=male&page={{page}}', title: '男频')));
    await shelf.settleUntil(t, () => find.byKey(const Key('found_filter')).evaluate().isNotEmpty && find.text('男频书').evaluate().isNotEmpty);
    expect(find.byKey(const Key('found_filter')), findsOneWidget);
    final before = engine.calls.where((c) => c.startsWith('explore')).length;

    await t.tap(find.byKey(const Key('found_filter')));
    await shelf.settleUntil(t, () => engine.calls.where((c) => c.startsWith('explore')).length > before);
    expect(opened.single.html, '<b>筛选</b>');
    expect(opened.single.url, url);
    expect(opened.single.source?.bookSourceUrl, url);
    expect(engine.calls.where((c) => c.startsWith('explore')).length, before + 1);
    await t.runAsync(SourceRun.clear);
  });

  testWidgets('search: one 时光源 searches with searchone; 搜索分类 opens its filter page and searches again', (t) async {
    final engine = FakeBookSearchService(library: {
      url: [Book(bookUrl: '$url/b/1', name: '测试书', origin: url)],
    });
    final env = await start(t, engine);
    addTearDown(env.dispose);
    final opened = <SourceBrowserRequest>[];
    SourceUi.openBrowser = (r) async {
      opened.add(r);
      return '';
    };
    await t.pumpWidget(shelf.app(SearchBookPage(searchKey: '测试', sources: [Source.fromJson(raw())])));
    await shelf.settleUntil(t, () => engine.calls.contains('search:测试:searchone'));
    expect(engine.calls, ['search:测试:searchone']);

    await t.tap(find.byKey(const Key('search_category')));
    await shelf.settleUntil(t, () => engine.calls.length >= 2);
    expect(opened.single.url, '$url/filter.html');
    expect(opened.single.source?.bookSourceUrl, url);
    expect(engine.calls, ['search:测试:searchone', 'search:测试:searchone']);
    expect(find.text('选择搜索分类'), findsNothing);
    await t.runAsync(SourceRun.clear);
  });
}
