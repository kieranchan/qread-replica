// widget/book/toc_cache.dart — table of contents of web books kept in the file store so the catalog, the download manager and the
// reader open without a network round trip; refreshed by the shelf's update check, the catalog's 「刷新」 and the detail page. Local
// books use `LocalBookImporter.loadChapters` instead.
//
// As the original's TOC task (0xed6a58 → 0xed8e8c `needsave`): the entry is `Storage.write` (0xe66a0c / 0xe06f14, i.e.
// `<documents>/item/<md5(key)>.txt`, static 0x1ed4 = "item") under the key `book_chapter:<bookUrl>,<type>` (0x254b94 via 0x254528) with
// the JSON `{latestChapterTitle, checktime (ms), directoryList: [chapters]}`; it is read back with `_parseDirectoryListJson`
// (`目录缓存获取成功:`).
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../read/local_book_importer.dart';
import '../../data/bookself.dart';
import '../../pages/search/book_search_service.dart';
import '../../storage/storage.dart';
import '../book_page.dart';

abstract class TocCache {
  /// 0x254b94.
  static String key(Book book) => 'book_chapter:${book.bookUrl},${book.type_}';

  /// `_parseDirectoryListJson`: the chapters of a stored entry (also accepts a bare JSON list).
  static List<BookChapter>? parse(String text) {
    if (text.trim().isEmpty) return null;
    Object? v;
    try {
      v = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (v is Map) v = v['directoryList'];
    if (v is String && v.trim().startsWith('[')) v = jsonDecode(v);
    if (v is! List || v.isEmpty) return null;
    return [for (final e in v) if (e is Map) BookChapter.fromJson(Map<String, dynamic>.from(e))];
  }

  static Future<List<BookChapter>?> read(Book book) async {
    try {
      final list = parse(await Storage.read(key(book)));
      if (list != null) debugPrint('目录缓存获取成功:${list.length}');
      return list;
    } catch (e) {
      debugPrint('查询本地缓存失败：$e');
      return null;
    }
  }

  static Future<void> write(Book book, List<BookChapter> chapters) async {
    final text = jsonEncode({
      'latestChapterTitle': chapters.isEmpty ? book.latestChapterTitle : chapters.last.name,
      'checktime': DateTime.now().millisecondsSinceEpoch,
      'directoryList': [for (final c in chapters) c.toJson()],
    });
    try {
      await Storage.write(key(book), text);
    } catch (e) {
      debugPrint('目录缓存保存失败：$e');
    }
  }

  static Future<void> delete(Book book) async {
    try {
      await Storage.delete(key(book));
    } catch (_) {}
  }

  /// The chapters of [book]: local file / cache / engine. [refresh] skips the cache for web books. A web refresh also updates
  /// the shelf entry (latest chapter, count, `isredupdate`).
  static Future<List<BookChapter>> load(Book book, {bool refresh = false}) async {
    if (isLocalShelfBook(book)) return const LocalBookImporter().loadChapters(book, reparse: refresh);
    if (!refresh) {
      final cached = await read(book);
      if (cached != null) return cached;
    }
    final list = await BookSearchService.instance.chapters(book);
    for (var i = 0; i < list.length; i++) {
      list[i].index = i;
    }
    await write(book, list);
    if (list.isNotEmpty && BookSelfN.contains(book.bookUrl)) {
      await BookSelfN.updateLatest(book.bookUrl, latestTitle: list.last.name, totalChapters: list.length);
    }
    return list;
  }
}
