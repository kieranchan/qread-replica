// storage/item.dart — `StorageItem`: the file-store keys that make up the synced "reading items" (cloud item `readitems`,
// docs/API.md). The original keeps the key list in `StorageItem.readitems` (static 0x4140) and, on upload (0x10e6c30), packs
// `{key: file content}` for each of them into one JSON map; on restore (0x10e6874) it writes every entry back.
import 'dart:convert';

import 'storage.dart';

abstract class StorageItem {
  /// Cloud item name.
  static const String cloudItem = 'readitems';

  /// File-store keys that belong to the reading items (per-book reading state the reader registers).
  static final List<String> readitems = <String>[];

  static void register(String key) {
    if (!readitems.contains(key)) readitems.add(key);
  }

  static void unregister(String key) => readitems.remove(key);

  /// JSON map `{key: content}` of every registered key that has content (what is uploaded as item `readitems`).
  static Future<String> export() async {
    final map = <String, String>{};
    for (final k in List<String>.of(readitems)) {
      final v = await Storage.read(k);
      if (v.isNotEmpty) map[k] = v;
    }
    return jsonEncode(map);
  }

  /// Writes an exported map back and registers its keys; returns how many entries were restored.
  /// Throws [FormatException] (`您还没有备份`) for empty input, like the original.
  static Future<int> import(String json) async {
    if (json.trim().isEmpty) throw const FormatException('您还没有备份');
    final v = jsonDecode(json);
    if (v is! Map) throw const FormatException('您还没有备份');
    var n = 0;
    for (final e in v.entries) {
      final value = e.value;
      if (value is! String) continue;
      await Storage.write('${e.key}', value);
      register('${e.key}');
      n++;
    }
    return n;
  }
}
