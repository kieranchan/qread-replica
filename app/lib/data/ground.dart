// data/ground.dart — the user's reading backgrounds / page styles (`BackGround`: colours, margins, fonts, header/footer slots).
// File-store key `ground` (JSON list of [BackGround]); cloud item `ground` with md5 key `groundmd5`.
//
// Original: `Ground.grounds` (static 0x4a38; load 0x10dc6d4/0x10dc778, closures 0x1013ef0 / 0x101615c). A style is identified by its
// integer `name`.
import '../models/back_ground.dart';
import 'list_store.dart';

abstract class Ground {
  static final ListStore<BackGround> store = ListStore<BackGround>(
    'ground',
    fromJson: BackGround.fromJson,
    toJson: (b) => b.toJson(),
    label: '背景',
  );

  /// `Ground.grounds`.
  static List<BackGround> get grounds => store.items;

  static Future<List<BackGround>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  static BackGround? byName(int name) {
    for (final b in store.items) {
      if (b.name == name) return b;
    }
    return null;
  }

  /// Adds a style; a `name` of 0 (or one in use) is replaced by the next free number. Returns the stored copy.
  static Future<BackGround> add(BackGround style) => store.run((list) {
        final copy = BackGround.fromJson(style.toJson());
        if (copy.name == 0 || list.any((e) => e.name == copy.name)) {
          copy.name = list.isEmpty ? 1 : list.map((e) => e.name).reduce((a, b) => a > b ? a : b) + 1;
        }
        list.add(copy);
        return copy;
      });

  /// Replaces the style with the same `name` (appends when unknown).
  static Future<void> update(BackGround style) => store.run((list) {
        final copy = BackGround.fromJson(style.toJson());
        final i = list.indexWhere((e) => e.name == style.name);
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  static Future<void> delete(int name) => store.run((list) => list.removeWhere((e) => e.name == name));
}
