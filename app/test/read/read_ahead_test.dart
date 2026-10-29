// 预缓存 while reading (read/util/read_ahead.dart): the chapters after the current one are downloaded in the background.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/read_ahead.dart';

Book _book({String origin = 'https://example.com'}) => Book(bookUrl: 'https://example.com/book/1', name: '测试书', author: 'A', origin: origin);

List<BookChapter> _chapters(int n) => [for (var i = 0; i < n; i++) BookChapter(name: '第${i + 1}章', index: i, chapterId: 'c$i')];

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('qread_ahead_');
    ReadStorageRoot.dir = tmp;
    ReadApi.resetCaches();
    ReadAhead.stopAll();
    ReadAhead.log = null;
    ReadAhead.count = () => 5;
  });
  tearDown(() async {
    ReadAhead.stopAll();
    tmp.deleteSync(recursive: true);
  });

  test('caches the next N chapters, skipping cached, volume and paid ones', () async {
    final loaded = <int>[];
    final book = _book();
    final api = ReadApi(book, chapters: _chapters(12), loader: (c) async {
      loaded.add(c.index);
      return ChapterContent.fromText('正文${c.index}');
    });
    api.chapters[3].isVolume = true;
    api.chapters[4].isPay = true;
    await api.bookContent.saveToLocal(book.bookUrl, 2, '已有', book: book);
    ReadAhead.touch(api, 0);
    expect(ReadAhead.isRunning(book.bookUrl), isTrue);
    await ReadAhead.running(book.bookUrl);
    expect(loaded, [1, 5]);
    expect(api.bookContent.existsSync(book.bookUrl, 5), isTrue);
    expect(api.bookContent.existsSync(book.bookUrl, 6), isFalse);
    expect(ReadAhead.isRunning(book.bookUrl), isFalse);
  });

  test('a chapter change moves the window; the window stops at the last chapter', () async {
    final loaded = <int>[];
    final api = ReadApi(_book(), chapters: _chapters(10), loader: (c) async {
      loaded.add(c.index);
      return ChapterContent.fromText('正文${c.index}');
    });
    ReadAhead.count = () => 3;
    ReadAhead.touch(api, 0); // starts with chapter 1 in flight
    ReadAhead.touch(api, 5); // now 6..8
    await ReadAhead.running(api.book.bookUrl);
    expect(loaded, [1, 6, 7, 8]);
    ReadAhead.touch(api, 8); // 9 is the last chapter
    await ReadAhead.running(api.book.bookUrl);
    expect(loaded, [1, 6, 7, 8, 9]);
    ReadAhead.touch(api, 9); // nothing left after the last chapter: the job ends without fetching
    await ReadAhead.running(api.book.bookUrl);
    expect(loaded, [1, 6, 7, 8, 9]);
    expect(ReadAhead.isRunning(api.book.bookUrl), isFalse);
  });

  test('count 0 and local books do nothing; three failures in a row stop the job', () async {
    var calls = 0;
    final api = ReadApi(_book(), chapters: _chapters(10), loader: (c) async {
      calls++;
      return ChapterContent.fromText('x');
    });
    ReadAhead.count = () => 0;
    ReadAhead.touch(api, 0);
    expect(ReadAhead.isRunning(api.book.bookUrl), isFalse);
    ReadAhead.count = () => 5;
    final local = ReadApi(_book(origin: ReadApi.localOrigin), chapters: _chapters(10), loader: (c) async => ChapterContent.fromText('x'));
    ReadAhead.touch(local, 0);
    expect(ReadAhead.isRunning(local.book.bookUrl), isFalse);
    expect(calls, 0);

    final lines = <String>[];
    ReadAhead.log = lines.add;
    final failing = ReadApi(_book(), chapters: _chapters(10), loader: (c) async {
      calls++;
      throw StateError('offline');
    });
    ReadAhead.touch(failing, 0);
    await ReadAhead.running(failing.book.bookUrl);
    expect(calls, 3);
    expect(lines.last, contains('暂停'));
    // the next chapter change starts counting again
    ReadAhead.touch(failing, 3);
    await ReadAhead.running(failing.book.bookUrl);
    expect(calls, 6);
  });

  test('stop() ends the job of the closed reader', () async {
    final gate = Completer<void>();
    final loaded = <int>[];
    final api = ReadApi(_book(), chapters: _chapters(10), loader: (c) async {
      loaded.add(c.index);
      await gate.future;
      return ChapterContent.fromText('x');
    });
    ReadAhead.touch(api, 0);
    ReadAhead.stop(api.book.bookUrl);
    gate.complete();
    await ReadAhead.running(api.book.bookUrl);
    expect(loaded, [1]);
    expect(ReadAhead.isRunning(api.book.bookUrl), isFalse);
  });
}
