// read/api/calculate/calculate_hapter.dart — `CalculateChapter`: lays a chapter out into pages (file name spelled as in the original).
//
// Original (class 1497, `_NovelViewState._calculatePages` 0xeb87a8 -> 0xeb8da0 -> 0xeb8e00 -> 0xeb8fc0 -> 0xeb964c): the chapter
// arrives as a list of `CalcuPages` (type 1 = image, otherwise a text paragraph), each paragraph is measured with a
// `TextPainter` (TextStyle with fontFamily/fontSize/fontWeight/height/leadingDistribution/letterSpacing, `layout(maxWidth)`),
// split into `Line`s of `CLine` runs (named args start/end/isfirst/style), grouped into `Content` blocks and then into
// `PageText` pages. Image blocks use the size from the image cache or a 100x100 default (0x23be88). Finally the spare height
// of every full page is spread over its lines (0x236954: `lineheight`, only when less than one line + paragraph gap is
// left, never on the last page) and in double-column mode a blank page is appended to make the page count even.
//
// This port follows that structure. Differences that matter: the page content comes from [ChapterContent] blocks instead of
// the original's JSON maps; every [CLine] carries its source offsets so [pageIndexForOffset] / [progressForPage] can map
// pages <-> character offsets (the original's progress is a 0..1 fraction `durChapterPos`, stored with 1/10000 resolution:
// 0xeae13c multiplies by 10000).
//
// Highlight rules with a font size / line height / family ([ReadLayoutStyle.metricRules]) are part of the measurement, as in the
// original, which wraps their matches in `<span style='rule:N'>` before laying the chapter out (0xf0caec): the runs of a paragraph
// are split at the matches and tagged `rule:N`, the paragraph is measured with a strut that only sets the minimum line height, and
// each line keeps its own height (the drawing uses the same styles and strut, see HighlightApply / ReadTextBuilder).
//
// Images inside a paragraph (image runs of a text block: 段评 bubbles and the other images on the same line as text, see
// WebBookLoader.parseContent) are measured as the original does it: a CLine of `type != 0` in a Line becomes a WidgetPlaceholderSpan
// of the "我的" box (PitchInfo.field_27 / field_2f, 0xeb964c at 0xeba3e0), here [ReadTextBuilder.inlineImage]. It takes one character of
// the flat paragraph text (U+FFFC) and none of the chapter text; it wraps to the next line only when the line has no room left. Its
// CLine on the laid-out line is `type: image`, `str: ''`, `start`/`end` -1.
//
// The engine is deterministic: the same blocks, size and [ReadLayoutStyle] always give the same pages, so results can be
// cached.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../model/line.dart';
import '../../model/page.dart';
import '../../setting/read_layout_style.dart';
import '../../util/content_painter.dart';

typedef ImageSizeResolver = FutureOr<Size?> Function(String src);

/// Class 1475/`Calare` (0xeb87a8 returns `Future<Calare>`): the pages of a chapter and the page to show first.
class Calare {
  final List<PageText> pages;
  final int index;
  const Calare(this.pages, [this.index = 0]);
}

class CalculateChapter {
  final ReadLayoutStyle style;

  /// Resolves the intrinsic size of an image `src` (a file path or `data:` URI). Missing sizes fall back to 100x100 like the
  /// original (0x23be88 `MySize`).
  final ImageSizeResolver? imageSizeOf;

  const CalculateChapter({this.style = const ReadLayoutStyle(), this.imageSizeOf});

  static const Size fallbackImageSize = Size(100, 100);

  /// Usable text area of one page (one column in double-column mode) for a screen of [size].
  Size contentSize(Size size) {
    final w = size.width - style.padding.horizontal;
    final h = size.height - style.padding.vertical;
    final colW = style.columns == 2 ? (w - style.columnGap) / 2 : w;
    return Size(math.max(colW, style.fontSize), math.max(h, style.fontSize * style.lineHeight));
  }

  /// Async entry point (image sizes are resolved first). [size] is the full page size including the margins.
  Future<List<PageText>> calculate({
    required Size size,
    required List<CalcuPages> blocks,
    String title = '',
    bool isVolume = false,
  }) async {
    final sizes = <String, Size>{};
    final resolver = imageSizeOf;
    if (resolver != null) {
      for (final b in blocks) {
        if (!b.isImage) continue;
        final src = b.runs.first.href;
        if (src.isEmpty || sizes.containsKey(src)) continue;
        final s = await resolver(src);
        if (s != null && s.width > 0 && s.height > 0) sizes[src] = s;
      }
    }
    return layout(size: size, blocks: blocks, title: title, isVolume: isVolume, imageSizes: sizes);
  }

  /// [calculate] plus the page that shows [offset] (character offset in the chapter text) or, when null, [progress] (0..1).
  Future<Calare> calculateAt({
    required Size size,
    required List<CalcuPages> blocks,
    required int textLength,
    String title = '',
    bool isVolume = false,
    int? offset,
    double progress = 0,
  }) async {
    final pages = await calculate(size: size, blocks: blocks, title: title, isVolume: isVolume);
    final index = offset != null ? pageIndexForOffset(pages, offset) : pageIndexForProgress(pages, progress, textLength);
    return Calare(pages, index);
  }

  /// Synchronous layout.
  List<PageText> layout({
    required Size size,
    required List<CalcuPages> blocks,
    String title = '',
    bool isVolume = false,
    Map<String, Size> imageSizes = const {},
  }) {
    final area = contentSize(size);
    final b = _PageBuilder(style, area);

    final trimmedTitle = title.trim();
    if (trimmedTitle.isNotEmpty) {
      final t = _layoutTitle(trimmedTitle, area.width);
      b.addTitle(t, centeredPage: isVolume);
    }

    var index = 0;
    for (final block in blocks) {
      if (block.isImage) {
        final run = block.runs.first;
        b.addImage(_imageContent(run, index, area, imageSizes[run.href] ?? fallbackImageSize));
      } else {
        final lines = _layoutParagraph(block, index, area.width);
        if (lines != null) b.addParagraph(lines.lines, lines.heights, index);
      }
      index++;
    }
    final pages = b.finish();
    _assignOffsets(pages);
    if (style.columns == 2 && pages.length.isOdd) {
      pages.add(PageText(iscentos: true, start: pages.isEmpty ? 0 : pages.last.end, end: pages.isEmpty ? 0 : pages.last.end));
    }
    return pages;
  }

  // ------------------------------------------------------------------ paragraphs

  _Measured _layoutTitle(String title, double width) {
    final textStyle = style.textStyle(const {}, title: true);
    final span = TextSpan(text: title, style: textStyle);
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: style.titleAlign,
      textScaler: TextScaler.noScaling,
      strutStyle: style.strut(title: true),
    )..layout(maxWidth: width);
    final ranges = _lineRanges(tp, title.length);
    final lh = _lineHeight(tp, style.titleFontSize * style.lineHeight);
    tp.dispose();
    final lines = <Line>[];
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      lines.add(Line(
        paragraphIndex: -1,
        clines: [
          CLine(str: title.substring(r.start, r.end), style: CLineStyle.title, isfirst: i == 0, ish: true),
        ],
      ));
    }
    return _Measured(lines, lh, List<double>.filled(lines.length, lh));
  }

  /// Splits [runs] where metric highlight rules match the paragraph text and tags the matched pieces `rule:N` (later rules win
  /// where matches overlap, like the colour decorations).
  List<CLine> _ruleRuns(List<CLine> runs) {
    final rules = style.metricRules;
    if (rules.isEmpty) return runs;
    final text = runs.map((r) => r.str).join();
    final marks = List<int>.filled(text.length, -1);
    var any = false;
    for (var i = 0; i < rules.length; i++) {
      for (final m in rules[i].matches(text)) {
        for (var k = m.start; k < m.end && k < text.length; k++) {
          marks[k] = i;
          any = true;
        }
      }
    }
    if (!any) return runs;
    final out = <CLine>[];
    var pos = 0;
    for (final r in runs) {
      if (r.isImage) {
        out.add(r); // an inline image has no text to match
        continue;
      }
      final s = r.str;
      var a = 0;
      for (var j = 1; j <= s.length; j++) {
        if (j < s.length && marks[pos + j] == marks[pos + a]) continue;
        final mark = marks[pos + a];
        out.add(CLine(
          str: s.substring(a, j),
          style: mark < 0 ? r.style : '${r.style} ${CLineStyle.rulePrefix}$mark'.trim(),
          type: r.type,
          id: a == 0 ? r.id : '',
          start: r.start < 0 ? -1 : r.start + a,
          end: r.start < 0 ? -1 : r.start + j,
          isfirst: r.isfirst && a == 0,
          href: r.href,
          noteref: r.noteref,
          ish: r.ish,
          prefix: a == 0 ? r.prefix : '',
        ));
        a = j;
      }
      pos += s.length;
    }
    return out;
  }

  /// Null when the paragraph has no visible text (and no inline image).
  _Measured? _layoutParagraph(CalcuPages block, int paragraphIndex, double width) {
    final runs = _ruleRuns(block.runs.where((r) => r.isImage || r.str.isNotEmpty).toList());
    if (runs.isEmpty) return null;
    final grow = style.hasRuleRuns(runs);

    final tokens = runs.first.styles;
    final heading = runs.first.ish || tokens.contains(CLineStyle.h1) || tokens.contains(CLineStyle.h2) || tokens.contains(CLineStyle.h3);
    final scale = ReadLayoutStyle.scaleFor(tokens);
    final plain = !heading && !tokens.contains(CLineStyle.center) && !tokens.contains(CLineStyle.right);
    final prefix = plain && runs.first.isfirst && style.indent > 0 ? '　' * style.indent : '';

    // Flat paragraph string and the map from flat positions back to runs.
    final segs = <_Seg>[];
    final children = <InlineSpan>[];
    final flat = StringBuffer();
    var pos = 0;
    for (var i = 0; i < runs.length; i++) {
      final r = runs[i];
      final pl = i == 0 ? prefix.length : 0;
      if (r.isImage) {
        // the placeholder of an inline image (one U+FFFC in the flat text), after the indent when the paragraph starts with it
        if (pl > 0) children.add(TextSpan(text: prefix, style: style.textStyle(r.styles, scale: scale)));
        children.add(ReadTextBuilder.inlineImage(style));
        final text = (i == 0 ? prefix : '') + ReadTextBuilder.placeholderChar;
        segs.add(_Seg(pos, pos + text.length, pl, r, i == 0));
        flat.write(text);
        pos += text.length;
        continue;
      }
      final text = (i == 0 ? prefix : '') + r.str;
      segs.add(_Seg(pos, pos + text.length, pl, r, i == 0));
      children.add(TextSpan(text: text, style: style.textStyle(r.styles, scale: scale)));
      flat.write(text);
      pos += text.length;
    }
    final flatText = flat.toString();

    final span = TextSpan(style: style.textStyle(const {}, scale: scale), children: children);
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      textScaler: TextScaler.noScaling,
      strutStyle: style.strut(scale: scale, grow: grow),
    )
      ..setPlaceholderDimensions(ReadTextBuilder.dimensionsOf(span))
      ..layout(maxWidth: width);
    final ranges = _lineRanges(tp, flatText.length);
    final lh = _lineHeight(tp, style.fontSize * scale * style.lineHeight);
    final metrics = grow ? tp.computeLineMetrics() : const <LineMetrics>[];
    tp.dispose();

    final lines = <Line>[];
    final heights = <double>[];
    for (var li = 0; li < ranges.length; li++) {
      final r = ranges[li];
      lines.add(Line(paragraphIndex: paragraphIndex, clines: _slice(flatText, segs, r.start, r.end)));
      heights.add(grow && li < metrics.length && metrics[li].height > 0 ? metrics[li].height : lh);
    }
    return _Measured(lines, lh, heights);
  }

  /// Source runs on one line of the flat paragraph.
  List<CLine> _slice(String flat, List<_Seg> segs, int ls, int le) {
    final out = <CLine>[];
    for (final seg in segs) {
      final os = math.max(ls, seg.flatStart);
      final oe = math.min(le, seg.flatEnd);
      if (oe <= os) continue;
      final prefixEnd = seg.flatStart + seg.prefixLen;
      final prefixStr = os < prefixEnd ? flat.substring(os, math.min(oe, prefixEnd)) : '';
      final run = seg.run;
      if (run.isImage) {
        // the placeholder sits at prefixEnd; a line holding only the indent before it keeps a text run with that indent
        final here = os <= prefixEnd && prefixEnd < oe;
        out.add(CLine(
          str: '',
          style: here ? run.style : '',
          type: here ? CLineType.image : CLineType.text,
          id: here ? run.id : '',
          isfirst: seg.first && os == seg.flatStart,
          href: here ? run.href : '',
          prefix: prefixStr,
        ));
        continue;
      }
      final bs = math.max(os, prefixEnd);
      final str = oe > bs ? flat.substring(bs, oe) : '';
      if (prefixStr.isEmpty && str.isEmpty) continue;
      final startsRun = bs == prefixEnd;
      var start = -1;
      var end = -1;
      if (run.start >= 0 && str.isNotEmpty) {
        start = run.start + (bs - prefixEnd);
        end = start + str.length;
        if (run.end >= 0 && end > run.end) end = run.end;
      }
      out.add(CLine(
        str: str,
        style: run.style,
        type: CLineType.text,
        id: startsRun ? run.id : '',
        start: start,
        end: end,
        isfirst: seg.first && os == seg.flatStart,
        href: run.href,
        noteref: run.noteref,
        ish: run.ish,
        prefix: prefixStr,
      ));
    }
    return out;
  }

  /// Character range of every visual line of a laid-out painter, contiguous from 0 to [length].
  List<TextRange> _lineRanges(TextPainter tp, int length) {
    final out = <TextRange>[];
    var offset = 0;
    while (offset < length) {
      final b = tp.getLineBoundary(TextPosition(offset: offset));
      var end = b.end;
      if (end <= offset) end = offset + 1;
      if (end > length) end = length;
      out.add(TextRange(start: offset, end: end));
      offset = end;
    }
    return out;
  }

  double _lineHeight(TextPainter tp, double fallback) {
    final m = tp.computeLineMetrics();
    if (m.isNotEmpty && m.first.height > 0) return m.first.height;
    return fallback;
  }

  // ------------------------------------------------------------------ images

  Content _imageContent(CLine run, int paragraphIndex, Size area, Size image) {
    var w = math.min(image.width, area.width);
    var h = image.height * w / image.width;
    if (h > area.height) {
      h = area.height;
      w = image.width * h / image.height;
    }
    final line = Line(
      paragraphIndex: paragraphIndex,
      clines: [
        CLine(
          str: '',
          style: CLineStyle.image,
          type: CLineType.image,
          start: run.start,
          end: run.start >= 0 ? run.start : -1,
          isfirst: true,
          href: run.href,
          id: run.id,
        ),
      ],
    );
    return Content(lines: [line], height: h, type: CLineType.image, line: 1, fit: BoxFit.contain);
  }

  // ------------------------------------------------------------------ offsets

  /// Fills [PageText.start] / [PageText.end] from the lines; pages without source characters inherit the previous end.
  static void _assignOffsets(List<PageText> pages) {
    var prevEnd = 0;
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      var s = -1;
      var e = -1;
      for (final c in p.contents) {
        for (final l in c.lines) {
          for (final cl in l.clines) {
            if (cl.start < 0) continue;
            if (s < 0 || cl.start < s) s = cl.start;
            if (cl.end > e) e = cl.end;
          }
        }
      }
      if (s < 0) {
        s = prevEnd;
        e = prevEnd;
      }
      if (i == 0) s = 0;
      if (s < prevEnd) s = prevEnd;
      if (e < s) e = s;
      p.start = s;
      p.end = e;
      prevEnd = e;
    }
  }

  // ------------------------------------------------------------------ page <-> offset mapping

  /// Total number of source characters covered by [pages].
  static int textLengthOf(List<PageText> pages) => pages.isEmpty ? 0 : pages.last.end;

  /// The page showing character [offset]: the last page that starts at or before it.
  static int pageIndexForOffset(List<PageText> pages, int offset) {
    if (pages.isEmpty) return 0;
    var lo = 0;
    var hi = pages.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (pages[mid].start <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// First source character shown on page [index].
  static int offsetForPage(List<PageText> pages, int index) {
    if (pages.isEmpty) return 0;
    return pages[index.clamp(0, pages.length - 1)].start;
  }

  /// Reading progress through the chapter (0..1) when page [index] is on screen: the fraction of the text before it. This is
  /// what `Book.durChapterPos` stores; because it counts characters (not pages) it survives font / size changes.
  static double progressForPage(List<PageText> pages, int index, [int? totalChars]) {
    final total = totalChars ?? textLengthOf(pages);
    if (pages.isEmpty || total <= 0) return 0;
    return (offsetForPage(pages, index) / total).clamp(0.0, 1.0);
  }

  /// Inverse of [progressForPage]. The stored progress has 1/10000 resolution (the original multiplies by 10000, 0xeae13c),
  /// i.e. it can be off by a few characters on long chapters, so the offset is rounded, not truncated.
  static int pageIndexForProgress(List<PageText> pages, double progress, [int? totalChars]) {
    final total = totalChars ?? textLengthOf(pages);
    if (pages.isEmpty || total <= 0 || progress <= 0) return 0;
    final offset = (progress.clamp(0.0, 1.0) * total).round();
    return pageIndexForOffset(pages, offset);
  }

  /// The page that holds anchor [id] (EPUB `#fragment`, original "根据id得到页码"), or -1.
  static int pageIndexForAnchor(List<PageText> pages, String id) {
    if (id.isEmpty) return -1;
    for (var i = 0; i < pages.length; i++) {
      for (final c in pages[i].contents) {
        for (final l in c.lines) {
          for (final cl in l.clines) {
            if (cl.id == id) return i;
          }
        }
      }
    }
    return -1;
  }

  /// Where character [offset] sits in the laid-out pages, or null when it is outside.
  static PitchInfo? locate(List<PageText> pages, int offset) {
    if (pages.isEmpty) return null;
    final pi = pageIndexForOffset(pages, offset);
    final page = pages[pi];
    for (var ci = 0; ci < page.contents.length; ci++) {
      final c = page.contents[ci];
      for (var li = 0; li < c.lines.length; li++) {
        final l = c.lines[li];
        for (var k = 0; k < l.clines.length; k++) {
          final cl = l.clines[k];
          if (cl.start >= 0 && offset >= cl.start && offset < cl.end) {
            return PitchInfo(page: pi, content: ci, line: li, cline: k, start: cl.start, end: cl.end, offsetInRun: offset - cl.start);
          }
        }
      }
    }
    return null;
  }
}

class _Measured {
  final List<Line> lines;
  final double lineHeight;

  /// Height of every line (all [lineHeight] unless metric rules made some taller).
  final List<double> heights;
  const _Measured(this.lines, this.lineHeight, this.heights);
}

class _Seg {
  final int flatStart;
  final int flatEnd;
  final int prefixLen;
  final CLine run;
  final bool first;
  const _Seg(this.flatStart, this.flatEnd, this.prefixLen, this.run, this.first);
}

/// Fills pages top to bottom. Gaps (`paragraphSpacing`) only go between blocks of the same page.
class _PageBuilder {
  final ReadLayoutStyle style;
  final Size area;
  final List<PageText> pages = [];

  PageText _cur = PageText();
  double _used = 0; // contents + gaps
  bool _pageHasImage = false;

  _PageBuilder(this.style, this.area);

  double get _gap => _cur.contents.isEmpty ? 0 : style.paragraphSpacing;

  void addTitle(_Measured t, {required bool centeredPage}) {
    final h = style.titleTopMargin + t.lines.length * t.lineHeight + style.titleBottomMargin;
    final c = Content(lines: t.lines, height: h, type: CLineType.text, line: t.lines.length);
    if (centeredPage) {
      _cur.contents.add(c);
      _used = h;
      _cur.iscentos = true;
      _closePage(last: false, stretch: false);
    } else {
      _place(c, 0);
    }
  }

  void addParagraph(List<Line> lines, List<double> heights, int paragraphIndex) {
    var i = 0;
    while (i < lines.length) {
      final gap = i == 0 ? _gap : 0.0;
      final avail = area.height - _used - gap;
      var n = 0;
      var h = 0.0;
      while (i + n < lines.length && h + heights[i + n] <= avail + 1e-6) {
        h += heights[i + n];
        n++;
      }
      if (n < 1) {
        if (_cur.contents.isEmpty) {
          n = 1; // page smaller than one line: force progress
          h = heights[i];
        } else {
          _closePage(last: false);
          continue;
        }
      }
      final chunk = lines.sublist(i, i + n);
      _place(Content(lines: chunk, height: h, type: CLineType.text, line: n), gap);
      i += n;
      if (i < lines.length) _closePage(last: false);
    }
  }

  void addImage(Content c) {
    var gap = _gap;
    if (_cur.contents.isNotEmpty && _used + gap + c.height > area.height + 1e-6) {
      _closePage(last: false);
      gap = 0;
    }
    _place(c, gap);
    _pageHasImage = true;
  }

  void _place(Content c, double gap) {
    _cur.contents.add(c);
    _used += gap + c.height;
  }

  void _closePage({required bool last, bool stretch = true}) {
    if (_cur.contents.isEmpty) return;
    var heights = 0.0;
    var lineCount = 0;
    for (final c in _cur.contents) {
      heights += c.height;
      final isTitle = c.lines.isNotEmpty && c.lines.first.paragraphIndex < 0;
      if (!isTitle) lineCount += c.line; // the title block has its own margins and takes no part in the stretch
    }
    _cur.height = heights;
    final leftover = area.height - _used;
    final threshold = style.fontSize * style.lineHeight + style.paragraphSpacing;
    if (stretch && style.stretchPages && !last && !_pageHasImage && lineCount > 0 && leftover > 0 && leftover < threshold) {
      _cur.lineheight = leftover / lineCount;
    }
    pages.add(_cur);
    _cur = PageText();
    _used = 0;
    _pageHasImage = false;
  }

  List<PageText> finish() {
    _closePage(last: true);
    if (pages.isEmpty) pages.add(PageText());
    return pages;
  }
}
