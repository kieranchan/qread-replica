// Fast chapter jumps (上一章 / 下一章 tapped quickly, or a jump still loading when the reader closes): a jump whose chapter loads
// slowly must not win over a newer one — seen on the owner's phone as the progress sitting three chapters after the last tap.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/pages/read/pages/novel_view.dart';
import 'package:newread/pages/read/read_page.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/read_ahead.dart';

import 'support.dart';

void main() {
  testWidgets('a slow earlier jump does not override a later one; nothing is saved after the reader closed', (tester) async {
    phoneSize(tester);
    await tester.runAsync(setUpReader);
    final book = Book(bookUrl: 'https://example.com/race', name: '竞态书', author: 'A', origin: 'https://example.com', durChapterIndex: 4);
    final chapters = [for (var i = 0; i < 6; i++) BookChapter(name: '第${i + 1}章', index: i, chapterId: 'c$i')];
    final gate = Completer<void>();
    Future<ChapterContent> loader(BookChapter c) async {
      if (c.index == 3) await gate.future; // the slow chapter
      return ChapterContent.fromText('${c.name}正文。\n' * 30);
    }

    await tester.pumpWidget(app(ReadPage(book: book, chapters: chapters, loader: loader, chapterIndex: 4)));
    await settle(tester, until: () {
      final s = tester.stateList<NovelViewState>(find.byType(NovelView));
      return s.isNotEmpty && s.first.pageCount > 0;
    });
    final s = tester.state<NovelViewState>(find.byType(NovelView));
    expect(s.chapterIndex, 4);

    unawaited(s.jumpToChapter(3)); // waits for the gate
    await settle(tester, max: 3);
    unawaited(s.jumpToChapter(2)); // loads at once
    await settle(tester, until: () => s.chapterIndex == 2);
    await settle(tester, until: () => book.durChapterIndex == 2);
    gate.complete(); // the slow jump finishes now: it must change nothing
    await settle(tester, max: 20);
    expect(s.chapterIndex, 2);
    expect(book.durChapterIndex, 2);
    expect(book.durChapterTitle, '第3章');

    // a jump still loading when the reader closes saves nothing either
    final gate2 = Completer<void>();
    ReadAhead.stopAll();
    await tester.pumpWidget(app(const SizedBox())); // dispose the first reader: the same tree shape would reuse its state
    await settle(tester, max: 3);
    // a fresh book: chapters of the first one are already in the content cache (read-ahead), which would bypass the gate
    final book2 = Book(bookUrl: 'https://example.com/race2', name: '竞态书二', author: 'A', origin: 'https://example.com', durChapterIndex: 2);
    await tester.pumpWidget(app(ReadPage(
      book: book2,
      chapters: chapters,
      loader: (c) async {
        if (c.index == 5) await gate2.future;
        return ChapterContent.fromText('${c.name}正文。\n' * 30);
      },
      chapterIndex: 2,
    )));
    await settle(tester, until: () {
      final s2 = tester.stateList<NovelViewState>(find.byType(NovelView));
      return s2.isNotEmpty && s2.first.pageCount > 0;
    });
    final s2 = tester.state<NovelViewState>(find.byType(NovelView));
    expect(identical(s2, s), isFalse);
    expect(s2.chapterIndex, 2);
    unawaited(s2.jumpToChapter(5));
    await settle(tester, max: 3);
    expect(s2.chapterIndex, 2, reason: 'chapter 6 is still loading');
    await tester.pumpWidget(app(const SizedBox())); // the reader is closed while chapter 6 is still loading
    await settle(tester, max: 3);
    gate2.complete();
    await settle(tester, max: 20);
    expect(book2.durChapterIndex, 2, reason: 'the detached jump must not save chapter 6');
    ReadAhead.stopAll();
  });
}
