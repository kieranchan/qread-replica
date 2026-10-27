// read/util/css.dart — `StyleGenUtils` (0x237c0c, "快速生成样式" of the layout editor) and `CssNamedColors`: builds the chapter-title HTML
// template (`BackGround.titleCss`, must contain `$title`) from the options of the "标题样式设置" dialog and parses CSS colours
// (`#rgb`, `#rrggbb`, `#aarrggbb`, `0x…`, `rgb()`, `rgba()`, named colours; closures 0xebdbcc / 0x100b3e0).
import 'package:flutter/painting.dart';

class TitleStyleOptions {
  /// Pixels.
  final int fontSize;
  final String fontFamily;

  /// CSS weight 100..900.
  final int fontWeight;
  final String color;
  final bool italic;

  /// `left` / `center` / `right`.
  final String align;
  final String background;
  final String backgroundImage;

  /// CSS shorthand, e.g. `10px 15px 10px 15px`.
  final String padding;
  final String margin;

  const TitleStyleOptions({
    this.fontSize = 24,
    this.fontFamily = '',
    this.fontWeight = 700,
    this.color = '',
    this.italic = false,
    this.align = 'left',
    this.background = '',
    this.backgroundImage = '',
    this.padding = '',
    this.margin = '',
  });
}

abstract class StyleGenUtils {
  static const String placeholder = r'$title';

  /// The title template for [o] (one `<div>` with an inline style around `$title`).
  static String generate(TitleStyleOptions o) {
    final css = <String>[
      'font-size: ${o.fontSize}px',
      if (o.fontFamily.isNotEmpty) "font-family: '${o.fontFamily}'",
      'font-weight: ${o.fontWeight}',
      if (o.color.isNotEmpty) 'color: ${o.color}',
      if (o.italic) 'font-style: italic',
      'text-align: ${o.align}',
      if (o.background.isNotEmpty) 'background-color: ${o.background}',
      if (o.backgroundImage.isNotEmpty) "background-image: url('${o.backgroundImage}'); background-size: cover",
      if (o.padding.isNotEmpty) 'padding: ${o.padding}',
      if (o.margin.isNotEmpty) 'margin: ${o.margin}',
    ];
    return '<div style="${css.join('; ')}">$placeholder</div>';
  }

  static bool isValidTemplate(String css) => css.contains(placeholder);

  /// Parses a CSS colour; null when it is not one.
  static Color? parseColor(String input) {
    final s = input.trim().toLowerCase();
    if (s.isEmpty) return null;
    final named = CssNamedColors.values[s];
    if (named != null) return Color(named);
    if (s.startsWith('rgb')) {
      final open = s.indexOf('(');
      final close = s.indexOf(')');
      if (open < 0 || close < open) return null;
      final parts = s.substring(open + 1, close).split(',').map((e) => e.trim()).toList();
      if (parts.length < 3) return null;
      final rgb = [for (var i = 0; i < 3; i++) int.tryParse(parts[i])];
      if (rgb.any((v) => v == null)) return null;
      final a = parts.length > 3 ? (double.tryParse(parts[3]) ?? 1) : 1.0;
      return Color.fromARGB((a.clamp(0, 1) * 255).round(), rgb[0]!.clamp(0, 255), rgb[1]!.clamp(0, 255), rgb[2]!.clamp(0, 255));
    }
    var h = s;
    if (h.startsWith('#')) h = h.substring(1);
    if (h.startsWith('0x')) h = h.substring(2);
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) h = 'ff$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  static String toHex(Color c) => '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
}

/// The common CSS named colours (the original carries the full CSS list, 0x237c0c).
abstract class CssNamedColors {
  static const Map<String, int> values = {
    'black': 0xFF000000, 'white': 0xFFFFFFFF, 'red': 0xFFFF0000, 'green': 0xFF008000, 'blue': 0xFF0000FF, 'yellow': 0xFFFFFF00,
    'orange': 0xFFFFA500, 'purple': 0xFF800080, 'gray': 0xFF808080, 'grey': 0xFF808080, 'silver': 0xFFC0C0C0, 'maroon': 0xFF800000,
    'olive': 0xFF808000, 'lime': 0xFF00FF00, 'aqua': 0xFF00FFFF, 'cyan': 0xFF00FFFF, 'teal': 0xFF008080, 'navy': 0xFF000080,
    'fuchsia': 0xFFFF00FF, 'magenta': 0xFFFF00FF, 'pink': 0xFFFFC0CB, 'brown': 0xFFA52A2A, 'gold': 0xFFFFD700, 'beige': 0xFFF5F5DC,
    'ivory': 0xFFFFFFF0, 'khaki': 0xFFF0E68C, 'lavender': 0xFFE6E6FA, 'linen': 0xFFFAF0E6, 'wheat': 0xFFF5DEB3, 'tan': 0xFFD2B48C,
    'coral': 0xFFFF7F50, 'crimson': 0xFFDC143C, 'indigo': 0xFF4B0082, 'violet': 0xFFEE82EE, 'orchid': 0xFFDA70D6, 'salmon': 0xFFFA8072,
    'tomato': 0xFFFF6347, 'chocolate': 0xFFD2691E, 'darkred': 0xFF8B0000, 'darkblue': 0xFF00008B, 'darkgreen': 0xFF006400,
    'darkgray': 0xFFA9A9A9, 'darkgrey': 0xFFA9A9A9, 'lightgray': 0xFFD3D3D3, 'lightgrey': 0xFFD3D3D3, 'whitesmoke': 0xFFF5F5F5,
    'aliceblue': 0xFFF0F8FF, 'antiquewhite': 0xFFFAEBD7, 'skyblue': 0xFF87CEEB, 'steelblue': 0xFF4682B4, 'seagreen': 0xFF2E8B57,
    'transparent': 0x00000000,
  };
}
