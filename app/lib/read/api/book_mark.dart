// read/api/book_mark.dart — bookmarks of one book (`<documents>/bookmark/<md5(bookUrl)>.txt`, a JSON list of [Bookmark]).
//
// Original: class 1502 `BookMark` with `static ValueNotifier<int> bookmarkVersion` (offset 0x4c98; the bookmark list UI listens to it) and the
// isolate pair `_saveToLocalIsolate(_SaveMarkParams)` 0x57cf5c / `_readFromLocalIsolate(_ReadMarkParams)` 0x57ce30 (returns the raw text).
// `Bookmark` fields: id, cindex (chapter index), cpos (position, 0..1 of the chapter), createtime, cname (chapter name).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/bookmark.dart';
import 'read_file_store.dart';
import 'read_storage_root.dart';

class _ReadMarkParams {
  final String dir;
  final String bookUrl;
  const _ReadMarkParams(this.dir, this.bookUrl);
}

class _SaveMarkParams {
  final String dir;
  final String bookUrl;
  final String json;
  const _SaveMarkParams(this.dir, this.bookUrl, this.json);
}

class BookMark {
  /// Bumped after every change; the bookmark list rebuilds on it.
  static final ValueNotifier<int> bookmarkVersion = ValueNotifier<int>(0);

  final Directory? rootOverride;

  const BookMark({this.rootOverride});

  Directory get root => rootOverride ?? ReadStorageRoot.sub(ReadStorageRoot.bookmark);

  static File fileFor(String dir, String bookUrl) => ReadFileStore.fileFor(Directory(dir), bookUrl);

  Future<List<Bookmark>> getMarks(String bookUrl) async {
    final params = _ReadMarkParams(root.path, bookUrl);
    final text = await ReadIsolate.run(() => _readFromLocalIsolate(params));
    final list = ReadFileStore.decodeList(text) ?? const [];
    return [
      for (final e in list)
        if (e is Map) Bookmark.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> saveMarks(String bookUrl, List<Bookmark> marks) async {
    final params = _SaveMarkParams(root.path, bookUrl, jsonEncode(marks.map((m) => m.toJson()).toList()));
    await ReadIsolate.run(() => _saveToLocalIsolate(params));
    bookmarkVersion.value++;
  }

  /// Adds a bookmark (a second one for the same chapter at the same position replaces the first).
  Future<Bookmark> add(String bookUrl, {required int chapterIndex, required String chapterName, required double position}) async {
    final marks = await getMarks(bookUrl);
    final now = DateTime.now();
    final mark = Bookmark(
      id: '${now.microsecondsSinceEpoch}',
      cindex: chapterIndex,
      cpos: position,
      createtime: now.toIso8601String(),
      cname: chapterName,
    );
    marks.removeWhere((m) => m.cindex == chapterIndex && (m.cpos - position).abs() < 0.0001);
    marks.add(mark);
    await saveMarks(bookUrl, marks);
    return mark;
  }

  Future<void> remove(String bookUrl, String id) async {
    final marks = await getMarks(bookUrl);
    marks.removeWhere((m) => m.id == id);
    await saveMarks(bookUrl, marks);
  }

  Future<void> deleteBook(String bookUrl) async {
    ReadFileStore.deleteSync(fileFor(root.path, bookUrl));
    bookmarkVersion.value++;
  }

  static String _readFromLocalIsolate(_ReadMarkParams p) => ReadFileStore.readTextSync(fileFor(p.dir, p.bookUrl)) ?? '';

  static void _saveToLocalIsolate(_SaveMarkParams p) => ReadFileStore.writeTextSync(fileFor(p.dir, p.bookUrl), p.json);
}
