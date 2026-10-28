// 换源 page (pages/book/book_change_yuan.dart): 切换书源 with the tabs 匹配书籍 / 不同作者 / 相近名称 and 菜单 → 加载目录.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/source.dart';
import 'package:newread/pages/book/book_change_yuan.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';

import 'support.dart';

Book b(String url, String name, String author, String origin) => Book(bookUrl: url, name: name, author: author, origin: origin);

void main() {
  test('tabs: same book, same name by another author, similar names', () {
    final book = b('u', '斗破苍穹', '天蚕土豆', 'a');
    expect(changeSourceTab(book, b('x', '斗破苍穹', '天蚕土豆', 'b')), 0);
    expect(changeSourceTab(book, b('x', '斗破苍穹', '某人', 'b')), 1);
    expect(changeSourceTab(book, b('x', '斗破苍穹外传', '某人', 'b')), 2);
    expect(changeSourceTab(book, b('x', '诛仙', '萧鼎', 'b')), isNull);
    expect(changeSourceTab(b('u', '斗破苍穹', '', 'a'), b('x', '斗破苍穹', '某人', 'b')), 0);
  });

  testWidgets('切换书源: candidates per tab; 加载目录 loads every latest chapter again', (t) async {
    final book = b('http://src-a.test/1', '斗破苍穹', '天蚕土豆', 'http://src-a.test');
    final engine = FakeBookSearchService(
      library: {
        'http://src-a.test': [b('http://src-a.test/1', '斗破苍穹', '天蚕土豆', '')],
        'http://src-b.test': [b('http://src-b.test/1', '斗破苍穹', '天蚕土豆', ''), b('http://src-b.test/2', '斗破苍穹', '别人', '')],
        'http://src-c.test': [b('http://src-c.test/3', '斗破苍穹之前传', '某某', ''), b('http://src-c.test/4', '诛仙', '萧鼎', '')],
      },
      tocs: {'http://src-b.test/1': chapters(3)},
    );
    final sources = [for (final u in engine.library.keys) Source.fromJson({'bookSourceUrl': u, 'bookSourceName': u})];
    final env = await pumpPage(t, BookChangeYuan(book: book, sources: sources), engine: engine);
    addTearDown(env.dispose);
    await settleUntil(t, () => find.text('最新：第3章').evaluate().isNotEmpty && find.byKey(const Key('change_retry')).evaluate().isNotEmpty);

    expect(find.text('切换书源'), findsOneWidget);
    expect(engine.calls.first, 'search:斗破苍穹');
    expect(find.byKey(const Key('cand_http://src-a.test/1')), findsOneWidget);
    expect(find.byKey(const Key('cand_http://src-b.test/1')), findsOneWidget);
    expect(find.byKey(const Key('cand_http://src-b.test/2')), findsNothing);
    expect(find.text('最新：第3章'), findsOneWidget);

    await t.tap(find.byKey(const Key('change_tab_1')));
    await t.pump();
    expect(find.byKey(const Key('cand_http://src-b.test/2')), findsOneWidget);
    expect(find.byKey(const Key('cand_http://src-b.test/1')), findsNothing);

    await t.tap(find.byKey(const Key('change_tab_2')));
    await t.pump();
    expect(find.byKey(const Key('cand_http://src-c.test/3')), findsOneWidget);
    expect(find.byKey(const Key('cand_http://src-c.test/4')), findsNothing);

    await t.tap(find.byKey(const Key('change_tab_0')));
    await t.pump();
    final tocs = engine.calls.where((c) => c.startsWith('toc:')).length;
    await t.tap(find.byKey(const Key('change_menu')));
    await settle(t);
    await t.tap(find.text('加载目录'));
    // every candidate of every tab (a/1, b/1, b/2, c/3) is asked again
    await settleUntil(t, () => engine.calls.where((c) => c.startsWith('toc:')).length >= tocs + 4);
    expect(engine.calls.where((c) => c.startsWith('toc:')).length, tocs + 4);
  });
}
