// data/fonts.dart — fonts the user imported for the reader. File-store key `fonts` (JSON list of [Font] {family, path}); the font
// files live in `<root>/fonts/`.
//
// Original: `FontsData` (static `_fonts` 0x38b8) and `Fonts` (operations under `_lock` 0x38a8). Adding a family that already
// exists throws `名称重复：<family>` (0xff4e24); save errors print `字体保存失败…` (0xff3d1c).
import 'dart:io';

import 'package:path/path.dart' as p;

import '../common/app_dirs.dart';
import '../models/font.dart';
import 'list_store.dart';

abstract class FontsData {
  static final ListStore<Font> store = ListStore<Font>(
    'fonts',
    fromJson: Font.fromJson,
    toJson: (f) => f.toJson(),
    label: '字体',
  );

  static List<Font> get fonts => store.items;

  static Future<List<Font>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  /// `<root>/fonts`.
  static Directory get directory => AppDirs.dir('fonts');

  /// The absolute path of a stored font file (the stored `path` may be a bare file name).
  static String filePath(Font f) => p.isAbsolute(f.path) ? f.path : p.join(directory.path, f.path);
}

abstract class Fonts {
  /// Registers a font. Throws [StateError] `名称重复：<family>` when the family is taken.
  static Future<void> add(Font font) => FontsData.store.run((list) {
        if (list.any((e) => e.family == font.family)) throw StateError('名称重复：${font.family}');
        list.add(Font.fromJson(font.toJson()));
      });

  /// Imports a font file: copies [source] into the fonts directory and registers it under [family].
  static Future<Font> importFile(String family, File source) async {
    await AppDirs.ensure('fonts');
    final name = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(source.path)}';
    final dest = p.join(FontsData.directory.path, name);
    final font = Font(family: family, path: name);
    await add(font); // fails on a duplicate name before anything is copied
    await source.copy(dest);
    return font;
  }

  /// Removes the font record and its file.
  static Future<void> remove(String family) => FontsData.store.run((list) async {
        final i = list.indexWhere((e) => e.family == family);
        if (i < 0) return;
        final f = list.removeAt(i);
        final file = File(FontsData.filePath(f));
        if (file.existsSync()) await file.delete();
      });

  static Font? byFamily(String family) {
    for (final f in FontsData.store.items) {
      if (f.family == family) return f;
    }
    return null;
  }
}
