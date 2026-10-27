// data/tts.dart — the TTS engine list (HTTP engines the user imported, plus per-book multi-role voice setups).
// File-store key `tts` (JSON list of [HttpTts]); cloud item `tts_engines` (switch `cloudtts`, md5 key `ttsmd5`).
//
// Original: `TTSData` (`_tts` 0x3f78, `_de` 0x3f80 = the built-in default engine; load 0x10dbcfc adds md5("tts") to `cleanwhite`),
// `Tts` (operations under `_lock` 0x3f60; lookups by id / by `bookurl` 0x601d88 0x601de4 0x601e28 0x5ff094 0x6054d4) and
// `CloudTts` (pull of the cloud item 0xe6f474: `云端数据读取失败` when empty, `云端朗读引擎同步失败，请检查网络` on errors; md5 compare
// 0xe6f9dc via `getItemMd5`, message `一样不必同步`).
//
// An entry with an empty `bookurl` is a global engine; a non-empty `bookurl` marks the multi-role setup of that book
// (`narrationEngineId/VoiceId`, default male / female dialogue voice, `roles`). `html` holds the engine's HTTP definition
// (Legado HttpTTS keys: url, contentType, concurrentRate, loginUrl, loginUi, header, jsLib, enabledCookieJar, loginCheckJs ...).
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../models/httptts.dart';
import '../storage/storage.dart';
import 'cloud_api.dart';
import 'list_store.dart';

abstract class TTSData {
  static const String cloudItem = 'tts_engines';

  static final ListStore<HttpTts> store = ListStore<HttpTts>(
    'tts',
    fromJson: HttpTts.fromJson,
    toJson: (t) => t.toJson(),
    label: '朗读引擎',
  );

  /// `_de`: the system voice entry that is always available (cannot be deleted). TODO(asm 0x10dbcfc): the original's
  /// initializer of `_de` is not recovered; id/name are the replica's.
  static final HttpTts defaultEngine = HttpTts(id: 'system', name: '系统默认', candel: false);

  static List<HttpTts> get all => store.items;

  /// Global engines (no book bound).
  static List<HttpTts> get engines => [for (final t in store.items) if (t.bookurl.isEmpty) t];

  static Future<List<HttpTts>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  static HttpTts? byId(String id) {
    if (id == defaultEngine.id) return defaultEngine;
    for (final t in store.items) {
      if (t.id == id && t.bookurl.isEmpty) return t;
    }
    return null;
  }

  /// The multi-role setup stored for a book, null when none.
  static HttpTts? forBook(String bookUrl) {
    if (bookUrl.isEmpty) return null;
    for (final t in store.items) {
      if (t.bookurl == bookUrl) return t;
    }
    return null;
  }
}

abstract class Tts {
  /// Adds a global engine (fresh id when empty or taken); user engines can be deleted. Returns the stored copy.
  static Future<HttpTts> add(HttpTts engine) => TTSData.store.run((list) {
        final copy = HttpTts.fromJson(engine.toJson());
        if (copy.id.isEmpty || copy.id == TTSData.defaultEngine.id || list.any((e) => e.id == copy.id && e.bookurl == copy.bookurl)) {
          copy.id = newId();
        }
        copy.candel = true;
        list.add(copy);
        return copy;
      });

  /// Replaces the entry with the same id (and book) — appends when unknown.
  static Future<void> update(HttpTts engine) => TTSData.store.run((list) {
        final copy = HttpTts.fromJson(engine.toJson());
        final i = list.indexWhere((e) => e.id == engine.id && e.bookurl == engine.bookurl);
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  /// Removes a global engine unless it is protected (`candel` false); returns whether something was removed.
  static Future<bool> delete(String id) => TTSData.store.run((list) {
        final before = list.length;
        list.removeWhere((e) => e.id == id && e.bookurl.isEmpty && e.candel);
        return list.length != before;
      });

  /// Saves the multi-role setup of a book (one per `bookurl`).
  static Future<void> saveForBook(String bookUrl, HttpTts setup) => TTSData.store.run((list) {
        final copy = HttpTts.fromJson(setup.toJson())..bookurl = bookUrl;
        if (copy.id.isEmpty) copy.id = newId();
        final i = list.indexWhere((e) => e.bookurl == bookUrl);
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  static Future<void> deleteForBook(String bookUrl) => TTSData.store.run((list) => list.removeWhere((e) => e.bookurl == bookUrl));

  /// Imports Legado HttpTTS JSON (list or single object): each becomes a global engine whose `html` is the raw definition.
  /// Entries without a url are skipped; an engine with the same name is replaced. Returns the number stored.
  static Future<int> importJson(String text) async {
    final v = jsonDecode(text);
    final raw = v is List ? v : (v is Map ? [v] : const []);
    return TTSData.store.run((list) {
      var n = 0;
      for (final m in raw) {
        if (m is! Map) continue;
        final map = Map<String, dynamic>.from(m);
        final name = '${map['name'] ?? ''}'.trim();
        if (name.isEmpty || '${map['url'] ?? ''}'.trim().isEmpty) continue;
        final e = HttpTts(id: newId(), name: name, candel: true, html: map);
        final i = list.indexWhere((x) => x.bookurl.isEmpty && x.name == name);
        if (i >= 0) {
          e.id = list[i].id;
          list[i] = e;
        } else {
          list.add(e);
        }
        n++;
      }
      return n;
    });
  }

  /// The global engines as JSON (also the content of the cloud item).
  static String exportJson() => jsonEncode([for (final t in TTSData.engines) t.toJson()]);
}

abstract class CloudTts {
  /// md5 of the exported engines, the value stored under `ttsmd5` after a sync.
  static String localMd5() => crypto.md5.convert(utf8.encode(Tts.exportJson())).toString();

  /// Downloads the cloud item and merges it into the local list (same id: the cloud entry wins; others are added).
  /// Returns false without changing anything when the local md5 already equals the cloud md5 (`一样不必同步`); throws
  /// [StateError] `云端数据读取失败` when the cloud holds nothing.
  static Future<bool> pull({CloudApi? api}) async {
    final a = api ?? defaultCloudApi;
    await TTSData.load();
    final remoteMd5 = await a.getItemMd5(TTSData.cloudItem);
    if (remoteMd5.isNotEmpty && remoteMd5 == localMd5() && remoteMd5 == Storage.getString('ttsmd5')) return false;
    final text = await a.getItemJson(TTSData.cloudItem);
    if (text.isEmpty) throw StateError('云端数据读取失败');
    final v = jsonDecode(text);
    if (v is! List) throw StateError('云端数据读取失败');
    await TTSData.store.run((list) {
      for (final m in v) {
        if (m is! Map) continue;
        final r = HttpTts.fromJson(Map<String, dynamic>.from(m));
        if (r.bookurl.isNotEmpty) continue; // per-book setups are local
        final i = list.indexWhere((e) => e.id == r.id && e.bookurl.isEmpty);
        if (i < 0) {
          list.add(r);
        } else {
          list[i] = r;
        }
      }
    });
    await Storage.setString('ttsmd5', localMd5());
    return true;
  }

  /// Uploads the global engines as item `tts_engines`.
  static Future<void> push({CloudApi? api}) async {
    final a = api ?? defaultCloudApi;
    await TTSData.load();
    await a.setItemJsonFile(TTSData.cloudItem, Tts.exportJson());
    await Storage.setString('ttsmd5', localMd5());
  }
}
