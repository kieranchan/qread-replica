// The Legado header / footer style (owner, 2026-11-03: "按照安卓的来设计"): Legado's tips (页数及进度 `1/6  0.0%`, 章节序号, the
// level in a box, 时间+电量), its defaults applied once to slots still at the original's, the text colour itself, the page typeface.
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

  test('Legado is the default style and takes its slots once; customised slots and the original style keep theirs', () async {
    final s = ReadSetting();
    expect(s.statusStyle, StatusStyle.legado);
    expect(s.slots['customHeaderLeft'], [SlotItem.time]);
    expect(s.slots['customHeaderRight'], [SlotItem.batteryBox]);
    expect(s.slots['customFooterLeft'], [SlotItem.bookName]);
    expect(s.slots['customFooterRight'], [SlotItem.pageAndTotal]);
    expect(Storage.getBool('legadoSlotsApplied'), isTrue);
    expect(s.fen, DividerMode.footer, reason: 'Legado shows a line above the footer by default');

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

    // a customised slot survives the switch
    await s.setSlot('customFooterRight', [SlotItem.time, SlotItem.batteryPercent]);
    await s.setStatusStyle(StatusStyle.qread);
    expect(s.slots['customFooterRight'], [SlotItem.time, SlotItem.batteryPercent]);
  });

  test('slots and a 分割线 already customised before the Legado update are left alone', () async {
    await Storage.setString('customFooterLeft', '[5]'); // the owner put the title there
    await Storage.setInt('fen', DividerMode.none); // and switched the line off
    final s = ReadSetting();
    expect(s.statusStyle, StatusStyle.legado);
    expect(s.slots['customFooterLeft'], [SlotItem.title]);
    expect(s.slots['customFooterRight'], [SlotItem.batteryOutside], reason: 'nothing else was touched');
    expect(s.fen, DividerMode.none);
  });

  testWidgets('the Legado footer line is one pixel edge to edge; the original keeps its inset half-point line', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = ReadSetting();
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
