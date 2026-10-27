import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/bookshelf_page.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/widget/book/shelf_prefs.dart';
import 'package:newread/widget/book_page.dart';

import 'support.dart';

// UI-triggered shelf writes are in bookshelf_import_test / bookshelf_delete_test / bookshelf_batch_test (see support.dart).
void main() {
  late ShelfEnv env;

  tearDown(() => env.dispose());

  Future<void> start(WidgetTester t, {List<Book>? books, FakeBookSearchService? engine}) async {
    env = await pumpPage(t, const BookshelfPage(), books: books, engine: engine);
  }

  testWidgets('empty shelf shows the original empty-state text', (t) async {
    await start(t);
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(find.text('点击右上角导入书籍后开始阅读吧  :)'), findsOneWidget);
  });

  testWidgets('grid and list layouts; the toggle is stored in `listtype`', (t) async {
    await start(t, books: fixtureBooks().take(2).toList());
    expect(find.text('斗破苍穹'), findsWidgets);
    expect(find.text('斗罗大陆'), findsWidgets);
    expect(find.textContaining('最新：'), findsNothing); // grid
    // unread badge: 1623 chapters, read up to index 10
    expect(find.text('99+'), findsOneWidget);

    await t.tap(find.byKey(const Key('shelf_layout')));
    await settle(t);
    expect(find.text('最新：第一千六百二十三章 结束'), findsOneWidget);
    expect(find.text('天蚕土豆 • 共1623章'), findsOneWidget);
    expect(Storage.getString(ShelfPrefs.listtypeKey), '0');
  });

  testWidgets('tapping a book opens the reader through Nav.openReader', (t) async {
    await start(t, books: fixtureBooks().take(1).toList());
    await t.tap(find.byKey(const Key('book_http://src-a.test/book/1')));
    await t.pump();
    expect(env.reader.single.book.bookUrl, 'http://src-a.test/book/1');
  });

  testWidgets('group tabs filter the books (user group and built-in 未分组)', (t) async {
    await t.runAsync(() async {
      env = await shelfEnv();
      await BookSelfN.addAll(fixtureBooks().take(2));
      await Groupdata.add('武侠');
      await Groupdata.add('未分组');
    });
    await t.pumpWidget(app(const BookshelfPage()));
    await settle(t);
    expect(find.byKey(const Key('group_武侠')), findsOneWidget);
    await t.tap(find.byKey(const Key('group_武侠')));
    await settle(t);
    expect(find.text('斗罗大陆'), findsWidgets);
    expect(find.text('斗破苍穹'), findsNothing);
    expect(Storage.getString(ShelfPrefs.groupKey), '武侠');

    await t.tap(find.byKey(const Key('group_未分组')));
    await settle(t);
    expect(find.text('斗破苍穹'), findsWidgets);
    expect(find.text('斗罗大陆'), findsNothing);
  });

  testWidgets('pull-to-refresh checks updates through the engine and marks new chapters', (t) async {
    final engine = FakeBookSearchService(tocs: {
      'http://src-a.test/book/2': chapters(5),
    });
    await start(t, books: fixtureBooks().take(2).toList(), engine: engine);
    await t.runAsync(() => BookSelfN.setUpdate('http://src-a.test/book/1', true)); // updates off for book 1
    final state = t.state<BookshelfPageState>(find.byType(BookshelfPage));
    await t.runAsync(() => state.refreshBooks());
    await settle(t);
    expect(engine.calls, ['toc:http://src-a.test/book/2']);
    final b = BookSelfN.get('http://src-a.test/book/2')!;
    expect(b.latestChapterTitle, '第5章');
    expect(b.totalChapterNum, 5);
    expect(b.isredupdate, isTrue);
  });

  test('built-in groups filter by rule', () {
    final local = Book(bookUrl: 'books/a.txt', origin: 'loc_book');
    final comic = Book(bookUrl: 'x', type_: 2, bookgroup: '武侠');
    expect(ShelfGroups.matches(local, '本地书'), isTrue);
    expect(ShelfGroups.matches(comic, '本地书'), isFalse);
    expect(ShelfGroups.matches(comic, '漫画'), isTrue);
    expect(ShelfGroups.matches(comic, '未分组'), isFalse);
    expect(ShelfGroups.matches(local, '未分组'), isTrue);
    expect(ShelfGroups.matches(comic, '武侠'), isTrue);
    expect(bookTypeLabel(4), '短剧');
  });
}
