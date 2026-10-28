// Reader fidelity: highlight-rule metrics inside the measurement (0xf0caec), 谷歌汉字 (0x673250), TXT rule selection (0x259668).
// flutter_test renders with the Ahem font: every glyph is fontSize wide and tall.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/highlight_rule.dart';
import 'package:newread/models/txt_toc_rule.dart';
import 'package:newread/read/api/calculate/calculate_hapter.dart';
import 'package:newread/read/model/line.dart';
import 'package:newread/read/model/page.dart';
import 'package:newread/read/setting/read_layout_style.dart';
import 'package:newread/read/txt/text_encoding.dart';
import 'package:newread/read/txt/text_file.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/content_painter.dart';
import 'package:newread/read/util/highlight_apply.dart';
import 'package:newread/read/util/read.dart';

const _base = ReadLayoutStyle(fontSize: 10, lineHeight: 1.5, paragraphSpacing: 0, indent: 0, padding: EdgeInsets.zero);

List<CLine> _runs(List<PageText> pages) => [
      for (final p in pages)
        for (final c in p.contents)
          for (final l in c.lines) ...l.clines,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('highlight rule metrics in CalculateChapter', () {
    final text = '${'甲' * 15}重点${'乙' * 15}\n${'丙' * 40}';
    final content = ChapterContent.fromText(text);
    const size = Size(100, 1000);

    test('values: px / em / % / plain, line height multiple or px', () {
      expect(RuleMetric.size('16px', 10), 16);
      expect(RuleMetric.size('1.5em', 10), 15);
      expect(RuleMetric.size('200%', 10), 20);
      expect(RuleMetric.size('12', 10), 12);
      expect(RuleMetric.size('', 10), isNull);
      expect(RuleMetric.height('2', 10), 2);
      expect(RuleMetric.height('30px', 10), 3);
      final rules = RuleMetric.fromRules([
        HighlightRule(pattern: 'a', isEnabled: true, dayColor: '#ff0000'), // colour only: not a metric rule
        HighlightRule(pattern: 'b', isEnabled: true, fontSize: '2em'),
        HighlightRule(pattern: 'c', isEnabled: false, fontSize: '2em'),
      ]);
      expect(rules.map((r) => r.pattern), ['b']);
      expect(_base.copyWith(metricRules: rules).signature, isNot(_base.signature));
    });

    test('the matched run is split out, tagged rule:N, measured larger; offsets stay exact; the line grows', () {
      final plain = const CalculateChapter(style: _base).layout(size: size, blocks: content.blocks);
      final style = _base.copyWith(metricRules: [const RuleMetric(pattern: '重点', fontSize: '2em', lineHeight: '2')]);
      final ruled = CalculateChapter(style: style).layout(size: size, blocks: content.blocks);

      final hit = _runs(ruled).singleWhere((r) => r.str == '重点');
      expect(hit.styles, contains('${CLineStyle.rulePrefix}0'));
      expect(text.substring(hit.start, hit.end), '重点');
      for (final r in _runs(ruled)) {
        if (r.start >= 0) expect(text.substring(r.start, r.end), r.str);
      }
      expect(_runs(ruled).where((r) => r.start >= 0).map((r) => r.str).join(), text.replaceAll('\n', ''));

      // 2em glyphs need more width: the first paragraph breaks differently, and the line holding the match is 2 x 20 px tall
      final firstPlain = plain.first.contents.first;
      final firstRuled = ruled.first.contents.first;
      expect(firstRuled.height, greaterThan(firstPlain.height));
      expect(style.textStyle({'${CLineStyle.rulePrefix}0'}).fontSize, 20);
      expect(style.textStyle({'${CLineStyle.rulePrefix}0'}).height, 2);
      expect(style.textStyle(const {}).fontSize, 10);

      // drawing uses the same styles and a strut that lets the line grow, so the painted block is as tall as measured
      final tp = ReadTextBuilder.painter(firstRuled, style, size.width, color: const Color(0xFF000000));
      expect(tp.height, closeTo(firstRuled.height, 0.5));
      expect(HighlightApply.strutOf(firstRuled, style).forceStrutHeight, isFalse);
      expect(HighlightApply.strutOf(plain.first.contents.first, _base).forceStrutHeight, isTrue);
      tp.dispose();
    });

    test('pages never overflow with grown lines', () {
      final long = ChapterContent.fromText(List.filled(30, '${'字' * 12}重点${'字' * 12}').join('\n'));
      final style = _base.copyWith(metricRules: [const RuleMetric(pattern: '重点', fontSize: '30px')]);
      const page = Size(100, 120);
      final pages = CalculateChapter(style: style).layout(size: page, blocks: long.blocks);
      expect(pages.length, greaterThan(1));
      for (final p in pages) {
        final used = p.contents.fold<double>(0, (a, c) => a + c.height);
        expect(used, lessThanOrEqualTo(page.height + 1e-3));
      }
      expect(_runs(pages).where((r) => r.start >= 0).map((r) => r.str).join(), long.text.replaceAll('\n', ''));
    });
  });

  test('谷歌汉字: offered after 默认字体 (0x673250) and loaded from the bundled NotoSansSC-Regular.ttf', () async {
    expect(ReaderFonts.builtin.map((f) => f.label), ['默认字体', '谷歌汉字', '阿里黑体', '阿里圆体']);
    expect(ReaderFonts.builtin[1].family, 'NotoSansSC_regular');
    expect(await ReaderFonts.ensure(ReaderFonts.googleFamily), isTrue);
  });

  group('TXT rule selection (0x259668)', () {
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
    final text = '序章 开始\n正文\n第一章 甲\n正文\n第二章 乙\n正文\n第三章 丙\n正文\n';
    final enc = TextEncodings.detect(bytes(text));

    test('the rule with the most matches wins, wherever it is in the list', () {
      final r = TextFile.splitBytes(bytes(text), enc, [
        TxtTocRule(name: '序章', rule: r'^序章.*$', isEnabled: true),
        TxtTocRule(name: '章', rule: r'^第.章.*$', isEnabled: true),
      ]);
      expect(r.ruleName, '章');
      expect(r.chapters.map((c) => c.name), contains('第三章 丙'));
    });

    test('ties go to the rule higher in the list; one match is enough', () {
      final tie = TextFile.splitBytes(bytes(text), enc, [
        TxtTocRule(name: 'A', rule: r'^第[一二三]章.*$', isEnabled: true),
        TxtTocRule(name: 'B', rule: r'^第.章 .$', isEnabled: true),
      ]);
      expect(tie.ruleName, 'A');
      final one = TextFile.splitBytes(bytes(text), enc, [TxtTocRule(name: '序章', rule: r'^序章.*$', isEnabled: true)]);
      expect(one.ruleName, '序章');
    });
  });
}
