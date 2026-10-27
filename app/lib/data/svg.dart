// data/svg.dart — user SVG icon sets (replace the reader menu's icons). File-store key `svg` (JSON list of [Svgimage] {id, svg});
// cloud item `svg` with md5 key `svgmd5`.
//
// Original: `Svg` (`_svgs` 0x4ab8, `desvgs` 0x4ac0 = the defaults used when nothing is stored, `_lock` 0x4aa8; load 0x10db80c:
// empty result -> `desvgs`). TODO(asm 0x10db80c): the contents of `desvgs` come from a static initializer that is not in the
// decompiled functions; the replica ships none, so "nothing stored" means "use the built-in icons".
import '../models/svgimage.dart';
import 'list_store.dart';

abstract class Svg {
  static final ListStore<Svgimage> store = ListStore<Svgimage>(
    'svg',
    fromJson: Svgimage.fromJson,
    toJson: (s) => s.toJson(),
    label: 'SVG',
  );

  /// `Svg.desvgs`: default icons (empty in the replica, see the file comment).
  static List<Svgimage> desvgs = <Svgimage>[];

  static List<Svgimage> get svgs => store.items;

  static Future<List<Svgimage>> load({bool force = false}) async {
    final list = await store.load(force: force);
    if (list.isEmpty && desvgs.isNotEmpty) store.items = List<Svgimage>.of(desvgs);
    return store.items;
  }

  static Future<bool> save() => store.save();

  static Svgimage? byId(String id) {
    for (final s in store.items) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Sets (or replaces) the icon with this id.
  static Future<void> put(String id, String svg) => store.run((list) {
        final i = list.indexWhere((e) => e.id == id);
        if (i < 0) {
          list.add(Svgimage(id: id, svg: svg));
        } else {
          list[i] = Svgimage(id: id, svg: svg);
        }
      });

  static Future<void> delete(String id) => store.run((list) => list.removeWhere((e) => e.id == id));

  static Future<void> clear() => store.run((list) => list.clear());
}
