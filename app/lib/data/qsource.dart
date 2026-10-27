// data/qsource.dart — the source list of the bound 轻阅读 (Legado-compatible) backend, cached locally. File-store key `sourcedata`.
//
// Original: `QSources` (`_lock` 0x4a78). It asks the backend for its book sources (`/getBookSourcesPage` with `oldmd5`, then
// `/getBookSourcesNew`; reply `{isSuccess, data, page, md5, errorMsg}`), wraps them in `SourceMsg {sources, md5}` and stores the
// list under `sourcedata` (save 0xf1bd88, error text `sourcedata保存失败`). The network part belongs to the bound-backend client
// (`lib/qread/`); this file is the cache plus the md5 the next request sends as `oldmd5`.
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../common/lock.dart';
import '../models/source.dart';
import '../storage/storage.dart';

/// One reply of the backend's source list: the sources of the page and the md5 of the whole list.
class SourceMsg {
  final List<Source> sources;
  final String md5;
  const SourceMsg(this.sources, this.md5);
}

abstract class QSources {
  static const String key = 'sourcedata';
  static const String _md5Key = 'sourcedata_md5';

  static final Lock _lock = Lock();
  static List<Source> _sources = <Source>[];
  static bool _loaded = false;

  static List<Source> get sources => _sources;

  /// Forgets the loaded state (tests, logout).
  static void reset() {
    _sources = <Source>[];
    _loaded = false;
  }

  /// Loads the cached list (idempotent).
  static Future<List<Source>> load({bool force = false}) async {
    if (_loaded && !force) return _sources;
    Storage.keepOnClean(key);
    final out = <Source>[];
    for (final e in Storage.jsondecode(await Storage.read(key))) {
      if (e is Map) out.add(Source.fromJson(Map<String, dynamic>.from(e)));
    }
    _sources = out;
    _loaded = true;
    return _sources;
  }

  /// The md5 of the cached list (sent as `oldmd5`), `''` when nothing is cached.
  static String get md5 => Storage.getString(_md5Key);

  /// Replaces the cache with a backend reply.
  static Future<void> replace(SourceMsg msg) => _lock.synchronized(() async {
        await load();
        _sources = List<Source>.of(msg.sources);
        await Storage.setString(_md5Key, msg.md5);
        await _save();
      });

  static Future<void> clear() => _lock.synchronized(() async {
        _sources = <Source>[];
        _loaded = true;
        await Storage.remove(_md5Key);
        await _save();
      });

  static Source? byUrl(String url) {
    for (final s in _sources) {
      if (s.bookSourceUrl == url) return s;
    }
    return null;
  }

  static Future<void> _save() async {
    try {
      await Storage.write(key, jsonEncode([for (final s in _sources) s.toJson()]));
    } catch (e) {
      debugPrint('sourcedata保存失败 $e');
    }
  }
}
