// Own file: the batch delete writes the shelf from the UI (see support.dart, pumpPage).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/pages/bookshelf_page.dart';

import 'support.dart';

void main() {
  testWidgets('edit mode: 全选 then 删除 removes the selected books', (t) async {
    final env = await pumpPage(t, const BookshelfPage(), books: fixtureBooks().take(2).toList());
    addTearDown(env.dispose);
    await t.tap(find.byKey(const Key('shelf_more')));
    await t.pumpAndSettle();
    await t.tap(find.text('编辑书架'));
    await t.pumpAndSettle();
    expect(find.text('全选 (0/2)'), findsOneWidget);
    await t.tap(find.byKey(const Key('sel_all')));
    await t.pump();
    expect(find.text('全选 (2/2)'), findsOneWidget);
    await t.tap(find.byKey(const Key('sel_invert')));
    await t.pump();
    expect(find.text('全选 (0/2)'), findsOneWidget);
    await t.tap(find.byKey(const Key('sel_all')));
    await t.pump();
    await t.tap(find.byKey(const Key('sel_delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('del_ok')));
    await settle(t);
    expect(BookSelfN.books, isEmpty);
    expect(find.text('书架还是空的'), findsOneWidget);
  });
}
