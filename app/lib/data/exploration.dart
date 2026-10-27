// data/exploration.dart — discover-page templates ("发现" layouts built from components). File-store keys
// `exploration_templates` (JSON list of [ExplorationTemplate]) and `active_exploration_template_id` (string); cloud item
// `exploration_templates_backup` (docs/API.md "Item names").
//
// Original: `ExplorationData` (`_templates` 0x49c8; load 0x10daae0 reads both keys, 0x10da9fc adds md5(key) to `cleanwhite`) and
// `Exploration` (operations under `_lock` 0x49b8; create 0x1007de0 stamps createdAt/updatedAt with the current time; the
// active-template lookup 0x7b311c uses `firstWhere(..., orElse:)`).
import 'dart:convert';

import '../models/exploration_template.dart';
import '../storage/storage.dart';
import 'list_store.dart';

abstract class ExplorationData {
  static const String activeKey = 'active_exploration_template_id';
  static const String cloudItem = 'exploration_templates_backup';

  static final ListStore<ExplorationTemplate> store = ListStore<ExplorationTemplate>(
    'exploration_templates',
    fromJson: ExplorationTemplate.fromJson,
    toJson: (t) => t.toJson(),
    label: '发现模板',
  );

  static String _activeId = '';

  static List<ExplorationTemplate> get templates => store.items;

  static String get activeId => _activeId;

  static Future<List<ExplorationTemplate>> load({bool force = false}) async {
    if (store.loaded && !force) return store.items;
    Storage.keepOnClean(activeKey);
    final list = await store.load(force: force);
    _activeId = (await Storage.read(activeKey)).trim();
    return list;
  }

  static Future<bool> save() => store.save();

  static Future<void> _saveActive() => Storage.write(activeKey, _activeId);

  /// The active template: the one whose id is stored, else the first flagged `isActive`, else null.
  static ExplorationTemplate? get active {
    for (final t in store.items) {
      if (t.id == _activeId && _activeId.isNotEmpty) return t;
    }
    for (final t in store.items) {
      if (t.isActive) return t;
    }
    return null;
  }
}

abstract class Exploration {
  static String get _now => DateTime.now().toIso8601String();

  /// 0x1007de0: a new empty template named [name] (timestamps = now), stored and returned.
  static Future<ExplorationTemplate> create(String name, {List<dynamic>? components}) async {
    await ExplorationData.load();
    final t = ExplorationTemplate(
      id: newId(),
      name: name,
      components: components ?? <dynamic>[],
      createdAt: _now,
      updatedAt: _now,
    );
    await ExplorationData.store.run((list) => list.add(t));
    return t;
  }

  static Future<void> add(ExplorationTemplate t) async {
    await ExplorationData.load();
    await ExplorationData.store.run((list) {
      final copy = ExplorationTemplate.fromJson(t.toJson());
      if (copy.id.isEmpty || list.any((e) => e.id == copy.id)) copy.id = newId();
      if (copy.createdAt.isEmpty) copy.createdAt = _now;
      if (copy.updatedAt.isEmpty) copy.updatedAt = copy.createdAt;
      list.add(copy);
    });
  }

  /// Replaces the template with the same id and stamps `updatedAt`.
  static Future<void> update(ExplorationTemplate t) async {
    await ExplorationData.load();
    await ExplorationData.store.run((list) {
      final copy = ExplorationTemplate.fromJson(t.toJson())..updatedAt = _now;
      final i = list.indexWhere((e) => e.id == t.id);
      if (i < 0) {
        list.add(copy);
      } else {
        list[i] = copy;
      }
    });
  }

  static Future<void> delete(String id) async {
    await ExplorationData.load();
    await ExplorationData.store.run((list) => list.removeWhere((e) => e.id == id));
    if (ExplorationData._activeId == id) {
      ExplorationData._activeId = '';
      await ExplorationData._saveActive();
    }
  }

  /// Makes [id] the active template (and flags `isActive` accordingly); an unknown id clears the selection.
  static Future<void> setActive(String id) async {
    await ExplorationData.load();
    await ExplorationData.store.run((list) {
      final known = list.any((e) => e.id == id);
      ExplorationData._activeId = known ? id : '';
      for (final e in list) {
        e.isActive = known && e.id == id;
      }
    });
    await ExplorationData._saveActive();
  }

  /// All templates as JSON (cloud item / export).
  static String exportJson() => jsonEncode([for (final t in ExplorationData.store.items) t.toJson()]);

  /// Replaces the templates with an exported list; returns the count.
  static Future<int> importJson(String text) async {
    await ExplorationData.load();
    final v = jsonDecode(text);
    final raw = v is List ? v : const [];
    return ExplorationData.store.run((list) {
      list.clear();
      for (final m in raw) {
        if (m is Map) list.add(ExplorationTemplate.fromJson(Map<String, dynamic>.from(m)));
      }
      return list.length;
    });
  }
}
