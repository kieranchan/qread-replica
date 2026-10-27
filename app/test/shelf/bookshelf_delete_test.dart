// Own file: deleting writes the shelf from the UI (see support.dart, pumpPage).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/pages/bookshelf_page.dart';
import 'package:newread/read/api/book_content.dart';

import 'support.dart';

void main() {
  testWidgets('long press → 删除书籍 removes the book; with the cache option its chapter cache goes too', (t) async {
    final env = await pumpPage(t, const BookshelfPage(), books: fixtureBooks().take(2).toList());
    addTearDown(env.dispose);
    const url = 'http://src-a.test/book/1';
    await t.runAsync(() => const BookContent().saveToLocal(url, 0, '正文'));
    expect(const BookContent().existsSync(url, 0), isTrue);

    await t.longPress(find.byKey(const Key('book_$url')));
    await t.pumpAndSettle();
    expect(find.text('作者: 天蚕土豆'), findsOneWidget);
    expect(find.text('分组: 全部'), findsOneWidget);
    expect(find.byKey(const Key('op_更换书源')), findsOneWidget);
    await t.tap(find.byKey(const Key('op_删除书籍')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('del_with_cache')));
    await t.pump();
    await t.tap(find.byKey(const Key('del_ok')));
    await settle(t);
    expect(BookSelfN.contains(url), isFalse);
    expect(BookSelfN.contains('http://src-a.test/book/2'), isTrue);
    expect(find.text('斗破苍穹'), findsNothing);
    expect(const BookContent().existsSync(url, 0), isFalse);
  });
}
