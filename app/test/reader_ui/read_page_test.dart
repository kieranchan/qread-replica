// ReadPage on a local TXT book: pagination, page turns (tap zones, keys, drag), chapter crossing, menus, font size -> page count,
// bookmarks, catalog, long-press selection, progress save/restore; unsupported types.
//
// The reader scenario is one test on purpose: the data stores keep static per-key locks, and a lock first used inside one test's
// fake-async zone cannot be used by a later test of the same file (see support.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/note_data_n.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/read/read_page.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/setting/read_setting.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';

import 'support.dart';

void main() {
  testWidgets('reader on a local TXT book', (tester) async {
    phoneSize(tester);
    final f = (await tester.runAsync(setUpReader))!;
    expect(f.chapters.map((c) => c.name).take(3), ['第一章 开端', '第二章 山雨', '第三章 归来']);
    var s = await openReader(tester, f.book);
    expect(s.chapterIndex, 0);
    expect(s.pageIndex, 0);
    expect(s.pageCount, greaterThan(1));
    expect(find.textContaining('第一章 开端'), findsWidgets);

    // --- tap zones: right third = next, left third = previous; progress saved on every turn
    await tester.tapAt(const Offset(380, 400));
    await settle(tester, until: () => s.pageIndex == 1);
    await settle(tester, until: () => f.book.durChapterPos > 0);
    expect(f.book.durChapterIndex, 0);
    await tester.tapAt(const Offset(20, 400));
    await settle(tester, until: () => s.pageIndex == 0);
    await tester.tapAt(const Offset(20, 400));
    await settle(tester, max: 5);
    expect(Toast.log, contains('已经到头了'));

    // --- volume / arrow keys
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await settle(tester, until: () => s.pageIndex == 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester, until: () => s.pageIndex == 0);

    // --- drag left (cover animation)
    await tester.dragFrom(const Offset(300, 400), const Offset(-200, 0));
    await settle(tester, until: () => s.pageIndex == 1);

    // --- last page of chapter 1, one more turn opens chapter 2 at its first page
    unawaited(s.jumpToChapter(0, last: true));
    await settle(tester, until: () => s.pageIndex == s.pageCount - 1);
    await settle(tester, max: 10); // the next chapter is preloaded
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester, until: () => s.chapterIndex == 1);
    expect(s.pageIndex, 0);
    await settle(tester, until: () => f.book.durChapterIndex == 1);

    // --- bookmark toggle (NoteDataN, `bm_` ids)
    unawaited(s.toggleBookmark());
    await settle(tester, until: () => s.isBookmarked && Toast.log.contains('已添加书签'));
    final marks = NoteDataN.notes.where((n) => n.bookUrl == f.book.bookUrl && NoteDataN.isBookmark(n)).toList();
    expect(marks.single.chapterIndex, 1);
    expect(marks.single.id, startsWith('bm_'));
    unawaited(s.toggleBookmark());
    await settle(tester, until: () => !s.isBookmarked);

    // --- long press selects a sentence; the menu copies it
    await tester.longPress(textBlock(1));
    await settle(tester, max: 5);
    expect(find.text('笔记/高亮'), findsOneWidget);
    expect(find.text('从这行开始朗读'), findsOneWidget);
    await tester.tap(find.text('复制'));
    await settle(tester, max: 3);
    expect(Toast.log, contains('已复制'));
    expect(find.text('笔记/高亮'), findsNothing);

    // --- menus from the centre; font size changes the page count
    final before = s.pageCount;
    await tester.tapAt(const Offset(200, 380));
    await settle(tester, until: () => s.menuVisible);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('朗读'), findsOneWidget);
    expect(find.text('上一章'), findsOneWidget);
    expect(find.text(f.book.name), findsWidgets); // top menu title
    await tester.tap(find.text('界面'));
    await settle(tester, max: 3);
    expect(find.text('界面设置'), findsOneWidget);
    final size = s.setting.fontSize;
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(const ValueKey('font_plus')));
      await settle(tester, max: 2);
    }
    expect(s.setting.fontSize, size + 8);
    expect(Storage.getInt(ReadSetting.fontSizeKey), size + 8);
    await settle(tester, until: () => s.pageCount > before);
    await tester.tapAt(const Offset(200, 200));
    await settle(tester, until: () => !s.menuVisible);

    // --- catalog drawer
    s.openCatalog();
    await settle(tester, max: 10);
    await tester.tap(find.text('第三章 归来'));
    await settle(tester, until: () => s.chapterIndex == 2);
    await settle(tester, max: 10); // drawer closes
    await tester.tapAt(const Offset(380, 400));
    await settle(tester, until: () => s.pageIndex == 1);
    await settle(tester, until: () => f.book.durChapterIndex == 2 && f.book.durChapterPos > 0);
    final saved = f.book.durChapterPos;

    // --- close; the history keeps the position; reopening restores it
    await tester.pumpWidget(app(const SizedBox()));
    await settle(tester, max: 5);
    final history = ReadApi.historyTmp!;
    expect(history.first.bookUrl, f.book.bookUrl);
    expect(history.first.durChapterIndex, 2);
    expect(history.first.durChapterPos, saved);
    s = await openReader(tester, Book.fromJson(history.first.toJson()));
    expect(s.chapterIndex, 2);
    expect(s.pageIndex, 1);
    await finish(tester);
  });

  testWidgets('a web book without a loader shows the original message; unknown types are rejected', (tester) async {
    phoneSize(tester);
    final prev = ReadPage.webLoader;
    ReadPage.webLoader = null;
    addTearDown(() => ReadPage.webLoader = prev);
    await tester.pumpWidget(app(ReadPage(book: Book(bookUrl: 'https://example.com/b', origin: 'https://example.com', name: 'W'))));
    expect(find.text('未接入书源引擎，无法阅读网络书籍'), findsOneWidget);
    await tester.pumpWidget(app(ReadPage(book: Book(bookUrl: 'x', type_: 3))));
    expect(find.text('不支持的阅读类型'), findsOneWidget);
  });
}
