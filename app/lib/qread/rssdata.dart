// qread/rssdata.dart — the RSS sources of the bound 轻阅读 backend, cached locally (`QRssSources`, `_lock` 0x4e48).
// Original: load 0xf1c7d8 (`开始获取rss`), `/getRssSourcessNew` 0xf1d12c (`md5`, `page`), save 0xf1d4fc (`rsssourcedata保存失败`).
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../common/lock.dart';
import '../models/rsssource.dart';
import '../storage/storage.dart';
import 'qread.dart';

/// One reply of the backend's RSS list.
class RssSourceMsg {
  final List<RssSource> sources;
  final String md5;
  const RssSourceMsg(this.sources, this.md5);
}

abstract class QRssSources {
  static const String key = 'rsssourcedata';
  static const String _md5Key = 'rsssourcedata_md5';
  static final Lock _lock = Lock();
  static List<RssSource> _sources = <RssSource>[];
  static bool _loaded = false;

  static List<RssSource> get sources => _sources;

  static void reset() {
    _sources = <RssSource>[];
    _loaded = false;
  }

  static Future<List<RssSource>> load({bool force = false}) async {
    if (_loaded && !force) return _sources;
    Storage.keepOnClean(key);
    _sources = [
      for (final e in Storage.jsondecode(await Storage.read(key)))
        if (e is Map) RssSource.fromJson(Map<String, dynamic>.from(e))
    ];
    _loaded = true;
    return _sources;
  }

  static String get md5 => Storage.getString(_md5Key);

  static Future<void> replace(RssSourceMsg msg) => _lock.synchronized(() async {
        _sources = List<RssSource>.of(msg.sources);
        _loaded = true;
        await Storage.setString(_md5Key, msg.md5);
        try {
          await Storage.write(key, jsonEncode([for (final s in _sources) s.toJson()]));
        } catch (e) {
          debugPrint('rsssourcedata保存失败 $e');
        }
      });

  /// Fetches every page from the backend (`开始获取rss`) and replaces the cache. Entries are marked `isqread`.
  static Future<List<RssSource>> refresh() async {
    debugPrint('开始获取rss');
    final all = <RssSource>[];
    var md5 = '';
    for (var p = 1; p <= 200; p++) {
      final data = await Qread.post('/getRssSourcessNew', {'md5': QRssSources.md5, 'page': p});
      var list = data;
      if (data is Map) {
        if ('${data['md5'] ?? ''}'.isNotEmpty) md5 = '${data['md5']}';
        list = data['list'] ?? data['data'];
      }
      if (list is String && list.trim().startsWith('[')) list = jsonDecode(list);
      final page = [for (final e in (list is List ? list : const [])) if (e is Map) RssSource.fromJson({...Map<String, dynamic>.from(e), 'isqread': true})];
      all.addAll(page);
      // TODO(asm 0xf1cbd4): paging contract inferred
      final more = data is Map ? (int.tryParse('${data['page'] ?? 0}') ?? 0) > p : false;
      if (page.isEmpty || !more) break;
    }
    await replace(RssSourceMsg(all, md5));
    return all;
  }

  static RssSource? byUrl(String url) {
    for (final s in _sources) {
      if (s.sourceUrl == url) return s;
    }
    return null;
  }
}
