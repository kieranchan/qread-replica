// Reader settings recovered from the original: prefs keys (font size `fontSizedefault`, `fan` = 翻页距离, `simplified1`, `fen` = 分割线,
// `ispad` = 双列), the custom header / footer slots and their defaults, 屏幕常亮 (`wakelockTimeout` timer), the status bar and the
// 更多设置 page.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/read/pages/novel/content.dart';
import 'package:newread/pages/read/pages/novel/read_more_setting.dart';
import 'package:newread/pages/read/pages/novel/views/battery_painter.dart';
import 'package:newread/read/setting/read_setting.dart';
import 'package:newread/read/util/read.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

void main() {
  setUp(() async {
    await newDevice();
    Toast.log.clear();
    Toast.sink = (_, _) {};
    UserSession.isvip = false;
    ReaderBattery.read = () async => (level: 76, charging: false);
  });

  test('keys and defaults of the original', () async {
    final s = ReadSetting();
    expect(ReadSetting.fontSizeKey, 'fontSizedefault');
    expect(s.fontPx(), 30);
    expect(s.fan, 5);
    expect(s.simplified, FanMode.off);
    expect(s.wakelockTimeout, WakeMode.always);
    expect(s.statusFontSize, 12);
    await s.setInt('headerFooterFontSize', 30);
    expect(s.statusFontSize, 25); // painted size is clamped to 8..25 (0x6342b8)
    await s.setFan(500);
    expect(Storage.getString('fan'), '200');
    await s.setSimplified(FanMode.toTraditional);
    expect(Storage.getString('simplified1'), '2');
    await s.setFen(DividerMode.both);
    expect(Storage.getString('fen'), '3');

    // slots: defaults until written, then the JSON list
    expect(s.slots['customHeaderLeft'], [SlotItem.title]);
    expect(s.slots['customFooterLeft'], [SlotItem.time]);
    expect(s.slots['customFooterCenter'], [SlotItem.chapterProgress]);
    expect(s.slots['customFooterRight'], [SlotItem.batteryOutside]);
    expect(s.slots['customHeaderRight'], isEmpty);
    await s.setSlot('customHeaderRight', [SlotItem.bookName, SlotItem.time]);
    expect(jsonDecode(Storage.getString('customHeaderRight')), [6, 0]);
    await s.setSlot('customFooterLeft', []);
    final again = ReadSetting();
    expect(again.slots['customHeaderRight'], [6, 0]);
    expect(again.slots['customFooterLeft'], isEmpty); // an empty list stays empty
    expect(SlotItem.names, ['时间', '内置百分比电池', '外置百分比电池', '章节进度', '全文进度', '标题', '书名']);
  });

  test('屏幕常亮: 0 system, -1 always, minutes idle timer', () async {
    final calls = <bool>[];
    ReaderWakelock.toggle = (on) async => calls.add(on);
    ReaderWakelock.tick = const Duration(hours: 1); // the test drives check()
    addTearDown(ReaderWakelock.stop);

    await ReaderWakelock.start(WakeMode.system);
    expect(calls, isEmpty);
    expect(ReaderWakelock.timerRunning, isFalse);

    await ReaderWakelock.start(WakeMode.always);
    expect(calls, [true]);
    expect(ReaderWakelock.timerRunning, isFalse);

    await ReaderWakelock.start(1); // releases the permanent lock, then runs the 60 s timer
    expect(calls, [true, false]);
    expect(ReaderWakelock.timerRunning, isTrue);
    final t0 = ReaderWakelock.lastActive!;
    await ReaderWakelock.check(t0.add(const Duration(seconds: 10)));
    expect(calls.last, isTrue);
    await ReaderWakelock.check(t0.add(const Duration(seconds: 61)));
    expect(calls.last, isFalse);
    ReaderWakelock.keepAwake = true; // audio playing renews the activity
    await ReaderWakelock.check(t0.add(const Duration(seconds: 200)));
    ReaderWakelock.keepAwake = false;
    await ReaderWakelock.check(t0.add(const Duration(seconds: 210)));
    expect(calls.last, isTrue);
    expect(WakeMode.seconds(10), 600);
    expect(WakeMode.labels.values, ['跟随系统', '1分钟', '2分钟', '5分钟', '10分钟', '常亮']);
  });

  testWidgets('status bar: default slots, custom slots, divider', (tester) async {
    final s = ReadSetting();
    Widget bar(bool header) => MaterialApp(
          home: Scaffold(
            body: ReaderStatusBar(
              setting: s,
              header: header,
              color: Colors.black,
              title: '第一章 开端',
              bookName: '测试书',
              pageNum: 2,
              totalPage: 9,
              bookProgress: 0.25,
            ),
          ),
        );
    await tester.pumpWidget(bar(false));
    await tester.pump();
    expect(find.text('2/9'), findsOneWidget);
    expect(find.text('76%'), findsOneWidget); // 外置百分比电池
    expect(find.text(clockText()), findsOneWidget);
    await tester.pumpWidget(bar(true));
    expect(find.text('第一章 开端'), findsOneWidget);
    expect(find.byType(Container), findsNothing);

    await s.setSlot('customHeaderCenter', [SlotItem.bookName, SlotItem.bookProgress]);
    await s.setFen(DividerMode.header);
    await tester.pumpWidget(bar(true));
    expect(find.text('测试书'), findsOneWidget);
    expect(find.text('25.0%'), findsOneWidget);
    expect(find.byType(Container), findsOneWidget); // the divider line
  });

  testWidgets('更多设置: slots are a member feature, 屏幕常亮 / 分割线 / 菜单滑动条 write the original keys', (tester) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = ReadSetting();
    final book = Book(name: '书', bookUrl: '/tmp/a.epub');
    await tester.pumpWidget(MaterialApp(home: ReadMoreSettingPage(setting: s, book: book)));
    expect(find.text('完整CSS'), findsOneWidget);
    expect(find.text('自定义页眉 💎'), findsOneWidget);
    expect(find.text('自定义页脚 💎'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot_customHeaderLeft_6')));
    await tester.pump();
    expect(Toast.log, contains('此功能为会员功能'));
    expect(s.slots['customHeaderLeft'], [SlotItem.title]);

    UserSession.isvip = true;
    await tester.tap(find.byKey(const ValueKey('slot_customHeaderLeft_6')));
    await tester.pump();
    expect(s.slots['customHeaderLeft'], [SlotItem.title, SlotItem.bookName]);

    await tester.tap(find.text('常亮'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5分钟').last);
    await tester.pumpAndSettle();
    expect(Storage.getString('wakelockTimeout'), '5');

    await tester.tap(find.text('按章节'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按分页').last);
    await tester.pumpAndSettle();
    expect(Storage.getString('menuSliderType'), '1');
    expect(Storage.getString('menuSliderType2'), '1');
  });
}
