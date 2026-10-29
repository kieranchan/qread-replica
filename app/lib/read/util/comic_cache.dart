// read/util/comic_cache.dart — the offline copy of comic chapters: the list of picture urls of a chapter and the pictures
// themselves, kept next to the text cache (`<bookcache2>/<md5(bookUrl)>/<md5(index)>.comic.json` and `.../img/<md5(url)>`).
//
// The original's CacheBook worker (0xf6d158) fetches the pictures of an image chapter as well and logs `缓存图片失败` for one that
// cannot be downloaded; the comic reader then shows the stored pictures without the network. The text cache cannot hold image
// chapters (`ChapterContent.fromText` only knows paragraphs), which is why they get a store of their own here. Both 批量下载
// (CacheBook) and the read-ahead (ReadAhead) go through [cacheChapter]; the comic view reads [readList] / [bytes] first.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../api/book_content.dart';
import '../api/read_file_store.dart';
import '../api/readapi.dart';
import 'chapter_content.dart';

abstract class ComicCache {
  /// `BookType.comic` (pages/read/read_page.dart).
  static const int comicType = 2;

  static bool isComic(Book b) => b.type_ == comicType;

  /// Downloads one picture (bytes); the app may replace it with a source-aware fetch (headers, `imagedecrypt`).
  static Future<Uint8List> Function(Book book, BookChapter chapter, String url) downloader = _download;

  static Directory _bookDir(String bookUrl) => BookContent.bookDir(const BookContent().root, bookUrl);

  static File listFile(String bookUrl, int index) => File('${_bookDir(bookUrl).path}/${ReadFileStore.md5Hex('$index')}.comic.json');

  static File imageFile(String bookUrl, String url) => File('${_bookDir(bookUrl).path}/img/${ReadFileStore.md5Hex(url)}');

  static bool exists(String bookUrl, int index) => listFile(bookUrl, index).existsSync();

  /// The picture urls of an image chapter ([CalcuPages.image] blocks), in order.
  static List<String> imagesOf(ChapterContent c) => [
        for (final b in c.blocks)
          if (b.isImage && b.runs.first.href.isNotEmpty) b.runs.first.href,
      ];

  /// The stored url list of chapter [index], or null.
  static Future<List<String>?> readList(String bookUrl, int index) async {
    final f = listFile(bookUrl, index);
    if (!await f.exists()) return null;
    try {
      final v = jsonDecode(await f.readAsString());
      return v is List ? [for (final e in v) '$e'] : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeList(String bookUrl, int index, List<String> urls, {Book? book}) async {
    final dir = _bookDir(bookUrl);
    await dir.create(recursive: true);
    final info = File('${dir.path}/book.json');
    if (!await info.exists()) await info.writeAsString(jsonEncode(book?.toJson() ?? {'bookUrl': bookUrl}));
    await _writeAtomic(listFile(bookUrl, index), utf8.encode(jsonEncode(urls)));
  }

  /// Downloads [url] into the store (or returns the stored copy).
  static Future<Uint8List> fetch(Book book, BookChapter chapter, String url) async {
    final f = imageFile(book.bookUrl, url);
    if (await f.exists()) return f.readAsBytes();
    final bytes = await downloader(book, chapter, url);
    if (bytes.isEmpty) throw StateError('空图片');
    await f.parent.create(recursive: true);
    await _writeAtomic(f, bytes);
    return bytes;
  }

  /// The picture for the reader: the stored copy or a fresh download; null when neither is possible (the view falls back to the
  /// network image).
  static Future<Uint8List?> bytes(Book book, BookChapter chapter, String url) async {
    try {
      return await fetch(book, chapter, url);
    } catch (e) {
      ReadApi.log?.call('图片加载失败: $url $e');
      return null;
    }
  }

  /// Caches chapter [index] of a comic: its url list (through the loader when not stored yet) and every picture that is not stored
  /// yet. Returns the number of pictures that failed (each logged as `缓存图片失败`); throws when the chapter itself cannot be read.
  static Future<int> cacheChapter(ReadApi api, int index, {bool Function()? isCancelled}) async {
    final book = api.book;
    final chapter = api.chapters[index];
    var urls = await readList(book.bookUrl, index);
    if (urls == null || urls.isEmpty) {
      final loader = api.loader;
      if (loader == null) throw StateError('没有章节来源');
      urls = imagesOf(await loader(chapter));
      if (urls.isEmpty) throw StateError('正文为空');
      await writeList(book.bookUrl, index, urls, book: book);
    }
    var failed = 0;
    for (final u in urls) {
      if (isCancelled?.call() ?? false) break;
      if (!u.startsWith('http') || imageFile(book.bookUrl, u).existsSync()) continue;
      try {
        await fetch(book, chapter, u);
      } catch (e) {
        failed++;
        ReadApi.log?.call('缓存图片失败: $u $e');
      }
    }
    return failed;
  }

  /// Removes the stored chapter lists and pictures of a book.
  static Future<void> deleteBook(String bookUrl) async {
    final dir = _bookDir(bookUrl);
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.comic.json')) await e.delete();
    }
    final img = Directory('${dir.path}/img');
    if (await img.exists()) await img.delete(recursive: true);
  }

  static Future<void> _writeAtomic(File f, List<int> bytes) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  static Future<Uint8List> _download(Book book, BookChapter chapter, String url) async {
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
      if (book.origin.startsWith('http')) 'Referer': book.origin,
    };
    final r = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes, headers: headers, receiveTimeout: const Duration(seconds: 30), validateStatus: (_) => true),
    );
    final code = r.statusCode ?? 0;
    if (code < 200 || code >= 300) throw StateError('HTTP $code');
    return Uint8List.fromList(r.data ?? const []);
  }
}
