// data/rss.dart — RSS sources (订阅源). File-store key `rss2`: JSON list, one object per source.
//
// Like the book sources, every entry keeps its **full raw JSON map** (Legado RSS keys: sourceUrl, sourceName, sourceIcon,
// sourceGroup, enabled, sortUrl, ruleArticles, ruleTitle, ruleLink, …; the original's `RssSource.json` field is the same text).
// `RssSource.fromJson` gives the small view.
//
// Original: `Rssdata` (static `_rsssources` 0x4080, sync timer 0x1c5590) and `RssSources` (operations under `_lock` 0x40a0):
// add 0xe72484 (save with key `rss2`), cloud update 0xe730c8/0xe73348 (`更新订阅源`), then closures for enable flags, group edits,
// delete and replace. Cloud list `getBRss` (etag `rsstag`, md5 `rssmd5`).
import 'dart:convert';

import '../models/rsssource.dart';
import 'list_store.dart';
import 'source.dart' show SourceImportResult, normalizeGroups;

abstract class Rssdata {
  static final ListStore<Map<String, dynamic>> store = ListStore<Map<String, dynamic>>(
    'rss2',
    fromJson: (m) => Map<String, dynamic>.from(m),
    toJson: (m) => m,
    label: '订阅源',
  );

  static List<Map<String, dynamic>> get raw => store.items;

  static List<RssSource> get sources => [for (final m in store.items) RssSource.fromJson(m)];

  static Future<List<Map<String, dynamic>>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  static Map<String, dynamic>? byUrl(String url) {
    for (final m in store.items) {
      if ('${m['sourceUrl']}' == url) return m;
    }
    return null;
  }

  static bool _on(Object? v) => v == null ? true : (v is bool ? v : '$v' == 'true' || '$v' == '1');

  static List<Map<String, dynamic>> get enabledRaw => [for (final m in store.items) if (_on(m['enabled'])) m];

  static List<String> get groups {
    final set = <String>{};
    for (final m in store.items) {
      for (final g in '${m['sourceGroup'] ?? ''}'.split(',')) {
        if (g.trim().isNotEmpty) set.add(g.trim());
      }
    }
    return set.toList()..sort();
  }

  static List<Map<String, dynamic>> ofGroup(String group) {
    return [
      for (final m in store.items)
        if (group.isEmpty ? '${m['sourceGroup'] ?? ''}'.trim().isEmpty : '${m['sourceGroup'] ?? ''}'.split(',').map((e) => e.trim()).contains(group)) m
    ];
  }
}

abstract class RssSources {
  static String _url(Map<String, dynamic> m) => '${m['sourceUrl'] ?? ''}'.trim();

  static bool isValid(Map<String, dynamic> m) => _url(m).isNotEmpty && '${m['sourceName'] ?? ''}'.trim().isNotEmpty;

  static Map<String, dynamic> _prepare(Map<String, dynamic> m) {
    final copy = Map<String, dynamic>.from(m);
    copy['sourceUrl'] = _url(m);
    copy['sourceGroup'] = normalizeGroups('${m['sourceGroup'] ?? ''}');
    copy['lastUpdateTime'] = m['lastUpdateTime'] ?? DateTime.now().millisecondsSinceEpoch;
    copy.putIfAbsent('enabled', () => true);
    return copy;
  }

  /// Upsert by `sourceUrl`; true when new.
  static Future<bool> add(Map<String, dynamic> raw) => Rssdata.store.run((list) {
        if (!isValid(raw)) throw const FormatException('订阅源缺少名称或地址');
        final copy = _prepare(raw);
        final i = list.indexWhere((e) => _url(e) == _url(copy));
        if (i >= 0) {
          list[i] = copy;
          return false;
        }
        list.add(copy);
        return true;
      });

  static Future<SourceImportResult> addAll(Iterable<Map<String, dynamic>> raws) => Rssdata.store.run((list) {
        var added = 0, updated = 0, skipped = 0;
        for (final raw in raws) {
          if (!isValid(raw)) {
            skipped++;
            continue;
          }
          final copy = _prepare(raw);
          final i = list.indexWhere((e) => _url(e) == _url(copy));
          if (i >= 0) {
            list[i] = copy;
            updated++;
          } else {
            list.add(copy);
            added++;
          }
        }
        return SourceImportResult(added, updated, skipped);
      });

  static Future<void> update(String oldUrl, Map<String, dynamic> raw) => Rssdata.store.run((list) {
        final copy = _prepare(raw);
        final i = list.indexWhere((e) => _url(e) == oldUrl);
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  static Future<int> delete(Iterable<String> urls) {
    final set = urls.toSet();
    return Rssdata.store.run((list) {
      final before = list.length;
      list.removeWhere((e) => set.contains(_url(e)));
      return before - list.length;
    });
  }

  static Future<void> clear() => Rssdata.store.run((list) => list.clear());

  static Future<void> setEnabled(Iterable<String>? urls, bool enabled) {
    final set = urls?.toSet();
    return Rssdata.store.run((list) {
      for (final e in list) {
        if (set == null || set.contains(_url(e))) e['enabled'] = enabled;
      }
    });
  }

  static Future<void> addGroup(Iterable<String> urls, String group) {
    final set = urls.toSet();
    final g = group.trim();
    return Rssdata.store.run((list) {
      if (g.isEmpty) return;
      for (final e in list) {
        if (set.contains(_url(e))) e['sourceGroup'] = normalizeGroups('${e['sourceGroup'] ?? ''},$g');
      }
    });
  }

  static Future<void> removeGroup(Iterable<String> urls, String group) {
    final set = urls.toSet();
    final g = group.trim();
    return Rssdata.store.run((list) {
      for (final e in list) {
        if (!set.contains(_url(e))) continue;
        final rest = '${e['sourceGroup'] ?? ''}'.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && s != g);
        e['sourceGroup'] = normalizeGroups(rest.join(','));
      }
    });
  }

  static Future<void> setField(String url, String key, Object? value) => Rssdata.store.run((list) {
        for (final e in list) {
          if (_url(e) == url) e[key] = value;
        }
      });

  /// Imports Legado RSS-source JSON (list or single object).
  static Future<SourceImportResult> importJson(String text) async {
    final v = jsonDecode(text);
    final items = v is List ? v : (v is Map ? [v] : const []);
    return await addAll([for (final m in items) if (m is Map) Map<String, dynamic>.from(m)]);
  }

  static Future<String> exportJson({Iterable<String>? urls}) async {
    final list = await Rssdata.load();
    final set = urls?.toSet();
    return const JsonEncoder.withIndent('  ').convert([for (final e in list) if (set == null || set.contains(_url(e))) e]);
  }
}
