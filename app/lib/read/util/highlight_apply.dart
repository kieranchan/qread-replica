// read/util/highlight_apply.dart — paints highlight rules, notes, the read-aloud range and search hits into the text of one page block.
//
// Original: `highlight_apply.dart` (0xf0caec, applies `HighlightRule`s of `HighlightData` to the paragraph text with the day/night colours,
// font weight/style, decoration and a background image drawn as nine-patch). This port builds the [TextSpan] of a [Content] block with
// the same styles the layout engine measured with (see `ReadTextBuilder.span`) and splits the runs at every decoration boundary.
// Only properties that do not move line breaks are applied (colour, background, decoration, italic); `fontSize` / `lineHeight` /
// `fontFamily` of a rule and the background images are not drawn. TODO(asm 0xf0caec): nine-patch background images of rules.
import 'package:flutter/painting.dart';

import '../../models/highlight_rule.dart';
import '../model/line.dart';
import '../model/page.dart';
import '../setting/read_layout_style.dart';
import 'content_painter.dart';

/// A styled range in the painter text of one block (`start` inclusive, `end` exclusive). Later decorations win on conflicts.
class TextDeco {
  final int start;
  final int end;
  final Color? color;
  final Color? background;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final TextDecoration? decoration;
  final Color? decorationColor;
  final TextDecorationStyle? decorationStyle;

  const TextDeco(
    this.start,
    this.end, {
    this.color,
    this.background,
    this.fontWeight,
    this.fontStyle,
    this.decoration,
    this.decorationColor,
    this.decorationStyle,
  });

  TextStyle apply(TextStyle s) => s.copyWith(
        color: color,
        backgroundColor: background,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
      );
}

abstract class HighlightApply {
  /// The painter text of [c] (indent + run text).
  static String flatText(Content c) => ReadTextBuilder.runsOf(c).map((r) => r.text).join();

  /// Painter range of the chapter-text range `[srcStart, srcEnd)` inside [c], or null when it does not touch the block.
  static ({int start, int end})? flatRange(Content c, int srcStart, int srcEnd) {
    if (srcEnd <= srcStart) return null;
    int? s;
    int? e;
    var pos = 0;
    for (final r in ReadTextBuilder.runsOf(c)) {
      pos += r.prefix.length;
      if (r.start >= 0 && r.str.isNotEmpty) {
        final os = srcStart > r.start ? srcStart : r.start;
        final oe = srcEnd < r.end ? srcEnd : r.end;
        if (oe > os) {
          final fs = pos + (os - r.start);
          final fe = pos + (oe - r.start);
          if (s == null || fs < s) s = fs;
          if (e == null || fe > e) e = fe;
        }
      }
      pos += r.str.length;
    }
    return s == null ? null : (start: s, end: e!);
  }

  /// Decorations of the enabled [rules] matched against the painter text [flat] (day or [night] colours).
  static List<TextDeco> ruleDecos(String flat, List<HighlightRule> rules, {required bool night}) {
    final out = <TextDeco>[];
    for (final r in rules) {
      if (!r.isEnabled || r.pattern.isEmpty) continue;
      Iterable<Match> matches;
      if (r.isRegex) {
        try {
          matches = RegExp(r.pattern, multiLine: true).allMatches(flat);
        } catch (_) {
          continue;
        }
      } else {
        matches = r.pattern.allMatches(flat);
      }
      final color = parseColor(night ? r.nightColor : r.dayColor);
      final bg = parseColor(night ? r.nightBgColor : r.dayBgColor);
      final weight = _weight(r.fontWeight);
      final italic = r.fontStyle.toLowerCase().contains('italic') ? FontStyle.italic : null;
      final deco = _decoration(r.textDecoration);
      for (final m in matches) {
        if (m.end <= m.start) continue;
        out.add(TextDeco(m.start, m.end, color: color, background: bg, fontWeight: weight, fontStyle: italic, decoration: deco));
      }
    }
    return out;
  }

  static FontWeight? _weight(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty || t == 'normal') return t == 'normal' ? FontWeight.w400 : null;
    if (t == 'bold') return FontWeight.w700;
    final v = int.tryParse(t.replaceAll(RegExp(r'[^0-9]'), ''));
    if (v == null) return null;
    final i = (v / 100).round().clamp(1, 9);
    return FontWeight.values[i - 1];
  }

  static TextDecoration? _decoration(String s) {
    final t = s.toLowerCase();
    if (t.contains('underline')) return TextDecoration.underline;
    if (t.contains('line-through') || t.contains('linethrough')) return TextDecoration.lineThrough;
    if (t.contains('overline')) return TextDecoration.overline;
    return null;
  }

  /// `#rrggbb`, `#aarrggbb`, `0xaarrggbb`; null when empty or invalid.
  static Color? parseColor(String s) {
    var t = s.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('#')) t = t.substring(1);
    if (t.startsWith('0x') || t.startsWith('0X')) t = t.substring(2);
    if (t.length == 6) t = 'ff$t';
    if (t.length != 8) return null;
    final v = int.tryParse(t, radix: 16);
    return v == null ? null : Color(v);
  }

  /// The styled text of [c] with [decos] applied on top of the layout styles (same metrics as `ReadTextBuilder.span`).
  static TextSpan span(
    Content c,
    ReadLayoutStyle style, {
    required Color color,
    Color? linkColor,
    List<TextDeco> decos = const [],
  }) {
    final isTitle = c.lines.isNotEmpty && c.lines.first.paragraphIndex < 0;
    final runs = ReadTextBuilder.runsOf(c).toList();
    final first = runs.isEmpty ? <String>{} : runs.first.styles;
    final scale = isTitle ? 1.0 : ReadLayoutStyle.scaleFor(first);
    final children = <InlineSpan>[];
    var pos = 0;
    for (final r in runs) {
      final text = r.text;
      final base = _runStyle(r, style, scale, isTitle, color, linkColor);
      if (decos.isEmpty) {
        children.add(TextSpan(text: text, style: base));
        pos += text.length;
        continue;
      }
      final rs = pos;
      final re = pos + text.length;
      final cuts = <int>{rs, re};
      for (final d in decos) {
        if (d.end <= rs || d.start >= re) continue;
        if (d.start > rs) cuts.add(d.start);
        if (d.end < re) cuts.add(d.end);
      }
      final sorted = cuts.toList()..sort();
      for (var i = 0; i + 1 < sorted.length; i++) {
        final a = sorted[i];
        final b = sorted[i + 1];
        if (b <= a) continue;
        var s = base;
        for (final d in decos) {
          if (d.start <= a && d.end >= b) s = d.apply(s);
        }
        children.add(TextSpan(text: text.substring(a - rs, b - rs), style: s));
      }
      pos = re;
    }
    return TextSpan(style: style.textStyle(const {}, scale: scale, title: isTitle).copyWith(color: color), children: children);
  }

  static TextStyle _runStyle(CLine r, ReadLayoutStyle style, double scale, bool isTitle, Color color, Color? linkColor) {
    final tokens = r.styles;
    final s = style.textStyle(tokens, scale: scale, title: isTitle);
    final decorations = <TextDecoration>[
      if (tokens.contains(CLineStyle.underline) || tokens.contains(CLineStyle.link)) TextDecoration.underline,
      if (tokens.contains(CLineStyle.strike)) TextDecoration.lineThrough,
    ];
    return s.copyWith(
      color: tokens.contains(CLineStyle.link) ? (linkColor ?? color) : color,
      decoration: decorations.isEmpty ? null : TextDecoration.combine(decorations),
    );
  }

  /// Text alignment of a block (title alignment, centred/right paragraphs, justified body).
  static TextAlign alignOf(Content c, ReadLayoutStyle style) {
    final isTitle = c.lines.isNotEmpty && c.lines.first.paragraphIndex < 0;
    if (isTitle) return style.titleAlign;
    final runs = ReadTextBuilder.runsOf(c);
    final first = runs.isEmpty ? <String>{} : runs.first.styles;
    if (first.contains(CLineStyle.center)) return TextAlign.center;
    if (first.contains(CLineStyle.right)) return TextAlign.right;
    return style.justify ? TextAlign.justify : TextAlign.left;
  }

  static StrutStyle strutOf(Content c, ReadLayoutStyle style) {
    final isTitle = c.lines.isNotEmpty && c.lines.first.paragraphIndex < 0;
    final runs = ReadTextBuilder.runsOf(c);
    final first = runs.isEmpty ? <String>{} : runs.first.styles;
    return style.strut(scale: isTitle ? 1.0 : ReadLayoutStyle.scaleFor(first), title: isTitle);
  }
}
