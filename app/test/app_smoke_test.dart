// The wired app on the host: start-up (AppInit + Wiring), privacy agreement, every tab builds without errors.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/common.dart';
import 'package:newread/init/appinit.dart';
import 'package:newread/init/wiring.dart';
import 'package:newread/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app starts and every tab builds', (tester) async {
    final root = Directory.systemTemp.createTempSync('qread_smoke_');
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await AppInit.init(prefs: await SharedPreferences.getInstance(), root: root);
      await Wiring.init();
    });
    Common.index.value = 0;

    await tester.pumpWidget(const QreadApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy_agree')));
    await tester.pumpAndSettle();

    for (final tab in ['书架', '发现', '探索', '订阅', '我的']) {
      await tester.tap(find.byKey(Key('tab_$tab')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: 'tab $tab');
    }
    expect(find.text('登录同步阅读数据'), findsOneWidget);
  });
}
