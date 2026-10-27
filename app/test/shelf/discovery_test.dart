// Discovery: explore kinds as tags, paging of the found list (FoundPager and the new discovery page).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/explore.dart';
import 'package:newread/models/source.dart';
import 'package:newread/pages/discovery_page_new.dart';
import 'package:newread/pages/search/book_search_service.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';
import 'package:newread/pages/search/search_page.dart';

import 'support.dart';

const src = 'http://src-a.test';

List<Book> page(String tag, int n, {int count = 20}) =>
    [for (var i = 0; i < count; i++) Book(bookUrl: '$src/$tag/$n/$i', name: '$tag第$n页$i', author: '作者$i')];

FakeBookSearchService engine() => FakeBookSearchService(
      kinds: {
        src: [Explore(title: '热门', url: '/hot'), Explore(title: '完结', url: '/end'), Explore(title: '分类', type_: 1, action: 'x')],
      },
      pages: {
        '$src|/hot': [page('热', 1), page('热', 2), page('热', 2)], // page 3 repeats page 2
        '$src|/end': [page('完', 1, count: 2)],
      },
    );

void main() {
  test('FoundPager pages until an empty or repeated page', () async {
    final e = engine();
    BookSearchService.instance = e;
    final p = FoundPager(Source(bookSourceUrl: src), '/hot');
    expect(await p.next(), isTrue);
    expect(await p.next(), isTrue);
    expect(p.books, hasLength(40));
    expect(await p.next(), isFalse); // same as page 2
    expect(p.hasMore, isFalse);
    expect(await p.next(), isFalse);
    expect(e.calls, ['explore:/hot:1', 'explore:/hot:2', 'explore:/hot:3']);

    final q = FoundPager(Source(bookSourceUrl: src), '/end');
    await q.next();
    expect(await q.next(), isFalse); // empty page 2
    expect(q.books, hasLength(2));
  });

  testWidgets('new discovery page: tags of the source, first page, scrolling loads the next page, switching tags', (t) async {
    final e = engine();
    late ShelfEnv env;
    await t.runAsync(() async {
      env = await shelfEnv(engine: e);
      await Sources.add({'bookSourceUrl': src, 'bookSourceName': '源A', 'exploreUrl': '热门::/hot', 'enabledExplore': true});
    });
    addTearDown(env.dispose);
    await t.pumpWidget(app(const DiscoveryPageNew()));
    await settle(t);

    expect(find.text('源A'), findsOneWidget);
    expect(find.byKey(const Key('kind_0')), findsOneWidget);
    expect(find.byKey(const Key('kind_1')), findsOneWidget);
    expect(e.calls, ['kinds:$src', 'explore:/hot:1']);
    expect(find.byKey(const Key('book_$src/热/1/0')), findsOneWidget);

    await t.fling(find.byKey(const Key('found_list_0')), const Offset(0, -3000), 3000);
    await settle(t);
    expect(e.calls, contains('explore:/hot:2'));

    await t.tap(find.byKey(const Key('kind_1')));
    await settle(t);
    expect(find.byKey(const Key('book_$src/完/1/0')), findsOneWidget);
    expect(e.calls.last, 'explore:/end:1');
  });

  testWidgets('new discovery page without explore sources shows the original hint', (t) async {
    final env = await pumpPage(t, const DiscoveryPageNew());
    addTearDown(env.dispose);
    expect(find.text('还没有添加书源'), findsOneWidget);
    expect(find.text('请先前往书源管理中添加书源并启用发现'), findsOneWidget);
  });
}
