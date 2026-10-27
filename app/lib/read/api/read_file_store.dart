// read/api/read_file_store.dart — file naming + atomic text files + the isolate hop shared by the per-book stores.
//
// Naming as in docs/SETTINGS.md §1: one text file per key, `<md5hex(utf8(key))>.txt`; writes go through a `.tmp` file and a
// rename (the original writes `…tmp`/`…tmp2`; error texts `保存失败: <path>, 错误: <e>` / `读取失败: <path>, 错误: <e>`
// are the originals'). The original runs every read/write in an isolate (`_readFromLocalIsolate` / `_saveToLocalIsolate`
// closures taking a params object); [ReadIsolate] keeps that pattern behind a switch so tests run inline.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'read_storage_root.dart';

abstract class ReadIsolate {
  /// When false (tests) the work runs in the calling isolate.
  static bool enabled = true;

  /// Runs [computation] in a short-lived isolate (a top-level or static function plus plain data, as in the original).
  static Future<R> run<R>(R Function() computation) {
    if (!enabled) return Future<R>.sync(computation);
    return Isolate.run<R>(computation);
  }
}

class ReadStoreException implements Exception {
  final String message;
  const ReadStoreException(this.message);
  @override
  String toString() => message;
}

abstract class ReadFileStore {
  /// `md5(utf8(key))` as lower-case hex.
  static String md5Hex(String key) => md5.convert(utf8.encode(key)).toString();

  /// `<dir>/<md5(key)>.txt`.
  static File fileFor(Directory dir, String key) => File('${dir.path}/${md5Hex(key)}.txt');

  /// Writes through `<file>.tmp` and a rename so a crash never leaves a half-written file behind.
  static void writeTextSync(File file, String content) {
    try {
      final parent = file.parent;
      if (!parent.existsSync()) parent.createSync(recursive: true);
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(content, flush: true);
      if (file.existsSync()) file.deleteSync();
      tmp.renameSync(file.path);
    } catch (e) {
      throw ReadStoreException('保存失败: ${file.path}, 错误: $e');
    }
  }

  /// Null when the file does not exist.
  static String? readTextSync(File file) {
    try {
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (e) {
      throw ReadStoreException('读取失败: ${file.path}, 错误: $e');
    }
  }

  static void deleteSync(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Decodes a JSON object; null for missing / empty / malformed text.
  static Map<String, dynamic>? decodeObject(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final j = jsonDecode(text);
      if (j is Map<String, dynamic>) return j;
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return null;
  }

  static List<dynamic>? decodeList(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final j = jsonDecode(text);
      if (j is List) return j;
    } catch (_) {}
    return null;
  }
}

/// A named key in the shared "item" store (`<root>/item/<md5(key)>.txt`, docs/SETTINGS.md §1). The storage owner's
/// `Storage.read/write` does the same for the rest of the app; the reader only needs it for `historybook`.
abstract class ReadItemStore {
  static File fileOf(String key) => ReadFileStore.fileFor(ReadStorageRoot.sub(ReadStorageRoot.item), key);

  static Future<String?> read(String key) {
    final f = fileOf(key);
    return ReadIsolate.run(() => ReadFileStore.readTextSync(f));
  }

  static Future<void> write(String key, String value) {
    final f = fileOf(key);
    return ReadIsolate.run(() => ReadFileStore.writeTextSync(f, value));
  }
}
