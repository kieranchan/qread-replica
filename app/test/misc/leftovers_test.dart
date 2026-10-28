// Small fidelity fixes: the TOC cache key / format of the original (0x254b94, 0xed8e8c) and the local TTS memory policy (0xe96f68).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/audio/local/local_tts_manager.dart';
import 'package:newread/widget/book/toc_cache.dart';

import '../support/env.dart';

void main() {
  late TestDevice dev;
  setUp(() async => dev = await newDevice());
  tearDown(() => dev.delete());

  test('TOC cache: file-store key book_chapter:<bookUrl>,<type> with {latestChapterTitle, checktime, directoryList}', () async {
    final book = Book(bookUrl: 'https://b.example/1', name: '书', type_: 2, latestChapterTitle: '旧');
    expect(TocCache.key(book), 'book_chapter:https://b.example/1,2');
    final before = DateTime.now().millisecondsSinceEpoch;
    await TocCache.write(book, [BookChapter(name: '第一章', index: 0), BookChapter(name: '第二章', index: 1)]);
    final stored = jsonDecode(await Storage.read('book_chapter:https://b.example/1,2')) as Map;
    expect(stored['latestChapterTitle'], '第二章');
    expect(stored['checktime'] as int, greaterThanOrEqualTo(before));
    expect((stored['directoryList'] as List).map((e) => (e as Map)['name']), ['第一章', '第二章']);
    expect((await TocCache.read(book))!.map((c) => c.name), ['第一章', '第二章']);
    // another type of the same url is another entry
    expect(await TocCache.read(Book(bookUrl: 'https://b.example/1', type_: 0)), isNull);
    expect(TocCache.parse(jsonEncode([{'name': 'x'}]))!.single.name, 'x');
    expect(TocCache.parse('not json'), isNull);
    await TocCache.delete(book);
    expect(await TocCache.read(book), isNull);
  });

  test('local TTS: no size threshold for recycling (the original only reports rss)', () {
    expect(LocalTtsManager.maxGrowthMb, 0);
  });
}
