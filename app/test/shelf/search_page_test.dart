// Own file: the search page writes the history from the UI (see support.dart, pumpPage).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';
import 'package:newread/pages/search/search.dart';
import 'package:newread/pages/search/search_book_page.dart';
import 'package:newread/storage/storage.dart';

import 'support.dart';

Book b(String url, String name, String author, {String words = ''}) => Book(bookUrl: url, name: name, author: author, wordCount: words);

void main() {
  test('Search merges results by name + author and splits contains / exact', () async {
    final engine = FakeBookSearchService(library: {
      'a': [b('a1', '斗破苍穹', '天蚕土豆'), b('a2', '斗破苍穹外传', '某人')],
      'b': [b('b1', '斗破苍穹', '天蚕土豆'), b('b3', '诛仙', '萧鼎')],
    });
    final s = Search('斗破苍穹', service: engine)..start();
    await s.finished;
    expect(s.done, 2);
    expect(s.hits.map((h) => h.book.name), ['斗破苍穹', '斗破苍穹外传']);
    expect(s.hits.first.origins.map((x) => x.bookUrl), ['a1', 'b1']);
    expect(s.contains, hasLength(2));
    expect(s.exact.single.book.name, '斗破苍穹');
    expect(wordCountValue('12.5万字'), 125000);
    expect(wordCountValue('3千字'), 3000);
  });

  testWidgets('search page: progress, contains / exact tabs, history and opening a result', (t) async {
    final engine = FakeBookSearchService(library: {
      'http://src-a.test': [b('a1', '斗破苍穹', '天蚕土豆', words: '100万字'), b('a2', '斗破苍穹外传', '某人', words: '300万字')],
      'http://src-b.test': [b('b1', '斗破苍穹', '天蚕土豆'), b('b3', '诛仙', '萧鼎')],
    });
    late ShelfEnv env;
    await t.runAsync(() async {
      env = await shelfEnv(engine: engine);
      await Sources.addAll([
        {'bookSourceUrl': 'http://src-a.test', 'bookSourceName': '源A'},
        {'bookSourceUrl': 'http://src-b.test', 'bookSourceName': '源B'},
      ]);
    });
    addTearDown(env.dispose);
    await t.pumpWidget(app(const SearchBookPage(searchKey: '斗破苍穹')));
    await settle(t);

    expect(engine.calls, ['search:斗破苍穹']);
    expect(find.text('已搜索 2/2'), findsOneWidget);
    expect(find.byKey(const Key('book_a1')), findsOneWidget); // merged with b1
    expect(find.byKey(const Key('book_b1')), findsNothing);
    expect(find.byKey(const Key('book_a2')), findsOneWidget);
    expect(find.text('来源：源A'), findsWidgets);

    await t.tap(find.text('精确匹配'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('book_a1')), findsOneWidget);
    expect(find.byKey(const Key('book_a2')), findsNothing);

    // read the file directly: Storage.read would wait on the lock tail of the fake zone (see support.dart)
    expect(File(Storage.itemPath(SearchPrefs.historyKey)).readAsStringSync(), contains('斗破苍穹'));

    await t.tap(find.byKey(const Key('book_a1')));
    await settle(t);
    expect(find.byKey(const Key('detail_name')), findsOneWidget);
    expect(engine.calls, contains('info:a1'));
  });
}
