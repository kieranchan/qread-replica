// storage/storage.dart — the two key/value layers of the original (docs/SETTINGS.md section 1).
//
//  * prefs      `Storage.getString/setString/getBool/...` over SharedPreferences (static `Storage._prefs`, 0x3da0). The original
//               keeps **every value as a String** (`prefs.get(key)?.toString() ?? ""`, callers convert with toBool/toInt, setters
//               write "true"/"false"/decimal text). The replica does the same; getters also accept natively typed values so
//               prefs written by older builds or by `SharedPreferences.setMockInitialValues` still read back.
//  * file store `Storage.read/write` (0xe66a0c / 0xe06f14): one text file per key, `<root>/item/<md5hex(utf8(key))>.txt`, big
//               JSON lists live here. Writes go through `<file>.tmp` and a `<file>.tmp2` commit marker as in the isolate
//               functions `_write` 0xe073ec / `_read` 0xe66eb0.
//
// The storage root is `AppDirs.root` (injectable; see common/app_dirs.dart).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_dirs.dart';
import '../common/common.dart';
import '../common/lock.dart';

/// Error of a failed file-store access; [message] is the user-visible text of the original (`保存失败: …, 错误: …`).
class StorageException implements Exception {
  final String message;
  const StorageException(this.message);
  @override
  String toString() => message;
}

abstract class Storage {
  static late SharedPreferences _prefs;
  static bool _ready = false;

  /// Opens SharedPreferences. [prefs] injects an instance (tests); [root] sets `AppDirs.root` for the file store.
  static Future<void> init({SharedPreferences? prefs, Directory? root}) async {
    if (root != null) AppDirs.root = root;
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _ready = true;
  }

  static bool get ready => _ready;

  // ------------------------------------------------------------------------------------------------ prefs layer

  /// `Storage.getString` 0xd53c0: the stored value as text, [def] when absent.
  static String getString(String key, [String def = '']) {
    if (!_ready) return def;
    final v = _prefs.get(key);
    return v == null ? def : v.toString();
  }

  /// `toBool` 0xd52bc applied to the stored text: `"true"` / `"1"` are true; absent gives [def].
  static bool getBool(String key, [bool def = false]) {
    if (!_ready) return def;
    final v = _prefs.get(key);
    if (v == null) return def;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return def;
    return s == 'true' || s == '1';
  }

  /// `toInt` 0x1cac00: integer text (a decimal like `3.0` is truncated); [def] when absent or unparsable.
  static int getInt(String key, [int def = 0]) {
    if (!_ready) return def;
    final v = _prefs.get(key);
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? def;
  }

  static double getDouble(String key, [double def = 0]) {
    if (!_ready) return def;
    final v = _prefs.get(key);
    if (v == null) return def;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim()) ?? def;
  }

  /// `Storage.setString` 0xe65a8c.
  static Future<void> setString(String key, String value) async {
    if (_ready) await _prefs.setString(key, value);
  }

  static Future<void> setBool(String key, bool value) async {
    if (_ready) await _prefs.setString(key, value ? 'true' : 'false');
  }

  static Future<void> setInt(String key, int value) async {
    if (_ready) await _prefs.setString(key, '$value');
  }

  static Future<void> setDouble(String key, double value) async {
    if (_ready) await _prefs.setString(key, '$value');
  }

  static Future<void> remove(String key) async {
    if (_ready) await _prefs.remove(key);
  }

  static bool containsKey(String key) => _ready && _prefs.containsKey(key);

  /// Every prefs entry as text: the `settings` map of a backup's `settings.json` (auto backup 0x10bb7d0 loops `prefs.get(key)`).
  static Map<String, String> dumpPrefs() {
    if (!_ready) return {};
    return {for (final k in _prefs.getKeys()) k: _prefs.get(k).toString()};
  }

  /// Restores a `settings.json` dump: every entry is written back as text.
  static Future<void> restorePrefs(Map<String, dynamic> settings) async {
    if (!_ready) return;
    for (final e in settings.entries) {
      if (e.value == null) continue;
      await _prefs.setString(e.key, e.value.toString());
    }
  }

  // ------------------------------------------------------------------------------------------------ file store

  static final Map<String, Lock> _fileLocks = {};

  /// `md5hex(utf8(key))`: the file name stem; also the entries of `Common.cleanwhite`.
  static String md5Of(String key) => crypto.md5.convert(utf8.encode(key)).toString();

  /// `<root>/item/<md5>.txt`.
  static String itemPath(String key) => p.join(AppDirs.item.path, '${md5Of(key)}.txt');

  /// Marks [key] as one that survives [cleanItems] (what each data manager does when it loads).
  static void keepOnClean(String key) => Common.cleanwhite.add(md5Of(key));

  static Future<void> _ensureItemDir() async {
    if (!AppDirs.hasRoot) await AppDirs.init();
    final d = AppDirs.item;
    if (!d.existsSync()) await d.create(recursive: true);
  }

  /// `Storage.read` 0xe66a0c: the text stored under [key], `''` when there is none.
  static Future<String> read(String key) async {
    try {
      await _ensureItemDir();
      final lock = _fileLocks.putIfAbsent(key, Lock.new);
      return await lock.synchronized(() => readFile(itemPath(key)));
    } catch (e) {
      throw StorageException('读取失败: $key, 错误: $e');
    }
  }

  /// `Storage.write` 0xe06f14: replaces the text under [key]; an empty [value] deletes the file.
  static Future<void> write(String key, String value) async {
    try {
      await _ensureItemDir();
      final lock = _fileLocks.putIfAbsent(key, Lock.new);
      await lock.synchronized(() => writeFile(itemPath(key), value));
    } catch (e) {
      throw StorageException('保存失败: $key, 错误: $e');
    }
  }

  static Future<bool> exists(String key) async {
    await _ensureItemDir();
    return File(itemPath(key)).existsSync();
  }

  static Future<void> delete(String key) => write(key, '');

  /// JSON helpers on top of read/write: `readJson` gives null when nothing is stored or the text is not JSON.
  static Future<Object?> readJson(String key) async {
    final s = await read(key);
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeJson(String key, Object? value) => write(key, jsonEncode(value));

  /// `Storage.jsondecode` 0x2284d8 (isolate helper): the decoded list, `[]` for anything else.
  static List<dynamic> jsondecode(String text) {
    if (text.isEmpty) return [];
    try {
      final v = jsonDecode(text);
      return v is List ? v : [];
    } catch (_) {
      return [];
    }
  }

  /// Deletes every item file whose name is not in `Common.cleanwhite` (the "clean items" action). Returns the count.
  static Future<int> cleanItems() async {
    await _ensureItemDir();
    var n = 0;
    for (final e in AppDirs.item.listSync()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      final stem = name.endsWith('.txt') ? name.substring(0, name.length - 4) : name;
      if (Common.cleanwhite.contains(stem)) continue;
      e.deleteSync();
      n++;
    }
    return n;
  }

  // -------------------------------------------------------------------------------- atomic file read / write

  /// `_write` 0xe073ec. [value] empty: delete [path]. Otherwise: write `<path>.tmp`, create the marker `<path>.tmp2`
  /// ("tmp is complete"), move tmp over [path], remove marker and leftovers.
  static Future<void> writeFile(String path, String value) async {
    final target = File(path);
    final tmp = File('$path.tmp');
    final marker = File('$path.tmp2');
    if (value.isEmpty) {
      if (target.existsSync()) await target.delete();
      if (tmp.existsSync()) await tmp.delete();
      if (marker.existsSync()) await marker.delete();
      return;
    }
    await tmp.writeAsString(value, flush: true);
    await marker.create();
    // TODO(asm 0xe073ec): the original calls sub_ca3dc4 (copy or rename) here and then deletes tmp/tmp2 when tmp still exists.
    await tmp.rename(path);
    if (marker.existsSync()) await marker.delete();
    if (tmp.existsSync()) await tmp.delete();
  }

  /// `_read` 0xe66eb0. A marker with its tmp file means a write finished but was not moved into place: tmp wins.
  /// TODO(asm 0xe66eb0): with a marker but no tmp the original returns null; the replica falls back to [path] (the move
  /// happened, only the marker deletion was lost).
  static Future<String> readFile(String path) async {
    final tmp = File('$path.tmp');
    final marker = File('$path.tmp2');
    if (marker.existsSync() && tmp.existsSync()) return tmp.readAsString();
    final f = File(path);
    if (f.existsSync()) return f.readAsString();
    return '';
  }
}
