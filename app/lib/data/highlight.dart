// data/highlight.dart — text highlight rules of the reader (pattern -> colour / background / font tweaks).
// File-store key `highlightRules` (JSON list of [HighlightRule]); `highlightRulesMd5` is the prefs key of the last synced md5.
//
// Original: `HighlightData` (static `_rules` 0x4a48, load 0x10dc0cc/0x10dc180) and `Highlights` (operations under `_lock`
// 0x4a50; save 0xff044c, `getRules`-style readers 0xff0574 / 0xff0688). Rules are applied in list order.
import 'dart:convert';

import '../models/highlight_rule.dart';
import 'list_store.dart';

abstract class HighlightData {
  static final ListStore<HighlightRule> store = ListStore<HighlightRule>(
    'highlightRules',
    fromJson: HighlightRule.fromJson,
    toJson: (r) => r.toJson(),
    label: '高亮规则',
  );

  static List<HighlightRule> get rules => store.items;

  static Future<List<HighlightRule>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  /// Enabled rules with a pattern, in list order.
  static List<HighlightRule> get enabled => [for (final r in store.items) if (r.isEnabled && r.pattern.isNotEmpty) r];

  /// Rule patterns that are not valid regular expressions are skipped by callers; this tells which are usable.
  static bool isValid(HighlightRule r) {
    if (r.pattern.isEmpty) return false;
    if (!r.isRegex) return true;
    try {
      RegExp(r.pattern);
      return true;
    } on FormatException {
      return false;
    }
  }
}

abstract class Highlights {
  /// Appends a copy with a fresh id when [rule] has none (or its id is taken).
  static Future<HighlightRule> add(HighlightRule rule) => HighlightData.store.run((list) {
        final copy = HighlightRule.fromJson(rule.toJson());
        if (copy.id.isEmpty || list.any((e) => e.id == copy.id)) copy.id = newId();
        list.add(copy);
        return copy;
      });

  static Future<void> update(HighlightRule rule) => HighlightData.store.run((list) {
        final i = list.indexWhere((e) => e.id == rule.id);
        final copy = HighlightRule.fromJson(rule.toJson());
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  static Future<void> delete(String id) => HighlightData.store.run((list) => list.removeWhere((e) => e.id == id));

  static Future<void> deleteMany(Iterable<String> ids) {
    final set = ids.toSet();
    return HighlightData.store.run((list) => list.removeWhere((e) => set.contains(e.id)));
  }

  static Future<void> setEnabled(String id, bool enabled) => HighlightData.store.run((list) {
        for (final e in list) {
          if (e.id == id) e.isEnabled = enabled;
        }
      });

  static Future<void> setAllEnabled(bool enabled) => HighlightData.store.run((list) {
        for (final e in list) {
          e.isEnabled = enabled;
        }
      });

  /// Moves the rule up/down by [delta] places (negative = towards the front).
  static Future<void> move(String id, int delta) => HighlightData.store.run((list) {
        final i = list.indexWhere((e) => e.id == id);
        if (i < 0) return;
        final j = (i + delta).clamp(0, list.length - 1);
        if (j != i) list.insert(j, list.removeAt(i));
      });

  /// Imports a JSON list (this app's export format); rules with the same name+pattern are skipped. Returns the number added.
  static Future<int> importJson(String text) async {
    final v = jsonDecode(text);
    final raw = v is List ? v : (v is Map ? [v] : const []);
    return HighlightData.store.run((list) {
      var n = 0;
      for (final m in raw) {
        if (m is! Map) continue;
        final r = HighlightRule.fromJson(Map<String, dynamic>.from(m));
        if (r.pattern.isEmpty) continue;
        if (list.any((e) => e.name == r.name && e.pattern == r.pattern)) continue;
        if (r.id.isEmpty || list.any((e) => e.id == r.id)) r.id = newId();
        list.add(r);
        n++;
      }
      return n;
    });
  }

  static Future<String> exportJson({Iterable<String>? ids}) async {
    final list = await HighlightData.load();
    final set = ids?.toSet();
    return jsonEncode([for (final r in list) if (set == null || set.contains(r.id)) r.toJson()]);
  }
}
