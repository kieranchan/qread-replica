// data/replace.dart — replace rules (净化/替换规则). File-store key `replaces` (JSON list of [ReplaceRule]).
//
// Original: `ReplaceData` (static `_rules` 0x4aa0, load 0x10dc3d0/0x10dc484) and `Replaces` (operations under `_lock` 0x4a80):
//   add 0xe70844  (copies the rule, assigns a fresh uuid id and the next `ruleorder`, appends)
//   set enabled 0xed763c / 0xfdce68 / 0xfdd098 / 0xfde0f4  (find by id, set `isEnabled`)
//   remove 0xfdd4d0 / 0xfdd8c4 / 0x101daf0   replace (remove by id, then add) 0x101dd10
// The reader applies the enabled rules in `ruleorder` order to titles / content of the books they are scoped to.
import 'dart:convert';

import '../models/replacerule.dart';
import 'list_store.dart';

abstract class ReplaceData {
  static final ListStore<ReplaceRule> store = ListStore<ReplaceRule>(
    'replaces',
    fromJson: ReplaceRule.fromJson,
    toJson: (r) => r.toJson(),
    label: '替换规则',
  );

  static List<ReplaceRule> get rules => store.items;

  static Future<List<ReplaceRule>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  /// The enabled rules in `ruleorder` order that apply to a book ([bookName], source/[origin] url). [forTitle] picks the
  /// rules scoped to titles, otherwise those scoped to content. Rules with neither flag set apply to content only.
  static List<ReplaceRule> forBook({required String bookName, String origin = '', bool forTitle = false}) {
    final list = store.items.where((r) {
      if (!r.isEnabled || r.pattern.isEmpty) return false;
      if (!appliesTo(r, bookName, origin)) return false;
      return forTitle ? r.scopeTitle : (r.scopeContent || !r.scopeTitle);
    }).toList();
    list.sort((a, b) => a.ruleorder.compareTo(b.ruleorder));
    return list;
  }

  /// `scope` / `excludeScope` are lists (separated by `,` or `;`) of book names and source urls; empty scope = everything.
  static bool appliesTo(ReplaceRule r, String bookName, String origin) {
    bool hit(String scope) {
      if (scope.trim().isEmpty) return false;
      return scope.split(RegExp('[,;]')).map((s) => s.trim()).where((s) => s.isNotEmpty).any((s) => s == bookName || s == origin);
    }

    if (hit(r.excludeScope)) return false;
    if (r.scope.trim().isEmpty) return true;
    return hit(r.scope);
  }
}

abstract class Replaces {
  /// 0xe70844. The stored copy gets a new id (when empty) and the next order number.
  static Future<ReplaceRule> add(ReplaceRule rule) => ReplaceData.store.run((list) {
        final copy = ReplaceRule.fromJson(rule.toJson());
        if (copy.id.isEmpty || list.any((e) => e.id == copy.id)) copy.id = newId();
        copy.ruleorder = list.isEmpty ? 1 : list.map((e) => e.ruleorder).reduce((a, b) => a > b ? a : b) + 1;
        list.add(copy);
        return copy;
      });

  /// 0x101dd10: replaces the rule with the same id (appends it when unknown).
  static Future<void> update(ReplaceRule rule) => ReplaceData.store.run((list) {
        final i = list.indexWhere((e) => e.id == rule.id);
        final copy = ReplaceRule.fromJson(rule.toJson());
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  static Future<void> delete(String id) => ReplaceData.store.run((list) => list.removeWhere((e) => e.id == id));

  static Future<void> deleteMany(Iterable<String> ids) {
    final set = ids.toSet();
    return ReplaceData.store.run((list) => list.removeWhere((e) => set.contains(e.id)));
  }

  static Future<void> setEnabled(String id, bool enabled) => ReplaceData.store.run((list) {
        for (final e in list) {
          if (e.id == id) e.isEnabled = enabled;
        }
      });

  static Future<void> setAllEnabled(bool enabled) => ReplaceData.store.run((list) {
        for (final e in list) {
          e.isEnabled = enabled;
        }
      });

  /// Moves the rule in front of all others (smallest `ruleorder` - 1).
  static Future<void> moveToTop(String id) => ReplaceData.store.run((list) {
        if (list.isEmpty) return;
        final min = list.map((e) => e.ruleorder).reduce((a, b) => a < b ? a : b);
        for (final e in list) {
          if (e.id == id) e.ruleorder = min - 1;
        }
      });

  /// Imports Legado-style replace rules (`[{"name","group","pattern","replacement","scope","scopeTitle","scopeContent",
  /// "excludeScope","isEnabled","isRegex","timeoutMillisecond","order"}]`, a single object also works) as well as this app's
  /// own export. Rules whose (name, pattern, replacement) already exist are skipped. Returns how many were added.
  static Future<int> importJson(String text) async {
    final v = jsonDecode(text);
    final raw = v is List ? v : (v is Map ? [v] : const []);
    return ReplaceData.store.run((list) {
      var n = 0;
      var order = list.isEmpty ? 0 : list.map((e) => e.ruleorder).reduce((a, b) => a > b ? a : b);
      for (final m in raw) {
        if (m is! Map) continue;
        final map = Map<String, dynamic>.from(m);
        map['groupname'] ??= map['group'];
        map['ruleorder'] ??= map['order'];
        map['id'] = '${map['id'] ?? ''}';
        final r = ReplaceRule.fromJson(map);
        if (r.pattern.isEmpty) continue;
        if (list.any((e) => e.name == r.name && e.pattern == r.pattern && e.replacement == r.replacement)) continue;
        if (r.id.isEmpty || r.id == '0' || list.any((e) => e.id == r.id)) r.id = newId();
        order += 1;
        if (map['ruleorder'] == null) r.ruleorder = order;
        list.add(r);
        n++;
      }
      return n;
    });
  }

  /// The rules as JSON text (this app's own format: the model's keys).
  static Future<String> exportJson({Iterable<String>? ids}) async {
    final list = await ReplaceData.load();
    final set = ids?.toSet();
    return jsonEncode([for (final r in list) if (set == null || set.contains(r.id)) r.toJson()]);
  }
}
