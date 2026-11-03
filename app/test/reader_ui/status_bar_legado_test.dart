// The Legado header / footer style (owner, 2026-11-03: "按照安卓的来设计", then "用回上一个版本" — so an option, not the default):
// Legado's tips (页数及进度 `1/6  0.0%`, 章节序号, the level in a box, 时间+电量), its defaults taken by the slots still at the
// original's when the style is switched on, the text colour itself, the page typeface, the footer line.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/content.dart';
import 'package:newread/pages/read/pages/novel/views/battery_painter.dart';
import 'package:newread/read/setting/read_setting.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

void main() {
  setUp(() async {
    await newDevice();
    ReaderBattery.last = (level: 69, charging: false);
    ReaderBattery.read = () async => (level: 69, charging: false);
  });

  test('the original look is the default; switching to Legado takes its slots and 分割线, switching back restores them', () async {
    final s = ReadSetting();
    expect(s.statusStyle, StatusStyle.qread);
    expect(s.slots['customHeaderLeft'], [SlotItem.title]);
    expect(s.slots['customFooterRight'], [SlotItem.batteryOutside]);
    expect(s.fen, DividerMode.none);

    await s.setStatusStyle(StatusStyle.legado);
    expect(s.slots['customHeaderLeft'], [SlotItem.time]);
    expect(s.slots['customHeaderRight'], [SlotItem.batteryBox]);
    expect(s.slots['customFooterLeft'], [SlotItem.bookName]);
    expect(s.slots['customFooterRight'], [SlotItem.pageAndTotal]);
    expect(s.fen, DividerMode.footer, reason: 'Legado shows a line above the footer by default');
    expect(ReadSetting().statusStyle, StatusStyle.legado);
    expect(ReadSetting().slots['customFooterRight'], [SlotItem.pageAndTotal]);

    // switching back to the original style restores its slots and its 分割线, switching again returns to Legado's
    await s.setStatusStyle(StatusStyle.qread);
    expect(s.slots['customFooterRight'], [SlotItem.batteryOutside]);
    expect(s.fen, DividerMode.none);
    expect(ReadSetting().statusStyle, StatusStyle.qread);
    expect(ReadSetting().fen, DividerMode.none);
    await s.setStatusStyle(StatusStyle.legado);
    expect(s.slots['customFooterLeft'], [SlotItem.bookName]);
    expect(s.fen, DividerMode.footer);

    // a 分割线 the owner chose survives the switch
    await s.setFen(DividerMode.both);
    await s.setStatusStyle(StatusStyle.qread);
    expect(s.fen, DividerMode.both);
    expect(ReadSetting().fen, DividerMode.both);

    // a customised slot survives the switch, the others still swap
    await s.setSlot('customFooterRight', [SlotItem.time, SlotItem.batteryPercent]);
    await s.setStatusStyle(StatusStyle.qread);
    expect(s.slots['customFooterRight'], [SlotItem.time, SlotItem.batteryPercent]);
    expect(s.slots['customFooterLeft'], [SlotItem.time]);
    expect(s.slots['customHeaderLeft'], [SlotItem.title]);
  });

  test('switching to Legado: a customised slot or 分割线 is left alone, the other slots take the Legado defaults', () async {
    await Storage.setString('customHeaderLeft', '[5,0]'); // the owner's phone: 标题 + 时间 in the header
    await Storage.setInt('fen', DividerMode.both); // and both lines on
    final s = ReadSetting();
    await s.setStatusStyle(StatusStyle.legado);
    expect(s.slots['customHeaderLeft'], [SlotItem.title, SlotItem.time]);
    expect(s.slots['customHeaderRight'], [SlotItem.batteryBox]);
    expect(s.slots['customFooterLeft'], [SlotItem.bookName]);
    expect(s.slots['customFooterRight'], [SlotItem.pageAndTotal]);
    expect(s.fen, DividerMode.both);
  });

  test('a phone that had the 2026-11-03 build (Legado as the default, nothing applied) keeps the original look', () async {
    await Storage.setBool('legadoSlotsApplied', true);
    final s = ReadSetting();
    expect(s.statusStyle, StatusStyle.qread);
    expect(s.fen, DividerMode.none);
    expect(s.slots['customFooterRight'], [SlotItem.batteryOutside]);
  });

  testWidgets('the Legado footer line is one pixel edge to edge; the original keeps its inset half-point line', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = ReadSetting();
    await s.setStatusStyle(StatusStyle.legado);
    Widget bar() => MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 400, child: ReaderStatusBar(setting: s, header: false, color: Colors.black, title: '', bookName: '书')),
          ),
        );
    await tester.pumpWidget(bar());
    final legado = tester.widget<Container>(find.byType(Container));
    expect(legado.constraints?.maxHeight, closeTo(0.5, 0.001));
    expect(legado.margin, isNull);
    final painted = find.descendant(of: find.byType(ReaderStatusBar), matching: find.byType(ColoredBox));
    expect(tester.getSize(painted).width, 400);
    expect(legadoLineHeight(1), 1);
    expect(legadoLineHeight(2), 0.5);

    await s.setStatusStyle(StatusStyle.qread);
    await s.setFen(DividerMode.footer);
    await tester.pumpWidget(bar());
    final original = tester.widget<Container>(find.byType(Container));
    expect(original.margin, const EdgeInsets.only(left: 16, right: 16));
    expect(tester.getSize(painted).width, 400 - 32);
  });

  testWidgets('Legado items render their texts, the battery box and the page typeface', (tester) async {
    final s = ReadSetting();
    await s.setStatusStyle(StatusStyle.legado);
    s.fontFamily = 'TestSerif';
    await s.setSlot('customFooterLeft', [SlotItem.chapterAndTotal]);
    await s.setSlot('customFooterCenter', [SlotItem.timeBatteryPercent, SlotItem.batteryPercent]);
    await s.setSlot('customFooterRight', [SlotItem.pageAndTotal, SlotItem.timeBatteryBox]);
    Widget bar() => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: ReaderStatusBar(
                setting: s,
                header: false,
                color: Colors.black,
                title: '第三章',
                bookName: '书名',
                pageNum: 2,
                totalPage: 6,
                bookProgress: 0.1234,
                chapterIndex: 4,
                chapterCount: 120,
                clock: () => '15:12',
              ),
            ),
          ),
        );
    await tester.pumpWidget(bar());
    await tester.pump();
    expect(find.text('5/120'), findsOneWidget);
    expect(find.text('2/6  12.3%'), findsOneWidget);
    expect(find.text('15:12 69%'), findsOneWidget);
    expect(find.text('69%'), findsOneWidget);
    expect(find.text('15:12  '), findsOneWidget);
    expect(find.byType(LegadoBatteryBox), findsOneWidget);
    expect(find.text('69'), findsOneWidget);
    final t = tester.widget<Text>(find.text('5/120'));
    expect(t.style?.fontFamily, 'TestSerif');
    expect(t.style?.fontSize, 12);

    // the original style does not use the page typeface (the reader rebuilds its pages on a setting change)
    await s.setStatusStyle(StatusStyle.qread);
    await tester.pumpWidget(bar());
    await tester.pump();
    expect(tester.widget<Text>(find.text('5/120')).style?.fontFamily, isNull);
  });

  test('Legado style: the header shows only while the system status bar is hidden (headerMode 0)', () async {
    final s = ReadSetting();
    await s.setStatusStyle(StatusStyle.legado);
    expect(s.hidetop, isTrue);
    expect(s.headerShown, isTrue);
    expect(s.headerHeight, s.statusFontSize + 14);
    await s.setHidetop(false);
    expect(s.headerShown, isFalse);
    expect(s.headerHeight, 0);
    await s.setStatusStyle(StatusStyle.qread); // the original always draws it
    expect(s.headerShown, isTrue);
    await s.setHeaderFooter(top: false);
    expect(s.headerShown, isFalse);
  });

  test('texts of the Legado items', () {
    final bar = ReaderStatusBar(setting: ReadSetting(), header: false, color: Colors.black, title: '', pageNum: 3, totalPage: 0, bookProgress: 1.5, chapterIndex: 0, chapterCount: 0);
    expect(bar.pageAndTotalText(), '3/-  100.0%');
    expect(bar.chapterAndTotalText(), '1/-');
    expect(legadoProgressText(0.0), '0.0%');
    expect(legadoProgressText(0.07777), '7.8%');
  });
}
