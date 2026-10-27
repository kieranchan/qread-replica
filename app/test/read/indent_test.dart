// The first-line indent survives TextAlign.justify in both drawing paths (ReadTextBuilder and HighlightApply): the first body
// character starts two characters in, and the indent itself is invisible. (Ahem test font: every glyph is fontSize wide.)
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/read/api/calculate/calculate_hapter.dart';
import 'package:newread/read/setting/read_layout_style.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/content_painter.dart';
import 'package:newread/read/util/highlight_apply.dart';

const _style = ReadLayoutStyle(fontSize: 16, lineHeight: 1.5, paragraphSpacing: 8, indent: 2, padding: EdgeInsets.all(10), justify: true);

void main() {
  test('indent is kept under justify', () {
    final text = List.generate(40, (k) => String.fromCharCode(0x4e00 + k)).join();
    const engine = CalculateChapter(style: _style);
    const size = Size(200, 300);
    final pages = engine.layout(size: size, blocks: ChapterContent.fromText(text).blocks);
    final c = pages.first.contents.first;
    final width = engine.contentSize(size).width;
    final indent = c.lines.first.clines.first.prefix.length;
    expect(indent, 2);

    for (final span in [
      ReadTextBuilder.span(c, _style, color: const Color(0xFF000000)),
      HighlightApply.span(c, _style, color: const Color(0xFF000000)),
    ]) {
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr, textAlign: TextAlign.justify, textScaler: TextScaler.noScaling)
        ..layout(minWidth: width, maxWidth: width);
      final box = tp.getBoxesForSelection(TextSelection(baseOffset: indent, extentOffset: indent + 1)).first;
      expect(box.left, closeTo(indent * _style.fontSize, 0.5));
      // the second line starts at the margin
      final secondLineStart = c.lines.first.clines.fold<int>(0, (n, r) => n + r.text.length);
      final box2 = tp.getBoxesForSelection(TextSelection(baseOffset: secondLineStart, extentOffset: secondLineStart + 1)).first;
      expect(box2.left, closeTo(0, 0.5));
      tp.dispose();
    }
  });
}
