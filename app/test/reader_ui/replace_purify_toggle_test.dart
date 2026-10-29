// 更多 → 替换净化 in the reader (TopMenuActions.replacePurify, 0x10e866c): the per-book switch is written to the shelf, so it survives a
// relaunch. Seen on the phone: switched on for a book, gone after the next start — only the in-memory Book had been flipped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/read/pages/novel/views/reader_host.dart';
import 'package:newread/pages/read/pages/novel/views/top_menu.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

class _Host implements ReaderHost {
  _Host(this.book);
  @override
  final Book book;
  int reloads = 0;
  @override
  Future<void> reloadChapter({bool refresh = false}) async => reloads++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ctx extends Fake implements BuildContext {}

void main() {
  setUp(() async {
    await newDevice();
    Toast.log.clear();
    Toast.sink = (_, _) {};
  });

  test('toggling 替换净化 in the reader is kept on the shelf', () async {
    final stored = await BookSelfN.add(Book(bookUrl: 'https://example.com/t', name: '替换书', author: 'A', origin: 'https://example.com'));
    expect(stored.useReplaceRule, isFalse);
    final host = _Host(stored);

    await TopMenuActions.replacePurify(_Ctx(), host);
    expect(host.book.useReplaceRule, isTrue);
    expect(host.reloads, 1);
    expect(Toast.log.last, '已开启替换净化');
    await BookSelfN.load();
    expect(Bookdata.books.singleWhere((b) => b.bookUrl == stored.bookUrl).useReplaceRule, isTrue, reason: 'persisted, not only in memory');

    await TopMenuActions.replacePurify(_Ctx(), host);
    expect(Toast.log.last, '已关闭替换净化');
    await BookSelfN.load();
    expect(Bookdata.books.singleWhere((b) => b.bookUrl == stored.bookUrl).useReplaceRule, isFalse);
  });
}
