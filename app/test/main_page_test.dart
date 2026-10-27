// The tab shell: privacy agreement on first launch, five tabs in the original's order, the agreement is remembered.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/common/common.dart';
import 'package:newread/init/appinit.dart';
import 'package:newread/pages/main_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('qread_main_');
    SharedPreferences.setMockInitialValues({});
    await AppInit.init(prefs: await SharedPreferences.getInstance(), root: root, loadData: false);
    Common.index.value = 0;
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('privacy agreement, then five tabs', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: MainPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy_dialog')), findsOneWidget);
    expect(find.text('欢迎使用轻悦时光！'), findsOneWidget);

    await tester.tap(find.byKey(const Key('privacy_agree')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy_dialog')), findsNothing);
    expect(Storage.getBool(MainPage.privacyKey), isTrue);

    final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
    expect(labels, ['书架', '发现', '探索', '订阅', '我的']);
    await tester.tap(find.byKey(const Key('tab_订阅')));
    await tester.pumpAndSettle();
    expect(Common.index.value, 3);
  });

  testWidgets('bottomBarTabs order and the found/ding switches', (tester) async {
    await Storage.setString(MainPage.privacyKey, 'true');
    await Storage.setString('bottomBarTabs', '["我的","书架","探索","发现","订阅"]');
    await Storage.setBool('ding', false);
    await tester.pumpWidget(const GetMaterialApp(home: MainPage()));
    await tester.pumpAndSettle();
    final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
    expect(labels, ['我的', '书架', '探索', '发现']);
  });

  testWidgets('no dialog once agreed', (tester) async {
    await Storage.setString(MainPage.privacyKey, 'true');
    await tester.pumpWidget(const GetMaterialApp(home: MainPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy_dialog')), findsNothing);
  });
}
