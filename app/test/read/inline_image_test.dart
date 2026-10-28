// Images on the same line as text in a book source's chapter (段评 bubbles `dp:N`, the original's "和文字同行的图片会默认识别为段评"): the
// content model keeps them as inline runs of the paragraph, the layout engine reserves the "我的" box for them at their place in the line,
// the page draws the same spans, and they take no character of the chapter text. (flutter_test's font: every glyph is fontSize wide.)
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/pages/read/pages/novel_view.dart';
import 'package:newread/pages/read/read_aloud.dart';
import 'package:newread/pages/read/web_book_loader.dart';
import 'package:newread/read/api/calculate/calculate_hapter.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/model/line.dart';
import 'package:newread/read/model/page.dart';
import 'package:newread/read/setting/read_layout_style.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/content_painter.dart';
import 'package:newread/read/util/highlight_apply.dart';

const _style = ReadLayoutStyle(fontSize: 16, lineHeight: 1.5, paragraphSpacing: 8, indent: 2, padding: EdgeInsets.all(10), justify: true);
const _size = Size(200, 300); // a 180 px column: 11 glyphs of 16 px
const _engine = CalculateChapter(style: _style);
const _dp = '''<img src="dp:3,{'js':'showCmt(1)'}">''';

/// Every CLine of the laid-out pages.
Iterable<(int page, int content, int line, CLine run)> _runs(List<PageText> pages) sync* {
  for (var p = 0; p < pages.length; p++) {
    for (var c = 0; c < pages[p].contents.length; c++) {
      final lines = pages[p].contents[c].lines;
      for (var l = 0; l < lines.length; l++) {
        for (final r in lines[l].clines) {
          yield (p, c, l, r);
        }
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an image on the same line as text is an inline run of the paragraph; a line of images only gives image blocks', () {
    final c = WebBookLoader.parseContent('　　一二三$_dp\n<img src="http://h/a.png">\n四五<img src="b.png">六 \n七八');
    expect(c.blocks.length, 4);
    expect(c.text, '一二三\n四五六\n七八');
    final p1 = c.blocks[0];
    expect(p1.isImage, isFalse);
    expect([for (final r in p1.runs) r.isImage], [false, true]);
    expect(p1.runs[0].str, '一二三');
    expect((p1.runs[0].start, p1.runs[0].end), (0, 3));
    expect(p1.runs[1].href, "dp:3,{'js':'showCmt(1)'}");
    expect((p1.runs[1].start, p1.runs[1].end, p1.runs[1].str), (3, 3, ''));
    expect(c.blocks[1].isImage, isTrue);
    expect(c.blocks[1].runs.single.href, 'http://h/a.png');
    // an image in the middle of a line stays at its place
    expect([for (final r in c.blocks[2].runs) r.isImage ? '[${r.href}]' : r.str], ['四五', '[b.png]', '六']);
    expect([for (final r in c.blocks[2].runs) (r.start, r.end)], [(4, 6), (6, 6), (6, 7)]);
    expect(c.isPlainText, isFalse);
    // a JSON with double quotes (as HtmlFormatter.formatKeepImg writes it) stays whole too
    final dq = WebBookLoader.parseContent('甲<img src="dp:5,{"js":"x()"}">');
    expect(dq.blocks.single.runs.last.href, 'dp:5,{"js":"x()"}');
    // comics keep every image a block
    final comic = WebBookLoader.parseContent('第一页<img src="a.png">', inline: false);
    expect([for (final b in comic.blocks) b.isImage], [false, true]);
  });

  test('a paragraph and its bubble lay out as one block, the bubble last on the last line; offsets are those of the text alone', () {
    final withDp = WebBookLoader.parseContent('一二三四五六七$_dp\n八九十');
    final plain = ChapterContent.fromText('一二三四五六七\n八九十');
    expect(withDp.text, plain.text);
    final pages = _engine.layout(size: _size, blocks: withDp.blocks);
    final ref = _engine.layout(size: _size, blocks: plain.blocks);
    expect(pages.length, 1);
    final first = pages.first.contents.first;
    expect(first.lines.length, 1, reason: '9 glyphs + the 2-glyph box fit the 11-glyph line');
    final runs = first.lines.single.clines;
    expect(runs.last.isImage, isTrue);
    expect(runs.last.href, "dp:3,{'js':'showCmt(1)'}");
    expect((runs.last.start, runs.last.end, runs.last.str), (-1, -1, ''));
    expect(first.height, ref.first.contents.first.height);
    expect(pages.first.contents.length, 2);
    expect((pages.first.start, pages.first.end), (ref.first.start, ref.first.end));
    for (final (_, _, _, r) in _runs(pages)) {
      if (r.start >= 0) expect(withDp.text.substring(r.start, r.end), r.str);
    }
    // the box: "我的" wide, one line high
    expect(ReadTextBuilder.inlineImageSize(_style), const Size(32, 24));
    expect(ReadTextBuilder.inlineImageHeight(_style, const Size(32, 24)), closeTo(16 * 1.2, 1e-9));
  });

  test('a full line pushes the bubble to the next line', () {
    final c = WebBookLoader.parseContent('一二三四五六七八九$_dp');
    final pages = _engine.layout(size: _size, blocks: c.blocks);
    final block = pages.single.contents.single;
    expect(block.lines.length, 2);
    expect(block.lines.first.text, '　　一二三四五六七八九');
    expect(block.lines.last.clines.single.isImage, isTrue);
    expect(block.lines.every((l) => l.paragraphIndex == 0), isTrue);
  });

  test('the page draws the same spans: same lines, the box at the end of the text; its placeholder maps to no character', () {
    final c = WebBookLoader.parseContent('一二三四五六七$_dp');
    final block = _engine.layout(size: _size, blocks: c.blocks).single.contents.single;
    final width = _engine.contentSize(_size).width;
    final span = HighlightApply.span(block, _style, color: const Color(0xFF000000));
    final tp = TextPainter(
      text: span,
      textAlign: HighlightApply.alignOf(block, _style),
      strutStyle: HighlightApply.strutOf(block, _style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )
      ..setPlaceholderDimensions(ReadTextBuilder.dimensionsOf(span))
      ..layout(minWidth: width, maxWidth: width);
    expect(tp.computeLineMetrics().length, block.lines.length);
    final box = tp.inlinePlaceholderBoxes!.single;
    expect(box.left, closeTo(9 * 16, 0.5));
    expect(box.right - box.left, closeTo(32, 0.5));
    expect(box.bottom - box.top, closeTo(24, 0.5));
    tp.dispose();
    // the canvas painter lays out alike
    final cp = ReadTextBuilder.painter(block, _style, width, color: const Color(0xFF000000));
    expect(cp.computeLineMetrics().length, 1);
    cp.dispose();

    final flat = HighlightApply.flatText(block);
    expect(flat, '　　一二三四五六七${ReadTextBuilder.placeholderChar}');
    expect(ReadTextBuilder.sourceOffset(block, flat.length - 1), -1);
    expect(ReadTextBuilder.sourceOffset(block, flat.length - 2), 6);
    expect(ReadTextBuilder.flatOffset(block, 6), flat.length - 2);
    // a selection over the whole block covers the text only
    expect(ReadTextBuilder.sourceRange(block, 0, flat.length), (start: 0, end: 7));
    expect(HighlightApply.flatRange(block, 0, 7), (start: 2, end: 9));
  });

  test('显示段评 off drops the bubbles, inline and alone; text, offsets and the read-aloud text do not change', () {
    final c = WebBookLoader.parseContent('一二三$_dp\n<img src="dp:7">\n四五<img src="http://h/a.png">六');
    final off = NovelViewState.paragraphComments(c, needdp: false);
    expect(identical(NovelViewState.paragraphComments(c, needdp: true), c), isTrue);
    expect(off.text, c.text);
    expect(off.blocks.length, 2);
    expect(off.blocks.first.runs.single.str, '一二三');
    expect((off.blocks.first.runs.single.start, off.blocks.first.runs.single.end), (0, 3));
    // other inline images stay
    expect([for (final r in off.blocks.last.runs) r.isImage], [false, true, false]);

    final rc = ReadChapter(BookChapter(name: '第一章'), '第一章', c);
    final segs = ReadAloudController.segmentsOf(rc, withTitle: false);
    expect([for (final s in segs) (s.text, s.start, s.end)], [('一二三', 0, 3), ('四五六', 4, 7)]);
  });

  test('rewriting the runs keeps the inline images; a paragraph left with images only gives image blocks', () {
    final c = WebBookLoader.parseContent('一二三$_dp\n四五$_dp');
    c.blocks.last.runs.first.str = '';
    final out = ChapterContent.fromBlocks(c.blocks);
    expect(out.text, '一二三');
    expect([for (final b in out.blocks) b.isImage], [false, true]);
    expect(out.blocks.first.runs.last.isImage, isTrue);
    expect((out.blocks.last.runs.single.start, out.blocks.last.runs.single.end), (3, 3));
  });
}
