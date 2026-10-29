// data/tts.dart — the TTS engine list (HTTP engines the user imported, plus per-book multi-role voice setups).
// File-store key `tts` (JSON list of [HttpTts]); cloud item `tts_engines` (switch `cloudtts`, md5 key `ttsmd5`).
//
// Original: `TTSData` (`_tts` 0x3f78, `_de` 0x3f80 = the built-in default engine; load 0x10dbcfc adds md5("tts") to `cleanwhite`),
// `Tts` (operations under `_lock` 0x3f60; lookups by id / by `bookurl` 0x601d88 0x601de4 0x601e28 0x5ff094 0x6054d4) and
// `CloudTts` (pull of the cloud item 0xe6f474: `云端数据读取失败` when empty, `云端朗读引擎同步失败，请检查网络` on errors; md5 compare
// 0xe6f9dc via `getItemMd5`, message `一样不必同步`).
//
// An entry with an empty `bookurl` is a global engine; a non-empty `bookurl` marks the multi-role setup of that book
// (`narrationEngineId/VoiceId`, default male / female dialogue voice, `roles`).
// `tp` (0x1c3158 / 0xe6e2dc): 0 = normal engine, 1 = multi-role engine (its `html` is the JSON of the role setup). In the original
// `html` is a String: the engine's HTML page with `getttsurl()` (util/audio/tts_page.dart). The generated model keeps `html` as a
// Map, so the replica stores the page as `html['page']`; older replica engines hold a Legado HttpTTS definition (url, contentType,
// header, ...) in the map instead, and those still run through util/audio/http_tts.dart.
// System entries: `_de` of the original (0x1c3800) is `dsld` / `大声朗读(系统默认无法选择)` = the Edge voice through
// `http://tts.qread.xyz/edge.html`, a page of the original's own service, which the replica does not reproduce; the engine pickers
// (0x1096d3c) start with `HttpTts(id: '', name: '系统默认')`, the system voice, which is [TTSData.defaultEngine] here.
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

  /// The system voice entry of the engine pickers (0x1096d3c: id `''`, name `系统默认`); always available, never stored.
  static final HttpTts defaultEngine = HttpTts(id: '', name: '系统默认', candel: false);

  /// The id earlier replica builds used for [defaultEngine] (still accepted by [byId]).
  static const String legacySystemId = 'system';

  /// The engine's HTML page (`getttsurl`), '' for Legado-style or multi-role entries.
  static String pageOf(HttpTts e) {
    final p = e.html['page'];
    return p is String ? p : '';
  }

  static List<HttpTts> get all => store.items;

  /// Global engines (no book bound).
  static List<HttpTts> get engines => [for (final t in store.items) if (t.bookurl.isEmpty) t];

  static Future<List<HttpTts>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  static HttpTts? byId(String id) {
    if (id == defaultEngine.id || id == legacySystemId) return defaultEngine;
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

  /// One engine of the original's own export (`HttpTts.toJson`: `html` a String, `tp` 0/1) in the replica's shape; null when [m]
  /// is not one.
  static HttpTts? fromOriginal(Map<String, dynamic> m) {
    final html = m['html'];
    if (html is! String || !m.containsKey('tp')) return null;
    final copy = Map<String, dynamic>.from(m)..remove('html');
    final e = HttpTts.fromJson(copy);
    if (e.tp == 1) {
      try {
        final cfg = jsonDecode(html);
        if (cfg is Map) e.html = Map<String, dynamic>.from(cfg);
      } catch (_) {}
    } else {
      e.html = {'page': html};
    }
    return e;
  }

  /// Imports engines: the original's export (pages, see [fromOriginal]) or Legado HttpTTS JSON (list or single object; each
  /// becomes a global engine whose `html` is the raw definition). Entries without a page / url are skipped; an engine with the
  /// same name is replaced. Returns the number stored.
  static Future<int> importJson(String text) async {
    final v = jsonDecode(text);
    final raw = v is List ? v : (v is Map ? [v] : const []);
    return TTSData.store.run((list) {
      var n = 0;
      for (final m in raw) {
        if (m is! Map) continue;
        final map = Map<String, dynamic>.from(m);
        final name = '${map['name'] ?? ''}'.trim();
        final orig = fromOriginal(map);
        if (name.isEmpty || (orig == null && '${map['url'] ?? ''}'.trim().isEmpty)) continue;
        if (orig != null && orig.tp != 1 && TTSData.pageOf(orig).trim().isEmpty) continue;
        final e = orig ?? HttpTts(id: newId(), name: name, candel: true, html: map);
        e
          ..id = newId()
          ..bookurl = ''
          ..candel = true;
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

  /// One engine in the original's format (`html` a String: the page, or the role setup JSON for `tp == 1`).
  static Map<String, dynamic> toOriginal(HttpTts e) {
    final j = e.toJson();
    j['html'] = e.tp == 1 ? jsonEncode(e.html) : (TTSData.pageOf(e).isNotEmpty ? TTSData.pageOf(e) : jsonEncode(e.html));
    return j;
  }
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

  /// The 云端朗读引擎 sync of 云端设置 (switch-on merge and 开始同步): the cloud copy is merged in when there is one, else the local
  /// engines are uploaded (the original: `打开时本地引擎与云端按名称合并…开启后以云端为准同步`). True when something changed.
  static Future<bool> sync({CloudApi? api}) async {
    final a = api ?? defaultCloudApi;
    final text = await a.getItemJson(TTSData.cloudItem);
    if (text.isEmpty) {
      await push(api: a);
      return true;
    }
    return pull(api: a);
  }

  /// Uploads the global engines as item `tts_engines`.
  static Future<void> push({CloudApi? api}) async {
    final a = api ?? defaultCloudApi;
    await TTSData.load();
    await a.setItemJsonFile(TTSData.cloudItem, Tts.exportJson());
    await Storage.setString('ttsmd5', localMd5());
  }
}
