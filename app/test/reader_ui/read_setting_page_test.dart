// 阅读设置: the original's sections, 底栏标签配置 (reorder, 发现 / 订阅 switches, saved through MainTabs), 沉浸光感 through ImmersiveLight.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/immersive_light.dart';
import 'package:newread/pages/main_page.dart';
import 'package:newread/pages/setting/read_setting_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

void main() {
  setUp(() async {
    await newDevice();
    Toast.log.clear();
    Toast.sink = (_, _) {};
    ImmersiveLight.reload();
  });

  testWidgets('sections, tab editor, 沉浸光感', (tester) async {
    tester.view.physicalSize = const Size(600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ReadSettingPage()));
    for (final t in ['书架设置', '阅读设置', '阅读统计', '界面设置', '缓存设置', '备份设置', 'AI模型', '其他设置', '朗读优化', '单本统计', '侧边导航']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('关闭'), findsOneWidget); // 朗读优化 0 = 关闭

    // 沉浸光感 writes immersiveLight2223 through ImmersiveLight
    await tester.tap(find.byKey(const ValueKey('immersive_light')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('强').last);
    await tester.pumpAndSettle();
    expect(ImmersiveLight.level.value, ImmersiveLight.strong);
    expect(Storage.getString('immersiveLight2223'), '2');

    // 底栏标签配置: 订阅 is hidden by default, 发现 shown
    await tester.tap(find.text('底栏图标'));
    await tester.pumpAndSettle();
    expect(find.text('底栏标签配置'), findsOneWidget);
    expect(find.text('「书架」和「我的」始终显示，但可以调整位置'), findsOneWidget);
    expect(find.byKey(const ValueKey('tab_switch_发现')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab_switch_订阅')), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('tab_switch_订阅'))).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('tab_switch_订阅')));
    await tester.tap(find.byKey(const ValueKey('tab_switch_发现')));
    await tester.pump();
    // drag 我的 (last) above 书架 (first)
    final handle = find.descendant(of: find.byKey(const ValueKey('tab_我的')), matching: find.byIcon(Icons.drag_handle));
    final top = tester.getCenter(find.byKey(const ValueKey('tab_书架')));
    final start = tester.getCenter(handle);
    final dy = (top.dy - 40 - start.dy) / 12;
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    for (var y = 0; y < 12; y++) {
      await g.moveBy(Offset(0, dy));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    final rev = MainTabs.revision.value;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(MainTabs.revision.value, rev + 1);
    expect(jsonDecode(Storage.getString('bottomBarTabs')), ['我的', '书架', '发现', '探索', '订阅']);
    expect(Storage.getString('ding'), 'true');
    expect(Storage.getString('found'), 'false');
    expect(MainTabs.order(), ['我的', '书架', '探索', '订阅']);
  });
}
