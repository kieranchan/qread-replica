// Highlight rules: the original's quick regex presets, background images (nine-patch slice, opacity, 延展区域) from the rule fields, the
// painter behind the text, and the editor's 上传背景图 / 重置.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/app_dirs.dart';
import 'package:newread/models/highlight_rule.dart';
import 'package:newread/pages/highlight/highlight_rule_edit.dart';
import 'package:newread/pages/read/pages/novel/theme_page.dart';
import 'package:newread/pages/replace/replace_rule_help.dart';
import 'package:newread/read/util/highlight_apply.dart';
import 'package:newread/read/util/highlight_bg.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

void main() {
  late TestDevice device;
  setUp(() async {
    device = await newDevice();
    Toast.log.clear();
    Toast.sink = (_, _) {};
  });

  test('quick presets are the original 16 and all compile', () {
    expect(HighlightRuleEditPresets.quick.length, 16);
    expect(HighlightRuleEditPresets.quick['中文引号对话'], '[“](.*?)[”]');
    for (final p in HighlightRuleEditPresets.quick.values) {
      RegExp(p);
    }
    expect(RegExp(HighlightRuleEditPresets.quick['章节标题']!).hasMatch('第十二章'), isTrue);
  });

  test('rule background image fields -> deco', () {
    final r = HighlightRule(
      pattern: '王',
      isEnabled: true,
      dayBgImage: '@high/a.png',
      dayBgImageOpacity: 0.5,
      dayBgImagePadding: [2, 4, 6, 8],
      dayBgImageStretch: [10, 20, 30, 40],
      textDecoration: 'underline wavy',
      fontWeight: 'medium',
    );
    final d = HighlightApply.ruleDecos('一王二', [r], night: false).single;
    expect(d.bgImage!.path, '@high/a.png');
    expect(d.bgImage!.alpha, 0.5);
    expect(d.bgImage!.padding, const EdgeInsets.fromLTRB(2, 4, 6, 8));
    expect(d.bgImage!.centerSlice(100, 200), const Rect.fromLTRB(10, 60, 80, 120));
    expect(d.decorationStyle, TextDecorationStyle.wavy);
    expect(d.fontWeight, FontWeight.w500);
    expect(HighlightApply.ruleDecos('一王二', [r], night: true).single.bgImage, isNull);
    expect(HighlightBgImages.resolve('@high/a.png'), '${AppDirs.path('high')}/a.png');
  });

  testWidgets('the painter draws the nine-patch over the line boxes of the range', (tester) async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 30, 30), Paint()..color = Colors.red);
    final img = (await tester.runAsync(() => rec.endRecording().toImage(30, 30)))!;
    HighlightBgImages.put('@high/t.png', img);
    const span = TextSpan(text: '一二三四五六七八九十', style: TextStyle(fontSize: 20));
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout(maxWidth: 100);
    final rects = NinePatchPainter.lineRects(tp, 2, 8);
    expect(rects.length, 2, reason: 'the range wraps onto a second line');
    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 100,
        child: CustomPaint(
          painter: NinePatchPainter(span: span, align: TextAlign.left, strut: null, ranges: [(2, 8, const RuleBgImage('@high/t.png'))]),
          child: const Text.rich(span, textDirection: TextDirection.ltr),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    HighlightBgImages.evict('@high/t.png');
  });

  testWidgets('editor: 上传背景图 copies into @high, 重置 restores the lines', (tester) async {
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final src = File('${device.dir.path}/bg.png')..writeAsBytesSync(List.filled(100, 1));
    HighlightRuleEdit.pickImage = () async => src.path;
    await tester.pumpWidget(const MaterialApp(home: HighlightRuleEdit()));
    await tester.tap(find.byKey(const ValueKey('hl_bg_upload')));
    for (var i = 0; i < 100 && find.text('更换背景图').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('更换背景图'), findsOneWidget);
    expect(find.text('拖拽 4 条线划分九宫格'), findsOneWidget);
    expect(Directory(AppDirs.path('high')).listSync(), hasLength(1));
    expect(find.textContaining('左 30% / 右 30%'), findsOneWidget);
    await tester.tap(find.text('移除'));
    await tester.pump();
    expect(find.text('上传背景图'), findsOneWidget);
  });

  testWidgets('净化帮助 shows the original texts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReplaceRuleHelp()));
    expect(find.text('轻悦时光替换净化规则'), findsOneWidget);
    expect(find.text(ReplaceRuleHelp.ruleText), findsOneWidget);
    expect(find.textContaining('@js:'), findsOneWidget);
  });

  testWidgets('取色: the centre pixel of the background image', (tester) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 9, 9), Paint()..color = const Color(0xFF000000));
    c.drawRect(const Rect.fromLTWH(3, 3, 3, 3), Paint()..color = const Color(0xFF12AB34));
    final png = await tester.runAsync(() async {
      final img = await rec.endRecording().toImage(9, 9);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      return d!.buffer.asUint8List();
    });
    final hex = await tester.runAsync(() => ThemePage.centerColor(png!));
    expect(hex, '#12ab34');
  });
}
