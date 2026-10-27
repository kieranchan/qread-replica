// widget/book/toc_cache.dart — table of contents of web books kept on disk (`<root>/toc/<md5(bookUrl)>.json`) so the catalog,
// the download manager and the reader open without a network round trip; refreshed by the shelf's update check, the catalog's
// 「刷新」 and the detail page. Local books use `LocalBookImporter.loadChapters` instead.
//
// TODO(asm 0xf6ede8): where the original keeps the fetched chapter lists is not recovered (the update task stores `needsave`);
// the directory name is this port's choice.
import 'dart:convert';
import 'dart:io';

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../read/api/read_file_store.dart';
import '../../read/api/read_storage_root.dart';
import '../../read/local_book_importer.dart';
import '../../data/bookself.dart';
import '../../pages/search/book_search_service.dart';
import '../book_page.dart';

abstract class TocCache {
  static File _file(String bookUrl) => File('${ReadStorageRoot.sub('toc').path}/${ReadFileStore.md5Hex(bookUrl)}.json');

  static Future<List<BookChapter>?> read(String bookUrl) async {
    if (!ReadStorageRoot.isSet) return null;
    final f = _file(bookUrl);
    final list = await ReadIsolate.run(() => ReadFileStore.decodeList(ReadFileStore.readTextSync(f)));
    if (list == null || list.isEmpty) return null;
    return [for (final e in list) if (e is Map) BookChapter.fromJson(Map<String, dynamic>.from(e))];
  }

  static Future<void> write(String bookUrl, List<BookChapter> chapters) async {
    if (!ReadStorageRoot.isSet) return;
    final f = _file(bookUrl);
    final text = jsonEncode([for (final c in chapters) c.toJson()]);
    await ReadIsolate.run(() => ReadFileStore.writeTextSync(f, text));
  }

  static Future<void> delete(String bookUrl) async {
    if (!ReadStorageRoot.isSet) return;
    ReadFileStore.deleteSync(_file(bookUrl));
  }

  /// The chapters of [book]: local file / cache / engine. [refresh] skips the cache for web books. A web refresh also updates
  /// the shelf entry (latest chapter, count, `isredupdate`).
  static Future<List<BookChapter>> load(Book book, {bool refresh = false}) async {
    if (isLocalShelfBook(book)) return const LocalBookImporter().loadChapters(book, reparse: refresh);
    if (!refresh) {
      final cached = await read(book.bookUrl);
      if (cached != null) return cached;
    }
    final list = await BookSearchService.instance.chapters(book);
    for (var i = 0; i < list.length; i++) {
      list[i].index = i;
    }
    await write(book.bookUrl, list);
    if (list.isNotEmpty && BookSelfN.contains(book.bookUrl)) {
      await BookSelfN.updateLatest(book.bookUrl, latestTitle: list.last.name, totalChapters: list.length);
    }
    return list;
  }
}
