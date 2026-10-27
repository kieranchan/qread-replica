// read/api/book_content.dart — cache of downloaded chapter text (`<documents>/bookcache2`).
//
// Original (class 1509 `BookContent`; `_saveToLocalIsolate(_SaveLocalParams)` 0x2a76b8 -> 0xf13240, `_readFromLocalIsolate(_ReadLocalParams)`
// 0x1bbe94): both run in an isolate. The save routine builds `<dir>/<md5(bookUrl)>`, creates it, writes `<dir>/<md5(bookUrl)>/book.json`
// and the chapter into `.../<md5(index)>.txt` through a temp file (`保存失败: <path>, 错误: <e>`).
// TODO(asm 0xf13240): the registers of the path building are ambiguous; `md5(utf8(bookUrl))` / `md5(utf8("$index"))` as directory /
// file name is the reading that fits the two `Utf8Encoder -> _MD5` pairs and the `/book.json` literal. If a backup of the original
// app does not show up, compare against a real `bookcache2` folder.
import 'dart:convert';
import 'dart:io';

import '../../models/book.dart';
import 'read_file_store.dart';
import 'read_storage_root.dart';

class _SaveLocalParams {
  final String dir;
  final String bookUrl;
  final int index;
  final String content;
  final String bookJson;
  const _SaveLocalParams(this.dir, this.bookUrl, this.index, this.content, this.bookJson);
}

class _ReadLocalParams {
  final String dir;
  final String bookUrl;
  final int index;
  const _ReadLocalParams(this.dir, this.bookUrl, this.index);
}

class BookContent {
  /// Cache root; defaults to `<ReadStorageRoot.dir>/bookcache2`.
  final Directory? rootOverride;

  const BookContent({this.rootOverride});

  Directory get root => rootOverride ?? ReadStorageRoot.sub(ReadStorageRoot.bookcache2);

  static Directory bookDir(Directory root, String bookUrl) => Directory('${root.path}/${ReadFileStore.md5Hex(bookUrl)}');

  static File chapterFile(Directory root, String bookUrl, int index) =>
      File('${bookDir(root, bookUrl).path}/${ReadFileStore.md5Hex('$index')}.txt');

  /// Cached text of chapter [index], or null.
  Future<String?> readFromLocal(String bookUrl, int index) {
    final params = _ReadLocalParams(root.path, bookUrl, index);
    return ReadIsolate.run(() => _readFromLocalIsolate(params));
  }

  /// Stores the text of chapter [index]; [book] (optional) is written to `book.json` so the directory can be identified.
  Future<void> saveToLocal(String bookUrl, int index, String content, {Book? book}) {
    final params = _SaveLocalParams(
      root.path,
      bookUrl,
      index,
      content,
      jsonEncode(book?.toJson() ?? {'bookUrl': bookUrl}),
    );
    return ReadIsolate.run(() => _saveToLocalIsolate(params));
  }

  bool existsSync(String bookUrl, int index) => chapterFile(root, bookUrl, index).existsSync();

  /// Which of chapters `0 until total` are cached.
  Set<int> cachedIndexesSync(String bookUrl, int total) => {
        for (var i = 0; i < total; i++)
          if (existsSync(bookUrl, i)) i,
      };

  Future<void> deleteChapter(String bookUrl, int index) async => ReadFileStore.deleteSync(chapterFile(root, bookUrl, index));

  /// Removes everything cached for the book.
  Future<void> deleteBook(String bookUrl) async {
    final d = bookDir(root, bookUrl);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  static String? _readFromLocalIsolate(_ReadLocalParams p) {
    final f = chapterFile(Directory(p.dir), p.bookUrl, p.index);
    return ReadFileStore.readTextSync(f);
  }

  static void _saveToLocalIsolate(_SaveLocalParams p) {
    final root = Directory(p.dir);
    final dir = bookDir(root, p.bookUrl);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final meta = File('${dir.path}/book.json');
    if (!meta.existsSync()) ReadFileStore.writeTextSync(meta, p.bookJson);
    ReadFileStore.writeTextSync(chapterFile(root, p.bookUrl, p.index), p.content);
  }
}
