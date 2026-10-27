// data/txtrule.dart — TXT chapter-title ("目录") rules. File-store key `txt_toc_rule`.
//
// Original: `Txtruledata` (static `_rules` 0x4ad8; load 0x10dbe44: `Storage.read("txt_toc_rule")`, `""` -> defaults, decode,
// an empty result also gives the defaults `TxtTocRule.detxtTocRules`) and `Txtrule` (operations under `_lock` 0x4ae0; save
// 0xe6bea4 prints `目录规则保存失败…` on error). The first built-in rule cannot be deleted (`candel` false).
import 'dart:convert';

import '../models/txt_toc_rule.dart';
import 'list_store.dart';

abstract class Txtruledata {
  static final ListStore<TxtTocRule> store = ListStore<TxtTocRule>(
    'txt_toc_rule',
    fromJson: TxtTocRule.fromJson,
    toJson: (r) => r.toJson(),
    defaults: TxtTocRule.defaults,
    label: '目录规则',
  );

  /// The current rules (the built-in list until the user changes something and saves).
  static List<TxtTocRule> get rules => store.items;

  static Future<List<TxtTocRule>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  /// The enabled rules the reader tries when it splits a TXT file into chapters, in list order.
  static List<TxtTocRule> get enabled => [for (final r in store.items) if (r.isEnabled && r.rule.isNotEmpty) r];
}

abstract class Txtrule {
  /// Appends a rule (user rules can be deleted). Rules are identified by name: a rule with the same name is replaced.
  static Future<void> add(TxtTocRule rule) => Txtruledata.store.run((list) {
        final copy = TxtTocRule(name: rule.name, rule: rule.rule, candel: true, isEnabled: rule.isEnabled);
        final i = list.indexWhere((e) => e.name == copy.name);
        if (i >= 0 && list[i].candel) {
          list[i] = copy;
        } else if (i < 0) {
          list.add(copy);
        }
      });

  /// Edits the rule called [oldName]; built-in rules that cannot be deleted keep their text.
  static Future<void> update(String oldName, TxtTocRule rule) => Txtruledata.store.run((list) {
        final i = list.indexWhere((e) => e.name == oldName);
        if (i < 0) return;
        if (!list[i].candel) {
          list[i].isEnabled = rule.isEnabled;
          return;
        }
        list[i] = TxtTocRule(name: rule.name, rule: rule.rule, candel: true, isEnabled: rule.isEnabled);
      });

  /// Deletes the rule called [name] unless it is protected; returns whether something was removed.
  static Future<bool> delete(String name) => Txtruledata.store.run((list) {
        final before = list.length;
        list.removeWhere((e) => e.name == name && e.candel);
        return list.length != before;
      });

  static Future<void> setEnabled(String name, bool enabled) => Txtruledata.store.run((list) {
        for (final e in list) {
          if (e.name == name) e.isEnabled = enabled;
        }
      });

  /// Moves the rule to the front (rules are tried in list order).
  static Future<void> moveToTop(String name) => Txtruledata.store.run((list) {
        final i = list.indexWhere((e) => e.name == name);
        if (i > 0) list.insert(0, list.removeAt(i));
      });

  /// Back to the built-in list.
  static Future<void> reset() => Txtruledata.store.run((list) {
        list
          ..clear()
          ..addAll(TxtTocRule.defaults());
      });

  /// Imports Legado's `txtTocRule.json` (`[{"name","rule","enable","serialNumber"}]`) or this app's export. Existing names are
  /// updated, new names appended; returns the number of rules added or changed.
  static Future<int> importJson(String text) async {
    final v = jsonDecode(text);
    final raw = v is List ? v : (v is Map ? [v] : const []);
    return Txtruledata.store.run((list) {
      var n = 0;
      for (final m in raw) {
        if (m is! Map) continue;
        final map = Map<String, dynamic>.from(m);
        map['isEnabled'] ??= map['enable'];
        final r = TxtTocRule.fromJson(map);
        if (r.name.isEmpty || r.rule.isEmpty) continue;
        final i = list.indexWhere((e) => e.name == r.name);
        if (i >= 0) {
          if (!list[i].candel || (list[i].rule == r.rule && list[i].isEnabled == r.isEnabled)) continue;
          list[i] = TxtTocRule(name: r.name, rule: r.rule, candel: true, isEnabled: r.isEnabled);
        } else {
          list.add(TxtTocRule(name: r.name, rule: r.rule, candel: true, isEnabled: map['isEnabled'] == null ? true : r.isEnabled));
        }
        n++;
      }
      return n;
    });
  }

  static Future<String> exportJson() async {
    final list = await Txtruledata.load();
    return jsonEncode([for (final r in list) r.toJson()]);
  }
}
