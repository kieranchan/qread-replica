// The reader takes a web book's catalog from the TOC cache (as the original's reader init: `目录缓存获取成功`), so a book
// opened from the shelf does not wait for the network; the engine is asked only when nothing is stored. init/wiring.dart
// installs that loader; the test installs the same line and checks the wiring source still carries it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/pages/read/read_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/widget/book/toc_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('reader catalog: TOC cache first, engine only without one', () async {
    final root = Directory.systemTemp.createTempSync('qread_toc_');
    addTearDown(() => root.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});
    await Storage.init(prefs: await SharedPreferences.getInstance(), root: root);

    const glue = 'ReadPage.webChapters = (book) => TocCache.load(book);';
    expect(File('lib/init/wiring.dart').readAsStringSync(), contains(glue), reason: 'the reader must keep reading the TOC cache first');
    ReadPage.webChapters = (book) => TocCache.load(book);

    final book = Book(bookUrl: 'https://example.com/book/1', name: '测试书', author: 'A', origin: 'https://example.com');
    await TocCache.write(book, [BookChapter(name: '第一章', index: 0, chapterId: 'c0'), BookChapter(name: '第二章', index: 1, chapterId: 'c1')]);
    final loader = ReadPage.chapterListOf(book)!;
    final list = await loader(book);
    expect(list.map((c) => c.name).toList(), ['第一章', '第二章']);

    // nothing cached: the engine path is taken (no engine is wired here, so it fails or answers nothing; no network either way)
    final other = Book(bookUrl: 'https://example.com/book/2', name: '另一本', author: 'A', origin: 'https://example.com');
    List<BookChapter> fallback = const [];
    Object? error;
    try {
      fallback = await loader(other);
    } catch (e) {
      error = e;
    }
    expect(error != null || fallback.isEmpty, isTrue);
  });
}
