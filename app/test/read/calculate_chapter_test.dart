// Paging invariants of the layout engine (flutter_test renders with the Ahem font: every glyph is fontSize wide and tall).

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/read/api/calculate/calculate_hapter.dart';
import 'package:newread/read/model/line.dart';
import 'package:newread/read/model/mykey.dart';
import 'package:newread/read/model/mypage.dart';
import 'package:newread/read/model/page.dart';
import 'package:newread/read/setting/read_layout_style.dart';
import 'package:newread/read/util/chapter_content.dart';

String _sampleText({int paragraphs = 40}) {
  final sb = StringBuffer();
  for (var i = 0; i < paragraphs; i++) {
    // Paragraphs of different length, some shorter than a line, some long enough to span pages.
    final n = 5 + (i * 37) % 120;
    sb.write(List.generate(n, (k) => String.fromCharCode(0x4e00 + (i * 31 + k * 7) % 400)).join());
    sb.write('\n');
    if (i % 5 == 0) sb.write('\n');
  }
  return sb.toString();
}

const _style = ReadLayoutStyle(
  fontSize: 16,
  lineHeight: 1.5,
  paragraphSpacing: 8,
  indent: 2,
  padding: EdgeInsets.all(10),
  titleFontSize: 24,
  titleTopMargin: 6,
  titleBottomMargin: 12,
);

void _checkInvariants(List<PageText> pages, ChapterContent content, Size size, ReadLayoutStyle style, {bool title = false}) {
  final area = size.height - style.padding.vertical;
  // Source characters covered exactly once, in order.
  final covered = List<int>.filled(content.text.length, 0);
  var lastEnd = 0;
  for (final p in pages) {
    var used = 0.0;
    for (var ci = 0; ci < p.contents.length; ci++) {
      final c = p.contents[ci];
      used += c.height + (ci > 0 ? style.paragraphSpacing : 0);
      for (final l in c.lines) {
        for (final cl in l.clines) {
          if (cl.start < 0) continue;
          expect(cl.end - cl.start, cl.str.length, reason: 'offsets must match the text of ${cl.str}');
          expect(content.text.substring(cl.start, cl.end), cl.str);
          for (var k = cl.start; k < cl.end; k++) {
            covered[k]++;
          }
          expect(cl.start >= lastEnd - 0, isTrue, reason: 'runs are in reading order');
        }
      }
    }
    // no overflow (allow 1e-3 for floating point)
    expect(used, lessThanOrEqualTo(area + 1e-3), reason: 'page content ($used) must fit the area ($area)');
    expect(p.start, lessThanOrEqualTo(p.end));
    lastEnd = p.end;
  }
  for (var i = 0; i < content.text.length; i++) {
    final ch = content.text[i];
    final blank = ch == '\n' || ch == ' ' || ch == '　' || ch == '\t';
    if (blank) {
      expect(covered[i], lessThanOrEqualTo(1));
    } else {
      expect(covered[i], 1, reason: 'char $i (${ch.codeUnitAt(0)}) must be shown exactly once');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = Size(200, 300);
  const engine = CalculateChapter(style: _style);

  test('every character is shown exactly once and no page overflows', () {
    final content = ChapterContent.fromText(_sampleText());
    final pages = engine.layout(size: size, blocks: content.blocks, title: '第一章 测试');
    expect(pages.length, greaterThan(3));
    _checkInvariants(pages, content, size, _style, title: true);
    // The title is on the first page only.
    expect(pages.first.contents.first.lines.first.clines.first.ish, isTrue);
    for (final p in pages.skip(1)) {
      expect(p.contents.any((c) => c.lines.any((l) => l.paragraphIndex < 0)), isFalse);
    }
  });

  test('layout is deterministic and survives a JSON round trip', () {
    final content = ChapterContent.fromText(_sampleText(paragraphs: 12));
    final a = engine.layout(size: size, blocks: content.blocks, title: 'T');
    final b = engine.layout(size: size, blocks: content.blocks, title: 'T');
    expect(a.map((p) => p.toJson()).toList(), b.map((p) => p.toJson()).toList());
    final restored = a.map((p) => PageText.fromJson(p.toJson())).toList();
    expect(restored.map((p) => p.toJson()).toList(), a.map((p) => p.toJson()).toList());
  });

  test('first-line indent is a prefix without source offsets', () {
    final content = ChapterContent.fromText('第一段文字内容比较短。\n\n第二段。');
    final pages = engine.layout(size: size, blocks: content.blocks);
    final first = pages.first.contents.first.lines.first.clines.first;
    expect(first.prefix, '　　');
    expect(first.isfirst, isTrue);
    expect(first.start, 0);
    expect(first.end - first.start, first.str.length);
    // second paragraph starts after the blank line
    final second = pages.first.contents[1].lines.first.clines.first;
    expect(content.text.substring(second.start, second.end), startsWith('第二段'));
  });

  test('page <-> offset mapping round trips and survives a font size change', () {
    final content = ChapterContent.fromText(_sampleText());
    final small = engine.layout(size: size, blocks: content.blocks);
    final big = CalculateChapter(style: _style.copyWith(fontSize: 22)).layout(size: size, blocks: content.blocks);
    expect(big.length, greaterThan(small.length));

    final total = CalculateChapter.textLengthOf(small);
    expect(total, greaterThan(1000));
    for (var i = 0; i < small.length; i++) {
      final off = CalculateChapter.offsetForPage(small, i);
      expect(CalculateChapter.pageIndexForOffset(small, off), i, reason: 'start of page $i maps back to page $i');
      if (small[i].end > small[i].start) {
        expect(CalculateChapter.pageIndexForOffset(small, small[i].end - 1), i);
      }
    }

    // Read at page 4 of the small layout, change the font: the new page must contain the same character.
    final off = CalculateChapter.offsetForPage(small, 4);
    final progress = CalculateChapter.progressForPage(small, 4);
    final pBig = CalculateChapter.pageIndexForOffset(big, off);
    expect(big[pBig].start, lessThanOrEqualTo(off));
    expect(pBig == big.length - 1 || big[pBig + 1].start > off, isTrue);
    // The fraction (what Book.durChapterPos stores) lands on the same neighbourhood.
    final pFrac = CalculateChapter.pageIndexForProgress(big, progress);
    expect((big[pFrac].start - off).abs(), lessThan(big.first.end * 2 + 400));
    expect(CalculateChapter.pageIndexForProgress(small, progress), 4);
  });

  test('last page is not stretched, full pages are filled to the bottom', () {
    final content = ChapterContent.fromText(_sampleText());
    final pages = engine.layout(size: size, blocks: content.blocks, title: 'T');
    expect(pages.last.lineheight, 0);
    final area = size.height - _style.padding.vertical;
    var stretched = 0;
    for (final p in pages.take(pages.length - 1)) {
      if (p.lineheight > 0) {
        stretched++;
        final lines = p.contents.where((c) => c.lines.first.paragraphIndex >= 0).fold<int>(0, (n, c) => n + c.line);
        final gaps = (p.contents.length - 1) * _style.paragraphSpacing;
        final total = p.contents.fold<double>(0, (s, c) => s + c.height) + gaps + p.lineheight * lines;
        expect(total, closeTo(area, 0.01));
      }
    }
    expect(stretched, greaterThan(0));
  });

  test('double column mode: narrower pages, even page count with a blank page', () {
    final content = ChapterContent.fromText(_sampleText(paragraphs: 25));
    const wide = Size(420, 300);
    final two = CalculateChapter(style: _style.copyWith(columns: 2)).layout(size: wide, blocks: content.blocks);
    expect(two.length.isEven, isTrue);
    final colW = CalculateChapter(style: _style.copyWith(columns: 2)).contentSize(wide).width;
    expect(colW, closeTo((420 - 20 - 24) / 2, 0.001));
    // a column holds at most colW/fontSize glyphs per line
    for (final p in two) {
      for (final l in p.lines) {
        expect(l.text.length * 16, lessThanOrEqualTo(colW + 0.001 + 16 * 2));
      }
    }
    final one = engine.layout(size: wide, blocks: content.blocks);
    expect(two.length, greaterThanOrEqualTo(one.length));
  });

  test('volume title gets its own centred page', () {
    final pages = engine.layout(size: size, blocks: ChapterContent.fromText('正文').blocks, title: '第一卷', isVolume: true);
    expect(pages.length, 2);
    expect(pages.first.iscentos, isTrue);
    expect(pages.first.contents.single.lines.first.clines.first.str, '第一卷');
    expect(pages.last.contents.single.lines.first.clines.first.start, 0);
  });

  test('images: sized from the resolver (100x100 fallback), moved to the next page when they do not fit', () async {
    final text = ChapterContent.fromText('一段文字\n').blocks;
    final blocks = <CalcuPages>[
      ...text,
      CalcuPages.image(CLine(type: CLineType.image, href: '/tmp/a.png', start: 5, end: 5)),
      CalcuPages.image(CLine(type: CLineType.image, href: '/tmp/big.png', start: 5, end: 5)),
    ];
    final calc = CalculateChapter(
      style: _style,
      imageSizeOf: (src) => src.endsWith('big.png') ? const Size(1000, 4000) : null,
    );
    final pages = await calc.calculate(size: size, blocks: blocks);
    final images = [for (final p in pages) ...p.contents.where((c) => c.isImage)];
    expect(images.length, 2);
    expect(images.first.height, 100); // fallback 100x100
    final area = calc.contentSize(size);
    expect(images.last.height, closeTo(area.height, 0.001)); // scaled to the page
    expect(pages.length, 2);
    expect(pages.first.start, 0);
    // anchors work for images through offsets
    expect(CalculateChapter.pageIndexForOffset(pages, 5), pages.length - 1);
  });

  test('anchors map to pages', () {
    final blocks = [
      CalcuPages.text([CLine(str: List.filled(300, '字').join(), start: 0, end: 300, isfirst: true)]),
      CalcuPages.text([CLine(str: '目标段落', start: 301, end: 305, isfirst: true, id: 'target')]),
    ];
    final pages = engine.layout(size: size, blocks: blocks);
    final idx = CalculateChapter.pageIndexForAnchor(pages, 'target');
    expect(idx, greaterThan(0));
    expect(CalculateChapter.pageIndexForAnchor(pages, 'missing'), -1);
    final loc = CalculateChapter.locate(pages, 302);
    expect(loc, isNotNull);
    expect(loc!.page, idx);
  });

  test('MyPage.fromPages, JSON round trip and Mykey', () {
    final content = ChapterContent.fromText(_sampleText(paragraphs: 10));
    final pages = engine.layout(size: size, blocks: content.blocks, title: '标题');
    final my = MyPage.fromPages(pages: pages, index: 0, chapterIndex: 3, chapterName: '标题', progress: 0.25);
    expect(my.isFirstPageOfChapter, isTrue);
    expect(my.totalPage, pages.length);
    expect(my.bigtitle, greaterThan(0));
    final again = MyPage.fromJson(my.toJson());
    expect(again.toJson(), my.toJson());

    final two = MyPage.fromPages(pages: pages, index: 3, chapterIndex: 3, chapterName: 'x', columns: 2);
    expect(two.pageNum, 3); // rounded down to an even page index (2) -> number 3
    expect(two.text2, isNotNull);

    final k1 = Mykey('b', 1, _style.signature);
    final k2 = Mykey('b', 1, _style.copyWith(fontSize: 17).signature);
    expect(k1 == Mykey('b', 1, _style.signature), isTrue);
    expect(k1 == k2, isFalse);
  });

  test('degenerate sizes do not loop forever', () {
    final content = ChapterContent.fromText('字字字字字字字字字字字字字字字字字字字字');
    final pages = engine.layout(size: const Size(30, 30), blocks: content.blocks);
    expect(pages, isNotEmpty);
    expect(CalculateChapter.textLengthOf(pages), 20);
    final empty = engine.layout(size: size, blocks: const []);
    expect(empty.length, 1);
  });
}
