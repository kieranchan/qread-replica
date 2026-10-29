// Comic chapters offline (read/util/comic_cache.dart): the url list and the pictures of a chapter are stored, 批量下载 (CacheBook)
// and the read-ahead go through the store, failures are logged as the original's `缓存图片失败`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/model/line.dart';
import 'package:newread/read/model/page.dart';
import 'package:newread/read/util/cache_book.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/comic_cache.dart';
import 'package:newread/read/util/read_ahead.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _comic() => Book(bookUrl: 'https://example.com/comic/1', name: '漫画', author: 'A', origin: 'https://example.com', type_: ComicCache.comicType);

ChapterContent _pictures(int chapter, int n) => ChapterContent.fromBlocks([
      for (var i = 0; i < n; i++) CalcuPages.image(CLine(type: CLineType.image, href: 'https://img.example.com/$chapter/$i.jpg')),
    ]);

void main() {
  late Directory tmp;
  final log = <String>[];
  final downloads = <String>[];
  Set<String> broken = {};

  setUp(() async {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_comic_');
    ReadStorageRoot.dir = tmp;
    ReadApi.resetCaches();
    ReadApi.remote = null;
    ReadApi.onProgress = null;
    log.clear();
    downloads.clear();
    broken = {};
    ReadApi.log = log.add;
    ComicCache.downloader = (book, chapter, url) async {
      downloads.add(url);
      if (broken.contains(url)) throw StateError('404');
      return Uint8List.fromList(url.codeUnits);
    };
    SharedPreferences.setMockInitialValues({'cachebook': 2});
    await Storage.init(prefs: await SharedPreferences.getInstance(), root: tmp);
  });

  tearDown(() async {
    ReadAhead.stopAll();
    ReadApi.log = null;
    tmp.deleteSync(recursive: true);
  });

  ReadApi api(Book book, {int chapters = 4, int pictures = 3, List<int>? started}) => ReadApi(
        book,
        chapters: [for (var i = 0; i < chapters; i++) BookChapter(name: '第${i + 1}话', index: i, chapterId: 'c$i')],
        loader: (c) async {
          started?.add(c.index);
          return _pictures(c.index, pictures);
        },
      );

  test('cacheChapter stores the url list and the pictures; a stored chapter is not fetched again; lost pictures are logged', () async {
    final book = _comic();
    final started = <int>[];
    final a = api(book, started: started);
    expect(ComicCache.exists(book.bookUrl, 1), isFalse);
    expect(await ComicCache.cacheChapter(a, 1), 0);
    expect(started, [1]);
    expect(ComicCache.exists(book.bookUrl, 1), isTrue);
    expect(await ComicCache.readList(book.bookUrl, 1), ['https://img.example.com/1/0.jpg', 'https://img.example.com/1/1.jpg', 'https://img.example.com/1/2.jpg']);
    expect(downloads.length, 3);
    expect(ComicCache.imageFile(book.bookUrl, 'https://img.example.com/1/2.jpg').readAsStringSync(), 'https://img.example.com/1/2.jpg');
    expect(File('${tmp.path}/bookcache2/${ReadFileStore.md5Hex(book.bookUrl)}/book.json').existsSync(), isTrue);
    // second run: nothing to do
    downloads.clear();
    expect(await ComicCache.cacheChapter(a, 1), 0);
    expect(started, [1]);
    expect(downloads, isEmpty);
    // a picture that cannot be fetched is counted and logged, the rest is stored
    broken = {'https://img.example.com/2/1.jpg'};
    expect(await ComicCache.cacheChapter(a, 2), 1);
    expect(log.where((l) => l.startsWith('缓存图片失败: https://img.example.com/2/1.jpg')).length, 1);
    expect(ComicCache.imageFile(book.bookUrl, 'https://img.example.com/2/0.jpg').existsSync(), isTrue);
    expect(ComicCache.imageFile(book.bookUrl, 'https://img.example.com/2/1.jpg').existsSync(), isFalse);
    // bytes(): the stored copy, else a download, else null (the view then uses the network image)
    downloads.clear();
    expect(await ComicCache.bytes(book, a.chapters[2], 'https://img.example.com/2/0.jpg'), isNotNull);
    expect(downloads, isEmpty);
    expect(await ComicCache.bytes(book, a.chapters[2], 'https://img.example.com/2/1.jpg'), isNull);
    broken = {};
    expect(await ComicCache.bytes(book, a.chapters[2], 'https://img.example.com/2/1.jpg'), isNotNull);
    expect(ComicCache.imageFile(book.bookUrl, 'https://img.example.com/2/1.jpg').existsSync(), isTrue);
    await ComicCache.deleteBook(book.bookUrl);
    expect(ComicCache.exists(book.bookUrl, 1), isFalse);
    expect(ComicCache.imageFile(book.bookUrl, 'https://img.example.com/2/0.jpg').existsSync(), isFalse);
  });

  test('an image chapter without pictures is 正文为空', () async {
    final book = _comic();
    final a = api(book, pictures: 0);
    expect(ComicCache.cacheChapter(a, 0), throwsA(isA<StateError>().having((e) => e.message, 'message', '正文为空')));
  });

  test('CacheBook on a comic: the range goes through the store, stored chapters are skipped, lost pictures fail the chapter', () async {
    final book = _comic();
    final a = api(book, chapters: 5);
    await ComicCache.cacheChapter(a, 2);
    broken = {'https://img.example.com/4/0.jpg'};
    final r = await CacheBook(a, concurrent: 1).cacheRange(1, 4);
    expect(r.cached, [1, 3]);
    expect(r.skipped, [2]);
    expect(r.failed.keys.toList(), [4]);
    expect(r.failed[4], '缓存图片失败: 1 张');
    expect(ComicCache.exists(book.bookUrl, 4), isTrue, reason: 'the url list is kept, the lost picture is tried again later');
    expect(a.bookContent.existsSync(book.bookUrl, 1), isFalse, reason: 'nothing goes into the text cache');
  });

  test('read-ahead on a comic stores the following chapters with their pictures', () async {
    final book = _comic();
    final a = api(book, chapters: 6, pictures: 2);
    ReadAhead.touch(a, 1);
    await (ReadAhead.running(book.bookUrl) ?? Future.value());
    expect(ComicCache.exists(book.bookUrl, 2), isTrue);
    expect(ComicCache.exists(book.bookUrl, 3), isTrue);
    expect(ComicCache.exists(book.bookUrl, 4), isFalse);
    expect(downloads.length, 4);
  });
}
