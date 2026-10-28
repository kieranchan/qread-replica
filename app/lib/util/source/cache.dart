// util/source/cache.dart — `Cache` (class 1233): the key/value store behind the page's `cache.*` handlers and the book variables of
// 时光源 (「设置书籍变量」 0xf709ac writes `Cache(<bookSourceUrl>).set(<bookUrl>, value)`).
//
// Original layout (0xe5fdd4 create, 0xe5fe40 init, 0xe60798 get `cache get `/`不存在: `, 0xe5fb7c set `保存失败: `, 0xe60b68 remove
// `cache remove `/`删除失败: `): one text file per key, `<documents>/cache/<md5(name)>/<md5(key)>.txt` (static 0x1d08 = "cache");
// `name` is the source's `bookSourceUrl`, or `all` for the `cache.all*` handlers shared by every source.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../common/app_dirs.dart';

class Cache {
  /// Namespace shared by all sources (`cache.allget` / `cache.allset` / `cache.allremove`).
  static const String all = 'all';

  final String name;
  const Cache(this.name);

  static String _md5(String s) => crypto.md5.convert(utf8.encode(s)).toString();

  Future<Directory> _dir() async {
    if (!AppDirs.hasRoot) await AppDirs.init();
    final d = Directory(p.join(AppDirs.root.path, 'cache', _md5(name)));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String key) async => File(p.join((await _dir()).path, '${_md5(key)}.txt'));

  /// The stored text, '' when there is none.
  Future<String> get(String key) async {
    try {
      final f = await _file(key);
      if (!await f.exists()) return '';
      return await f.readAsString();
    } catch (e) {
      debugPrint('cache get $key: $e');
      return '';
    }
  }

  Future<void> set(String key, String value) async {
    try {
      await (await _file(key)).writeAsString(value, flush: true);
    } catch (e) {
      debugPrint('保存失败: $key, 错误: $e');
    }
  }

  Future<void> remove(String key) async {
    try {
      final f = await _file(key);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('删除失败: $key, 错误: $e');
    }
  }

  /// Removes every key of this namespace (the editor's 清除缓存 `是否要清理当前书源所有的cache？`).
  Future<void> clear() async {
    try {
      final d = await _dir();
      if (await d.exists()) await d.delete(recursive: true);
    } catch (e) {
      debugPrint('清除缓存失败: $e');
    }
  }
}
