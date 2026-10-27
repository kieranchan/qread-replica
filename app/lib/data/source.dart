// data/source.dart — the book-source store (书源). File-store key `source`: a JSON list with one object per source.
//
// The original shows sources through the small `Source` model (url, name, group, enabled, enabledExplore, login flags …) and keeps
// the full Legado definition in its source engine. The replica has no separate engine process, so every entry keeps its **full
// raw JSON map** (Legado keys: bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType, enabled, enabledExplore, header,
// loginUrl, exploreUrl, searchUrl, ruleSearch, ruleBookInfo, ruleToc, ruleContent, …). [Sourcedata.raw] hands the maps to the
// engine; [Sourcedata.sources] / [Sourcedata.byUrl] give the `Source` view.
//
// Original: `Sourcedata` (static `_sources` 0x3d78; load 0x10dba94, sync timer 0xe7658c `同步书源失败`) and `Sources` (operations
// under `_lock` 0x3d88):
//   add 0xe75974       copies the Source, normalises `bookSourceGroup` (split on `,`, drop empties, de-duplicate, join with `,`)
//   save 0xe76148      `Storage.write("source", …)`, error `书源保存失败…`, `获取云端信息失败` when the cloud etag is unusable
//   update-from-cloud 0xe77130 (`更新书源`)
//   group edit 0xf86dac / 0xf87d10 / 0xf88584 / 0xf88b28 (add / remove a group name on a set of sources)
//   enable flags 0xf8acf4 0xf8b074 (`enabled`) and 0xf89df4 0xf8a174 (`enabledExplore`)   delete 0xf8c698 0xf8c9f0 0xf8ce18
import 'dart:convert';

import '../models/source.dart';
import 'list_store.dart';

/// Normalises a comma separated group text: trims entries, drops empty ones and duplicates, keeps the first-seen order.
String normalizeGroups(String groups) {
  final seen = <String>{};
  final out = <String>[];
  for (final g in groups.split(RegExp('[,，;；]'))) {
    final t = g.trim();
    if (t.isNotEmpty && seen.add(t)) out.add(t);
  }
  return out.join(',');
}

abstract class Sourcedata {
  static final ListStore<Map<String, dynamic>> store = ListStore<Map<String, dynamic>>(
    'source',
    fromJson: (m) => Map<String, dynamic>.from(m),
    toJson: (m) => m,
    label: '书源',
  );

  /// The full raw JSON maps (live list; do not modify without going through [Sources]).
  static List<Map<String, dynamic>> get raw => store.items;

  /// The `Source` view of every entry.
  static List<Source> get sources => [for (final m in store.items) Source.fromJson(m)];

  static Future<List<Map<String, dynamic>>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  /// The raw map of the source with this `bookSourceUrl`, null when unknown.
  static Map<String, dynamic>? byUrl(String url) {
    for (final m in store.items) {
      if ('${m['bookSourceUrl']}' == url) return m;
    }
    return null;
  }

  static Source? sourceByUrl(String url) {
    final m = byUrl(url);
    return m == null ? null : Source.fromJson(m);
  }

  static bool _on(Object? v, {bool def = true}) => v == null ? def : (v is bool ? v : '$v' == 'true' || '$v' == '1');

  /// Enabled sources (Legado default for a missing flag is enabled).
  static List<Map<String, dynamic>> get enabledRaw => [for (final m in store.items) if (_on(m['enabled'])) m];

  /// Sources that provide a discover page: `enabledExplore` and a non-empty `exploreUrl`.
  static List<Map<String, dynamic>> get exploreRaw =>
      [for (final m in store.items) if (_on(m['enabled']) && _on(m['enabledExplore']) && '${m['exploreUrl'] ?? ''}'.trim().isNotEmpty) m];

  /// All group names (split from `bookSourceGroup`), sorted.
  static List<String> get groups {
    final set = <String>{};
    for (final m in store.items) {
      for (final g in '${m['bookSourceGroup'] ?? ''}'.split(',')) {
        if (g.trim().isNotEmpty) set.add(g.trim());
      }
    }
    return set.toList()..sort();
  }

  /// Sources of one group; `''` gives the sources without a group.
  static List<Map<String, dynamic>> ofGroup(String group) {
    return [
      for (final m in store.items)
        if (group.isEmpty ? '${m['bookSourceGroup'] ?? ''}'.trim().isEmpty : '${m['bookSourceGroup'] ?? ''}'.split(',').map((e) => e.trim()).contains(group)) m
    ];
  }
}

/// Result of an import / bulk add.
class SourceImportResult {
  final int added;
  final int updated;
  final int skipped;
  const SourceImportResult(this.added, this.updated, this.skipped);
  @override
  String toString() => 'added $added, updated $updated, skipped $skipped';
}

abstract class Sources {
  static String _url(Map<String, dynamic> m) => '${m['bookSourceUrl'] ?? ''}'.trim();

  /// A source needs a non-empty url and name to be stored.
  static bool isValid(Map<String, dynamic> m) => _url(m).isNotEmpty && '${m['bookSourceName'] ?? ''}'.trim().isNotEmpty;

  /// De-duplication key is `bookSourceUrl`.
  static Map<String, dynamic> _prepare(Map<String, dynamic> m) {
    final copy = Map<String, dynamic>.from(m);
    copy['bookSourceUrl'] = _url(m);
    copy['bookSourceGroup'] = normalizeGroups('${m['bookSourceGroup'] ?? ''}');
    copy['lastUpdateTime'] = m['lastUpdateTime'] ?? DateTime.now().millisecondsSinceEpoch;
    // Legado: a missing flag means enabled
    copy.putIfAbsent('enabled', () => true);
    copy.putIfAbsent('enabledExplore', () => true);
    return copy;
  }

  /// 0xe75974: stores [raw] (replacing a source with the same url, keeping its position). Returns true when it was new.
  static Future<bool> add(Map<String, dynamic> raw) => Sourcedata.store.run((list) {
        if (!isValid(raw)) throw const FormatException('书源缺少名称或地址');
        final copy = _prepare(raw);
        final i = list.indexWhere((e) => _url(e) == _url(copy));
        if (i >= 0) {
          list[i] = copy;
          return false;
        }
        list.add(copy);
        return true;
      });

  /// Bulk upsert; invalid entries are skipped.
  static Future<SourceImportResult> addAll(Iterable<Map<String, dynamic>> raws) => Sourcedata.store.run((list) {
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

  /// Replaces the source [oldUrl] (the url itself may change). Unknown urls are appended.
  static Future<void> update(String oldUrl, Map<String, dynamic> raw) => Sourcedata.store.run((list) {
        final copy = _prepare(raw);
        final i = list.indexWhere((e) => _url(e) == oldUrl);
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  /// 0xf8c698 …: removes the sources with these urls; returns how many were removed.
  static Future<int> delete(Iterable<String> urls) {
    final set = urls.toSet();
    return Sourcedata.store.run((list) {
      final before = list.length;
      list.removeWhere((e) => set.contains(_url(e)));
      return before - list.length;
    });
  }

  static Future<void> clear() => Sourcedata.store.run((list) => list.clear());

  /// 0xf8acf4 / 0xf8b074: `enabled` on a set of sources (all when [urls] is null).
  static Future<void> setEnabled(Iterable<String>? urls, bool enabled) {
    final set = urls?.toSet();
    return Sourcedata.store.run((list) {
      for (final e in list) {
        if (set == null || set.contains(_url(e))) e['enabled'] = enabled;
      }
    });
  }

  /// 0xf89df4 / 0xf8a174: `enabledExplore`.
  static Future<void> setEnabledExplore(Iterable<String>? urls, bool enabled) {
    final set = urls?.toSet();
    return Sourcedata.store.run((list) {
      for (final e in list) {
        if (set == null || set.contains(_url(e))) e['enabledExplore'] = enabled;
      }
    });
  }

  /// 0xf86dac / 0xf88584: adds [group] to the sources (normalising the group text).
  static Future<void> addGroup(Iterable<String> urls, String group) {
    final set = urls.toSet();
    final g = group.trim();
    return Sourcedata.store.run((list) {
      if (g.isEmpty) return;
      for (final e in list) {
        if (set.contains(_url(e))) e['bookSourceGroup'] = normalizeGroups('${e['bookSourceGroup'] ?? ''},$g');
      }
    });
  }

  /// 0xf87d10 / 0xf88b28: removes [group] from the sources.
  static Future<void> removeGroup(Iterable<String> urls, String group) {
    final set = urls.toSet();
    final g = group.trim();
    return Sourcedata.store.run((list) {
      for (final e in list) {
        if (!set.contains(_url(e))) continue;
        final rest = '${e['bookSourceGroup'] ?? ''}'.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && s != g);
        e['bookSourceGroup'] = normalizeGroups(rest.join(','));
      }
    });
  }

  /// Renames a group on every source that has it.
  static Future<void> renameGroup(String oldName, String newName) => Sourcedata.store.run((list) {
        for (final e in list) {
          final parts = '${e['bookSourceGroup'] ?? ''}'.split(',').map((s) => s.trim()).toList();
          if (!parts.contains(oldName)) continue;
          e['bookSourceGroup'] = normalizeGroups(parts.map((s) => s == oldName ? newName : s).join(','));
        }
      });

  /// Sets one key of the raw map (e.g. `respondTime`, `variableComment`, `loginUi`).
  static Future<void> setField(String url, String key, Object? value) => Sourcedata.store.run((list) {
        for (final e in list) {
          if (_url(e) == url) e[key] = value;
        }
      });

  /// Imports Legado book-source JSON: a list of sources or a single object. Entries without url or name are skipped.
  /// Throws [FormatException] when the text is not JSON.
  static Future<SourceImportResult> importJson(String text) async {
    final v = jsonDecode(text);
    final items = v is List ? v : (v is Map ? [v] : const []);
    return await addAll([for (final m in items) if (m is Map) Map<String, dynamic>.from(m)]);
  }

  /// Legado-compatible JSON of the given sources (all when [urls] is null): the full raw maps.
  static Future<String> exportJson({Iterable<String>? urls}) async {
    final list = await Sourcedata.load();
    final set = urls?.toSet();
    return const JsonEncoder.withIndent('  ').convert([for (final e in list) if (set == null || set.contains(_url(e))) e]);
  }
}
