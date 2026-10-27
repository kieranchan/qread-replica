// Detail → catalog → reader navigation with the fake engine (no shelf writes from the UI).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/book/book_detail_page.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';
import 'package:newread/read/api/book_content.dart';

import 'support.dart';

void main() {
  testWidgets('detail loads info and toc; the catalog marks cached chapters and opens the reader at a chapter', (t) async {
    final book = Book(bookUrl: 'http://src-a.test/book/7', name: '雪中悍刀行', author: '烽火戏诸侯', origin: 'http://src-a.test');
    final engine = FakeBookSearchService(
      library: {
        'http://src-a.test': [Book(bookUrl: book.bookUrl, name: book.name, author: book.author, intro: '江湖是一张珠帘。', kind: '武侠,完本')],
      },
      tocs: {book.bookUrl: chapters(8)},
    );
    final env = await pumpPage(t, BookDetailPage(book: book), engine: engine);
    addTearDown(env.dispose);
    await t.runAsync(() => const BookContent().saveToLocal(book.bookUrl, 2, '第三章的正文'));

    expect(find.text('雪中悍刀行'), findsWidgets);
    expect(find.text('江湖是一张珠帘。'), findsOneWidget);
    expect(find.text('武侠'), findsOneWidget);
    expect(find.text('共 8 章'), findsOneWidget);
    expect(engine.calls, ['info:${book.bookUrl}', 'toc:${book.bookUrl}']);

    await t.tap(find.byKey(const Key('detail_toc')));
    await settle(t);
    expect(find.byKey(const Key('catalog_count')), findsOneWidget);
    expect(find.byKey(const Key('cached_2')), findsOneWidget);
    expect(find.byKey(const Key('cached_1')), findsNothing);

    await t.tap(find.byKey(const Key('catalog_order')));
    await t.pump();
    expect(find.text('倒序'), findsOneWidget);

    await t.tap(find.byKey(const Key('chapter_3')));
    await t.pump();
    expect(env.reader.single.chapterIndex, 3);
    expect(env.reader.single.book.bookUrl, book.bookUrl);

    await t.enterText(find.byKey(const Key('catalog_search')), '第8');
    await t.pump();
    expect(find.byKey(const Key('chapter_7')), findsOneWidget);
    expect(find.byKey(const Key('chapter_3')), findsNothing);
  });

  testWidgets('detail 阅读 opens the reader with the loaded chapters', (t) async {
    final book = Book(bookUrl: 'u1', name: '书', author: '人', origin: 'o');
    final engine = FakeBookSearchService(tocs: {'u1': chapters(3)});
    final env = await pumpPage(t, BookDetailPage(book: book), engine: engine);
    addTearDown(env.dispose);
    await t.tap(find.byKey(const Key('detail_read')));
    await t.pump();
    expect(env.reader.single.book.bookUrl, 'u1');
    expect(env.reader.single.chapterIndex, isNull);
  });
}
