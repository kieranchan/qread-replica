// Own file: the import writes the shelf from the UI (see support.dart, pumpPage).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/pages/bookshelf_page.dart';
import 'package:newread/util/toast.dart';
import 'package:newread/widget/book_page.dart';

import 'support.dart';

void main() {
  testWidgets('local import: 添加书籍 → 本地导入 adds the TXT with its chapters', (t) async {
    final env = await pumpPage(t, const BookshelfPage());
    addTearDown(env.dispose);
    await t.runAsync(() async {
      final f = File('${env.dir.path}/《山居笔记》作者：林间.txt');
      await File('test/fixtures/shelf/sample.txt').copy(f.path);
      env.picker.books = [f];
    });
    await t.tap(find.byKey(const Key('shelf_more')));
    await t.pumpAndSettle();
    await t.tap(find.text('添加书籍'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add_local')));
    await settle(t, rounds: 60);
    expect(BookSelfN.books, hasLength(1));
    final b = BookSelfN.books.single;
    expect(b.name, '山居笔记');
    expect(b.author, '林间');
    expect(b.totalChapterNum, 3);
    expect(b.latestChapterTitle, '第三章 夜雨');
    expect(isLocalShelfBook(b), isTrue);
    expect(find.text('山居笔记'), findsWidgets);
    expect(Toast.log, contains('导入成功'));
  });
}
