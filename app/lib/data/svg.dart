// data/svg.dart — user SVG icon sets (the paragraph-comment bubbles of the reader). File-store key `svg` (JSON list of [Svgimage]
// {id, svg}); cloud item `svg` with md5 key `svgmd5`.
//
// Original: `Svg` (`_svgs` 0x4ab8, `desvgs` 0x4ac0 = the defaults used when nothing is stored, `_lock` 0x4aa8; load 0x10db80c:
// empty result -> `desvgs`). The four defaults are the late initializer 0x2276cc (ids "0".."3", built from the pool strings
// pp+0x29600..0x29698 by string concatenation, reproduced below piece by piece).
import '../models/svgimage.dart';
import 'user.dart';
import 'list_store.dart';

abstract class Svg {
  static final ListStore<Svgimage> store = ListStore<Svgimage>(
    'svg',
    fromJson: Svgimage.fromJson,
    toJson: (s) => s.toJson(),
    label: 'SVG',
  );

  /// `Svg.desvgs` (0x2276cc): the built-in bubbles.
  static List<Svgimage> desvgs = <Svgimage>[
    Svgimage(
      id: '0',
      svg: '<svg width="16" height="12" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M4,2 L13,2 Q15,2 15,4 L15,9 Q15,11 13,11 L4,11 Q2,11 2,9 L2,7.5 L0.5,6 L2,4.5 L2,4 Q2,2 4,2 Z" '
          'fill="none" stroke="\$color" stroke-width="0.3" stroke-linejoin="round"/>'
          '<text x="8" y="6.8" font-family="Arial" text-anchor="middle" '
          'font-size="5.5" fill="\$color" font-weight="600" dy="1.5">\$displayText</text>'
          '</svg>',
    ),
    Svgimage(
      id: '1',
      svg: '<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">'
          '<circle cx="50" cy="50" r="45" fill="none" stroke="\$color" stroke-width="2" opacity="0.15"/>'
          '<circle cx="50" cy="50" r="40" fill="none" stroke="\$color" stroke-width="1"/>'
          '<text x="50" y="53" font-family="Arial" text-anchor="middle" '
          'font-size="45" fill="\$color" font-weight="600" dy="10">\$displayText</text>'
          '</svg>',
    ),
    Svgimage(
      id: '2',
      svg: '<svg width="100" height="80" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M10,15 L85,15 Q92,15 92,22 L92,58 Q92,65 85,65 L25,65 L18,72 L10,65 Q3,65 3,58 L3,22 Q3,15 10,15 Z" '
          'fill="none" stroke="\$color" stroke-width="2" stroke-linejoin="round"/>'
          '<text x="50" y="43" font-family="Arial" text-anchor="middle" '
          'font-size="40" fill="\$color" font-weight="500" dy="10">\$displayText</text>'
          '</svg>',
    ),
    Svgimage(
      id: '3',
      svg: '<svg width="80" height="100" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M15,10 L65,10 Q70,10 70,15 L70,85 Q70,90 65,90 L43,90 L40,98 L37,90 L15,90 Q10,90 10,85 L10,15 Q10,10 15,10 Z" '
          'fill="none" stroke="\$color" stroke-width="2" stroke-linejoin="round"/>'
          '<text x="40" y="53" font-family="Arial" text-anchor="middle" '
          'font-size="45" fill="\$color" font-weight="500" dy="10">\$displayText</text>'
          '</svg>',
    ),
  ];

  /// The stored list (what the cloud item and the editor work on).
  static List<Svgimage> get svgs => store.items;

  /// 0x2273b0: the bubbles the app offers — a copy of the stored list for members, a copy of [desvgs] otherwise (custom bubbles
  /// are a member feature).
  static List<Svgimage> get available => [for (final s in UserSession.isvip ? store.items : desvgs) Svgimage(id: s.id, svg: s.svg)];

  /// The bubble with this id among [available], else the first one (null when there is none).
  static Svgimage? selected(String id) {
    final list = available;
    for (final s in list) {
      if (s.id == id) return s;
    }
    return list.isEmpty ? null : list.first;
  }

  static Future<List<Svgimage>> load({bool force = false}) async {
    final list = await store.load(force: force);
    if (list.isEmpty && desvgs.isNotEmpty) {
      store.items = [for (final s in desvgs) Svgimage(id: s.id, svg: s.svg)];
    }
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
