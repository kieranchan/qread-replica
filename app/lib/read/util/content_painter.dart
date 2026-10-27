// read/util/content_painter.dart — builds the [TextPainter] a reader page uses to draw one [Content] block, with exactly the text styles and
// strut the layout engine measured with (so what is drawn breaks into the same lines that were counted), plus the map from painter
// offsets back to chapter-text offsets (selection, notes, search hits).
//
// Usage in a page painter, for every content `c` of a [PageText] `p` (title content: `lineheight` does not apply, its margins are inside
// `c.height`; y grows by `c.height + extra * c.lines.length + style.paragraphSpacing`):
//   final tp = ReadTextBuilder.painter(c, style, width, color: textColor);
//   ReadTextBuilder.paint(canvas, tp, Offset(left, y), extraLineHeight: p.lineheight);
// The page's spare height (`PageText.lineheight`) is added line by line in [paint]: the paragraph engine rounds line heights to whole
// pixels, so a fractional line pitch cannot be expressed through the strut.
// Image contents (`c.isImage`) are drawn by the UI from `c.lines.first.clines.first.href` with `c.fit` in a box `width x c.height`.
import 'package:flutter/painting.dart';

import '../model/line.dart';
import '../model/page.dart';
import '../setting/read_layout_style.dart';

abstract class ReadTextBuilder {
  /// All runs of a content block in drawing order (prefix + text).
  static Iterable<CLine> runsOf(Content c) sync* {
    for (final l in c.lines) {
      yield* l.clines;
    }
  }

  /// The styled text of a block. [color] is the body text colour; links use [linkColor] (default: [color]).
  static TextSpan span(
    Content c,
    ReadLayoutStyle style, {
    required Color color,
    Color? linkColor,
  }) {
    final isTitle = c.lines.isNotEmpty && c.lines.first.paragraphIndex < 0;
    final first = runsOf(c).isEmpty ? <String>{} : runsOf(c).first.styles;
    final scale = isTitle ? 1.0 : ReadLayoutStyle.scaleFor(first);
    final children = <InlineSpan>[];
    for (final r in runsOf(c)) {
      final tokens = r.styles;
      final s = style.textStyle(tokens, scale: scale, title: isTitle);
      final decorations = <TextDecoration>[
        if (tokens.contains(CLineStyle.underline) || tokens.contains(CLineStyle.link)) TextDecoration.underline,
        if (tokens.contains(CLineStyle.strike)) TextDecoration.lineThrough,
      ];
      if (r.prefix.isNotEmpty) {
        // The first-line indent is measured as U+3000 but drawn as invisible ideographs of the same width: with TextAlign.justify
        // a line holding U+3000 gets its free space spread over the whole line (the indent vanished and the characters spread).
        // Same length, so the offset mapping below is unchanged.
        children.add(TextSpan(text: '中' * r.prefix.length, style: s.copyWith(color: const Color(0x00000000))));
      }
      children.add(TextSpan(
        text: r.str,
        style: s.copyWith(
          color: tokens.contains(CLineStyle.link) ? (linkColor ?? color) : color,
          decoration: decorations.isEmpty ? null : TextDecoration.combine(decorations),
        ),
      ));
    }
    return TextSpan(style: style.textStyle(const {}, scale: scale, title: isTitle).copyWith(color: color), children: children);
  }

  /// A laid-out painter for [c] in a column [width] wide. Body text is justified when the style says so; titles use the title alignment;
  /// paragraphs whose runs carry `center` / `right` follow that.
  static TextPainter painter(
    Content c,
    ReadLayoutStyle style,
    double width, {
    required Color color,
    Color? linkColor,
  }) {
    final isTitle = c.lines.isNotEmpty && c.lines.first.paragraphIndex < 0;
    final first = runsOf(c).isEmpty ? <String>{} : runsOf(c).first.styles;
    final scale = isTitle ? 1.0 : ReadLayoutStyle.scaleFor(first);
    TextAlign align;
    if (isTitle) {
      align = style.titleAlign;
    } else if (first.contains(CLineStyle.center)) {
      align = TextAlign.center;
    } else if (first.contains(CLineStyle.right)) {
      align = TextAlign.right;
    } else {
      align = style.justify ? TextAlign.justify : TextAlign.left;
    }
    return TextPainter(
      text: span(c, style, color: color, linkColor: linkColor),
      textDirection: TextDirection.ltr,
      textAlign: align,
      textScaler: TextScaler.noScaling,
      strutStyle: style.strut(scale: scale, title: isTitle),
    )..layout(minWidth: width, maxWidth: width);
  }

  /// Draws [tp] at [offset]; with [extraLineHeight] > 0 every line is moved down by `extra * lineIndex` (the page's `lineheight`).
  static void paint(Canvas canvas, TextPainter tp, Offset offset, {double extraLineHeight = 0}) {
    if (extraLineHeight <= 0) {
      tp.paint(canvas, offset);
      return;
    }
    final metrics = tp.computeLineMetrics();
    for (var i = 0; i < metrics.length; i++) {
      final m = metrics[i];
      final top = m.baseline - m.ascent;
      final bottom = top + m.height;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(offset.dx - 8, offset.dy + top, offset.dx + tp.width + 8, offset.dy + bottom));
      tp.paint(canvas, Offset(offset.dx, offset.dy + extraLineHeight * i));
      canvas.restore();
    }
  }

  /// Chapter-text offset of the character at [flatOffset] in the painter text of [c], or -1 for indent / synthetic characters.
  static int sourceOffset(Content c, int flatOffset) {
    var pos = 0;
    for (final r in runsOf(c)) {
      final pl = r.prefix.length;
      if (flatOffset < pos + pl) return -1;
      pos += pl;
      if (flatOffset < pos + r.str.length) {
        return r.start < 0 ? -1 : r.start + (flatOffset - pos);
      }
      pos += r.str.length;
    }
    return -1;
  }

  /// Inverse of [sourceOffset]: the painter offset of chapter offset [source] in [c], or -1 when it is not in this block.
  static int flatOffset(Content c, int source) {
    var pos = 0;
    for (final r in runsOf(c)) {
      pos += r.prefix.length;
      if (r.start >= 0 && source >= r.start && source < r.end) return pos + (source - r.start);
      pos += r.str.length;
    }
    return -1;
  }

  /// The source-offset range covered by a painter selection `[flatStart, flatEnd)` inside [c] (indent characters are skipped);
  /// null when the selection contains no source characters.
  static ({int start, int end})? sourceRange(Content c, int flatStart, int flatEnd) {
    int? s;
    int? e;
    for (var i = flatStart; i < flatEnd; i++) {
      final o = sourceOffset(c, i);
      if (o < 0) continue;
      s ??= o;
      e = o + 1;
    }
    return s == null ? null : (start: s, end: e!);
  }
}
