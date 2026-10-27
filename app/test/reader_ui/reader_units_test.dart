// Unit tests of the reader UI helpers: highlight decorations, ReadSetting (prefs, colours, layout), tap zones, LRC, title CSS, search,
// the scroll-mode controller, progress text, route names.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/highlight_rule.dart';
import 'package:newread/pages/read/pages/lyrics_view.dart';
import 'package:newread/pages/read/pages/novel/content.dart';
import 'package:newread/pages/read/pages/novel/search_book.dart';
import 'package:newread/pages/read/pages/novel/views/turn.dart';
import 'package:newread/pages/read/reader_routes.dart';
import 'package:newread/read/api/calculate/calculate_hapter.dart';
import 'package:newread/read/model/page.dart';
import 'package:newread/read/setting/read_layout_style.dart';
import 'package:newread/read/setting/read_setting.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/css.dart';
import 'package:newread/read/util/highlight_apply.dart';
import 'package:newread/read/util/listcontroller.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

List<PageText> _layout(String text, {double fontSize = 16, Size size = const Size(300, 400)}) {
  final c = ChapterContent.fromText(text);
  return CalculateChapter(style: ReadLayoutStyle(fontSize: fontSize, stretchPages: false)).layout(size: size, blocks: c.blocks, title: '标题');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('highlight_apply', () {
    test('flatRange maps chapter offsets to painter offsets (indent skipped)', () {
      const text = '甲乙丙丁戊己庚辛\n子丑寅卯';
      final pages = _layout(text);
      final body = pages.first.contents.firstWhere((c) => c.lines.first.paragraphIndex >= 0);
      final flat = HighlightApply.flatText(body);
      expect(flat, startsWith('　　甲乙'));
      final r = HighlightApply.flatRange(body, 1, 3)!;
      expect(flat.substring(r.start, r.end), '乙丙');
      expect(HighlightApply.flatRange(body, 100, 120), isNull);
    });

    test('rule decorations and span splitting', () {
      final rules = [
        HighlightRule(name: 'q', pattern: '“[^”]*”', isRegex: true, isEnabled: true, dayColor: '#ff0000', nightColor: '#00ff00', fontWeight: 'bold'),
        HighlightRule(name: 'w', pattern: '王', isEnabled: true, dayBgColor: '#ffff00', textDecoration: 'underline'),
        HighlightRule(name: 'off', pattern: '他', isEnabled: false, dayColor: '#0000ff'),
      ];
      const flat = '他说：“王来了。”王';
      final day = HighlightApply.ruleDecos(flat, rules, night: false);
      expect(day.length, 3);
      expect(day.first.color, const Color(0xffff0000));
      expect(day.first.fontWeight, FontWeight.w700);
      expect(flat.substring(day.first.start, day.first.end), '“王来了。”');
      expect(day[1].background, const Color(0xffffff00));
      expect(day[1].decoration, TextDecoration.underline);
      final night = HighlightApply.ruleDecos(flat, rules, night: true);
      expect(night.first.color, const Color(0xff00ff00));

      final pages = _layout('他说：“王来了。”王');
      final body = pages.first.contents.firstWhere((c) => c.lines.first.paragraphIndex >= 0);
      final f = HighlightApply.flatText(body);
      final span = HighlightApply.span(body, const ReadLayoutStyle(fontSize: 16), color: Colors.black,
          decos: HighlightApply.ruleDecos(f, rules, night: false));
      expect(span.toPlainText(), f);
      final colored = <String>[];
      span.visitChildren((s) {
        if (s is TextSpan && s.style?.color == const Color(0xffff0000)) colored.add(s.text!);
        return true;
      });
      expect(colored.join(), '“王来了。”');
      expect(HighlightApply.parseColor('#80112233'), const Color(0x80112233));
      expect(HighlightApply.parseColor('bad'), isNull);
    });
  });

  group('ReadSetting', () {
    setUp(() async => newDevice());

    test('defaults, persistence, colours, layout style', () async {
      final s = ReadSetting();
      expect(s.fontSize, 30);
      expect(s.lineHeight, 2);
      expect(s.turn, TurnMode.cover);
      expect(s.darkbackground, 4);
      await s.setFontSize(80);
      expect(s.fontSize, 55);
      expect(Storage.getString(ReadSetting.fontSizeKey), '55');
      await s.setTurn(TurnMode.scroll);
      await s.setLineHeight(1.234);
      await s.setMargins(left: 20, right: 30);
      await s.setHeaderFooter(top: false);
      final again = ReadSetting();
      expect(again.turn, TurnMode.scroll);
      expect(again.lineHeight, 1.23);
      expect(again.leftMargin, 20);
      expect(again.showTop, isFalse);

      // built-in colours: #000000 has light text, the others dark text
      expect(again.config(4).backgroundColor, const Color(0xff000000));
      expect(again.config(4).textColor, Colors.white70);
      expect(again.config(0).backgroundColor, const Color(0xffe6e6e6));
      expect(again.config(0).textColor, Colors.black87);
      expect(again.config(ReadSetting.imageIdBase).image, isNotNull);
      await again.setNight(true);
      expect(again.currentBackgroundId, 4);

      final style = again.layoutStyle(const Size(390, 800), const EdgeInsets.only(top: 40));
      expect(style.padding.left, 20);
      expect(style.padding.right, 30);
      expect(style.padding.top, 40 + again.topMargin); // header hidden
      expect(style.fontSize, closeTo(55 * 390 / 750, 0.01));
      expect(again.columnsFor(const Size(390, 800)), 1);
      expect(again.columnsFor(const Size(1200, 800)), 2);
      await again.setFen(1);
      expect(again.columnsFor(const Size(1200, 800)), 1);

      final b = again.toBackGround(name: 30, themeName: '排版 1');
      expect(b.fontSize, 55);
      await again.setFontSize(20);
      await again.applyLayout(b);
      expect(again.fontSize, 55);
      expect(TurnMode.labels().length, 7);
      expect(TurnMode.labels(ios: true)[TurnMode.appleBook], '仿真翻页(IOS原生)');
    });

    test('tap zones: default grid, JSON round trip, hit test', () async {
      final d = ClickAreaSetting.defaults();
      const size = Size(300, 600);
      expect(d.hit(const Offset(150, 300), size), ClickAreaType.menu);
      expect(d.hit(const Offset(10, 300), size), ClickAreaType.previousPage);
      expect(d.hit(const Offset(290, 300), size), ClickAreaType.nextPage);
      expect(d.hit(const Offset(150, 590), size), ClickAreaType.nextPage);
      final j = d.toJson();
      expect(j['middleCenter'], 'menu');
      expect(j.keys, ClickAreaSetting.keys);
      d.areas[4] = ClickAreaType.none;
      expect(d.hasMenu, isFalse);
      await d.save();
      expect(jsonDecode(Storage.getString('turntype'))['middleCenter'], 'none');
      expect(ClickAreaSetting.load().areas[4], ClickAreaType.none);
    });
  });

  test('LRC parsing and the line at a position', () {
    final lines = parseLrc('[00:01.50]第一句\n[00:03]第二句\n没有时间\n[01:00.1]第三句');
    expect(lines.map((l) => l.text), ['第一句', '第二句', '没有时间', '第三句']);
    expect(lines.first.time, const Duration(seconds: 1, milliseconds: 500));
    expect(lines.last.time, const Duration(minutes: 1, milliseconds: 100));
    expect(lrcIndexAt(lines, const Duration(seconds: 2)), 0);
    expect(lrcIndexAt(lines, Duration.zero), -1);
    expect(lrcIndexAt(lines, const Duration(seconds: 59)), 2);
  });

  test('StyleGenUtils builds a title template and parses CSS colours', () {
    final css = StyleGenUtils.generate(const TitleStyleOptions(fontSize: 20, align: 'center', color: '#333333'));
    expect(StyleGenUtils.isValidTemplate(css), isTrue);
    expect(css, contains('font-size: 20px'));
    expect(css, contains('text-align: center'));
    expect(StyleGenUtils.parseColor('red'), const Color(0xffff0000));
    expect(StyleGenUtils.parseColor('#abc'), const Color(0xffaabbcc));
    expect(StyleGenUtils.parseColor('rgba(255, 0, 0, 0.5)'), const Color.fromARGB(128, 255, 0, 0));
    expect(StyleGenUtils.parseColor('nope'), isNull);
  });

  test('in-book search finds every hit with context', () {
    final hits = searchText('甲乙丙\n乙丁乙', '乙', 3, '第四章', around: 1);
    expect(hits.map((h) => h.start), [1, 4, 6]);
    expect(hits.first.context, '甲乙丙');
    expect(hits.first.chapterIndex, 3);
    expect(searchText('abc', '', 0, ''), isEmpty);
  });

  test('footer progress text', () {
    expect(progressText(ProgressMode.hidden, pageNum: 1, totalPage: 3, bookProgress: 0.5), '');
    expect(progressText(ProgressMode.chapter, pageNum: 2, totalPage: 3, bookProgress: 0.5), '2/3');
    expect(progressText(ProgressMode.book, pageNum: 2, totalPage: 3, bookProgress: 0.123), '12.3%');
    expect(progressText(ProgressMode.both, pageNum: 2, totalPage: 3, bookProgress: 0.5), '2/3  50.0%');
  });

  test('scroll-mode controller keeps chapter windows in order', () {
    final c = ReadListController();
    final p = [PageText(), PageText(), PageText()];
    c.reset(2, '三', p);
    c.append(3, '四', [PageText()]);
    c.append(3, '四', [PageText()]); // ignored
    c.prepend(1, '二', [PageText(), PageText()]);
    expect(c.items.map((e) => '${e.chapterIndex}:${e.pageIndex}'), ['1:0', '1:1', '2:0', '2:1', '2:2', '3:0']);
    expect(c.firstChapter, 1);
    expect(c.lastChapter, 3);
    expect(c.items[2].totalPage, 3);
    c.dispose();
  });

  test('routes handled by the reader area', () {
    expect(ReaderRoutes.names, containsAll(['txtrule_page', 'replace_page', 'highlight_page', 'read_setting_page']));
    for (final n in ['txtrule_page', 'replace_page', 'highlight_page', 'read_setting_page']) {
      expect(ReaderRoutes.pageFor(n), isNotNull, reason: n);
    }
    expect(ReaderRoutes.pageFor('read_page', arguments: Book(bookUrl: 'x')), isNotNull);
    expect(ReaderRoutes.pageFor('gallery_viewer_page', arguments: ['a.png']), isNotNull);
    expect(ReaderRoutes.pageFor('unknown'), isNull);
  });
}
