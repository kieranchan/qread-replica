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
// Images inside a paragraph (image runs of a text block: 段评 bubbles and other images on the same line as text) are [InlineImageSpan]
// placeholders of [ReadTextBuilder.inlineImageSize]; a canvas painter leaves their box empty, the page draws them as widgets.
import 'package:flutter/widgets.dart';

import '../model/line.dart';
import '../model/page.dart';
import '../setting/read_layout_style.dart';

/// An image inside a line of text. The original's `WidgetPlaceholderSpan` (newread/read/util/image.dart: an ExtendedWidgetSpan holding a
/// fixed `Size`, set up by 0x23a650 with PlaceholderAlignment.middle and TextBaseline.ideographic): the layout engine (0xeb964c, CLine
/// `type != 0` inside a Line) and the page (0xffedf4 -> 0x1002698) both put one in the paragraph with the same size, so measuring and
/// drawing break the lines alike. [child] is only drawn by the page; every [TextPainter] gets the box from [size]
/// ([ReadTextBuilder.dimensionsOf]).
class InlineImageSpan extends WidgetSpan {
  final Size size;

  const InlineImageSpan({required this.size, required super.child}) : super(alignment: PlaceholderAlignment.middle, baseline: TextBaseline.ideographic);
}

abstract class ReadTextBuilder {
  /// Drawn (transparent) in place of each U+3000 of a first-line indent: same width, but not whitespace for TextAlign.justify.
  static const String indentGlyph = '中';

  /// All runs of a content block in drawing order (prefix + text).
  static Iterable<CLine> runsOf(Content c) sync* {
    for (final l in c.lines) {
      yield* l.clines;
    }
  }

  /// The character a placeholder takes in the painter text (U+FFFC, as for every [PlaceholderSpan]).
  static const String placeholderChar = '￼';

  /// The painter text of a run after its indent: the run's text, or the one placeholder character of an inline image. An inline
  /// image takes no character of the chapter text, so its painter character maps to -1 like the indent ([sourceOffset]).
  static String bodyOf(CLine r) => r.isImage ? placeholderChar : r.str;

  static final Map<String, Size> _inlineSizes = {};

  /// The box an inline image takes in its line: as wide as "我的" in the body text style and one line high. The original measures
  /// "我的" with the reading font size / line height / letter spacing (0x240c00, a TextPainter laid out once) and keeps that size as
  /// PitchInfo.field_27 / field_2f (0xec1a3c), which the layout engine gives every inline image (0xeb964c at 0xeba3e0); the page builds
  /// its WidgetPlaceholderSpan from a captured `Size(w, h)` and draws the picture in a SizedBox of it (0xffedf4 at 0x1002614..0x1002698;
  /// where that Size comes from is not traced, it has to be the same box for the lines to match). The height here is exactly the strut's
  /// line pitch (fontSize x lineHeight), which is what the "我的" painter reports for a fixed line height, so the box never makes a line
  /// taller.
  static Size inlineImageSize(ReadLayoutStyle style) {
    final base = style.textStyle(const {});
    final key = '${base.fontFamily}|${base.fontSize}|${base.fontWeight?.value}|${base.letterSpacing}|${style.lineHeight}';
    return _inlineSizes[key] ??= () {
      final tp = TextPainter(text: TextSpan(text: '我的', style: base), textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)
        ..layout();
      final w = tp.width;
      tp.dispose();
      return Size(w, style.fontSize * style.lineHeight);
    }();
  }

  /// Height of the picture drawn inside an inline image box (centred in it): `min(fontSize * 1.2, box height - 1)` (0x10023e8 ->
  /// CacheBookImage height at 0x1002494).
  static double inlineImageHeight(ReadLayoutStyle style, Size box) {
    final cap = style.fontSize * 1.2;
    if (box.height >= cap) return cap;
    return box.height - 1 > 0 ? box.height - 1 : 0;
  }

  /// The placeholder of an inline image run; [child] is what the page draws in it (default: an empty box of the same size, enough for
  /// measuring).
  static InlineImageSpan inlineImage(ReadLayoutStyle style, {Widget? child}) {
    final size = inlineImageSize(style);
    return InlineImageSpan(size: size, child: child ?? SizedBox.fromSize(size: size));
  }

  /// The placeholder boxes of [span] in text order, for [TextPainter.setPlaceholderDimensions] (a painter whose text holds placeholders
  /// cannot lay out without them). [InlineImageSpan]s report their fixed size.
  static List<PlaceholderDimensions> dimensionsOf(InlineSpan span) {
    final out = <PlaceholderDimensions>[];
    span.visitChildren((s) {
      if (s is PlaceholderSpan) {
        out.add(PlaceholderDimensions(size: s is InlineImageSpan ? s.size : Size.zero, alignment: s.alignment, baseline: s.baseline));
      }
      return true;
    });
    return out;
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
        children.add(TextSpan(text: indentGlyph * r.prefix.length, style: s.copyWith(color: const Color(0x00000000))));
      }
      if (r.isImage) {
        children.add(inlineImage(style));
        continue;
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
    final text = span(c, style, color: color, linkColor: linkColor);
    return TextPainter(
      text: text,
      textDirection: TextDirection.ltr,
      textAlign: align,
      textScaler: TextScaler.noScaling,
      strutStyle: style.strut(scale: scale, title: isTitle, grow: !isTitle && style.hasRuleRuns(runsOf(c))),
    )
      ..setPlaceholderDimensions(dimensionsOf(text))
      ..layout(minWidth: width, maxWidth: width);
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

  /// Chapter-text offset of the character at [flatOffset] in the painter text of [c], or -1 for indent / synthetic characters and the
  /// placeholder of an inline image.
  static int sourceOffset(Content c, int flatOffset) {
    var pos = 0;
    for (final r in runsOf(c)) {
      final pl = r.prefix.length;
      if (flatOffset < pos + pl) return -1;
      pos += pl;
      final bl = bodyOf(r).length;
      if (flatOffset < pos + bl) {
        return r.isImage || r.start < 0 ? -1 : r.start + (flatOffset - pos);
      }
      pos += bl;
    }
    return -1;
  }

  /// Inverse of [sourceOffset]: the painter offset of chapter offset [source] in [c], or -1 when it is not in this block.
  static int flatOffset(Content c, int source) {
    var pos = 0;
    for (final r in runsOf(c)) {
      pos += r.prefix.length;
      if (!r.isImage && r.start >= 0 && source >= r.start && source < r.end) return pos + (source - r.start);
      pos += bodyOf(r).length;
    }
    return -1;
  }

  /// The source-offset range covered by a painter selection `[flatStart, flatEnd)` inside [c] (indent characters and inline images are
  /// skipped);
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
