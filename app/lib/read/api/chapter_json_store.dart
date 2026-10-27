// read/api/chapter_json_store.dart — shared plumbing of `BookRules` / `BookHight` / `BookAi`: one JSON text file per (book, chapter)
// under `<root>/<dir>/<md5(bookUrl)>/<md5(index)>.txt`, written through a temp file inside an isolate.
//
// TODO(asm 0xf0b7a8 / 0xf0bfc0): the original's file path has a single `md5(...)` component (`<dir>/<md5>.txt`); the per-book
// sub-directory used here keeps deletion per book simple and is invisible to callers.
import 'dart:convert';
import 'dart:io';

import 'read_file_store.dart';
import 'read_storage_root.dart';

class ChapterJsonStore {
  final String dirName;
  final Directory? rootOverride;

  const ChapterJsonStore(this.dirName, {this.rootOverride});

  Directory get root => rootOverride ?? ReadStorageRoot.sub(dirName);

  static File fileFor(String root, String bookUrl, int index) =>
      File('$root/${ReadFileStore.md5Hex(bookUrl)}/${ReadFileStore.md5Hex('$index')}.txt');

  Future<Map<String, dynamic>?> read(String bookUrl, int index) {
    final path = root.path;
    return ReadIsolate.run(() => readSync(path, bookUrl, index));
  }

  Future<void> save(String bookUrl, int index, Map<String, dynamic> json) {
    final path = root.path;
    final text = jsonEncode(json);
    return ReadIsolate.run(() => saveSync(path, bookUrl, index, text));
  }

  /// Isolate bodies (top-level style: plain data in, plain data out).
  static Map<String, dynamic>? readSync(String root, String bookUrl, int index) =>
      ReadFileStore.decodeObject(ReadFileStore.readTextSync(fileFor(root, bookUrl, index)));

  static void saveSync(String root, String bookUrl, int index, String json) => ReadFileStore.writeTextSync(fileFor(root, bookUrl, index), json);

  Future<void> delete(String bookUrl, int index) async => ReadFileStore.deleteSync(fileFor(root.path, bookUrl, index));

  Future<void> deleteBook(String bookUrl) async {
    final d = Directory('${root.path}/${ReadFileStore.md5Hex(bookUrl)}');
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
