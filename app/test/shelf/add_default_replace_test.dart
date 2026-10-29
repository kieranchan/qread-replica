// 加入书架 → the new shelf book takes the 阅读设置 default 替换净化 (`useReplaceRule`, 0x5abd64 reads the global preference 0x53d688);
// a book that already had its own switch on keeps it. Before this, every added book started with 替换净化 off whatever the setting said.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/app_dirs.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/models/book.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/widget/book_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends BookApiPage<_Host> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qread_add_default_');
    SharedPreferences.setMockInitialValues({});
    await Storage.init(prefs: await SharedPreferences.getInstance(), root: tmp);
    AppDirs.root = tmp;
    ReadStorageRoot.dir = tmp;
    await BookSelfN.load();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  // bounded pumping: the 操作成功 toast keeps animating, so pumpAndSettle would never return
  Future<void> pumps(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<Book?> add(WidgetTester tester, Book book) async {
    final f = tester.state<_HostState>(find.byType(_Host)).addToShelf(book);
    await pumps(tester, 5);
    await tester.tap(find.byKey(const Key('add_ok')));
    await pumps(tester);
    return f;
  }

  Book web(String id) => Book(bookUrl: 'https://example.com/$id', name: '书$id', author: 'A', origin: 'https://example.com');

  testWidgets('a book added to the shelf follows the 替换净化 default; its own switch wins when already on', (tester) async {
    // runAsync: the shelf is written to a real file, which never completes under the test's fake clock
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: _Host()));

      expect((await add(tester, web('a')))!.useReplaceRule, isFalse, reason: 'setting never touched: off, like the original');

      await Storage.setBool('useReplaceRule', true);
      expect((await add(tester, web('b')))!.useReplaceRule, isTrue);

      await Storage.setBool('useReplaceRule', false);
      expect((await add(tester, web('c')))!.useReplaceRule, isFalse);
      expect((await add(tester, web('d')..useReplaceRule = true))!.useReplaceRule, isTrue, reason: 'a copy with the switch on keeps it');

      expect(Bookdata.books.where((b) => b.useReplaceRule).map((b) => b.name), unorderedEquals(['书b', '书d']));
    });
  });
}
