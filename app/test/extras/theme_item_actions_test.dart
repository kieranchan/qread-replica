// The theme card's visible actions (as the original card): 应用 / 取消应用 (back to the default theme) and 删除 (an applied theme is
// cancelled first, then removed).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/data/theme.dart';
import 'package:newread/data/user.dart';
import 'package:newread/init/appinit.dart';
import 'package:newread/models/theme.dart';
import 'package:newread/pages/theme/theme_manager_page.dart';
import 'package:newread/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('apply, cancel back to the default, delete', (tester) async {
    final root = Directory.systemTemp.createTempSync('qread_theme_card_');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {} // Windows may still hold a file of the store open
    });
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await AppInit.init(prefs: await SharedPreferences.getInstance(), root: root);
      await ThemeManager.install(ThemeModel(id: 'plaza_t1', title: '青竹', author: '轻悦复刻', isLightMode: true, tabBarSelectedColor: 0xFF4E7D4E));
      await ThemeProvider.instance.init();
    });
    UserSession.isvip = true; // applying is member-only, as in the original

    await tester.pumpWidget(const GetMaterialApp(home: ThemeManagerPage()));
    await tester.pumpAndSettle();
    expect(find.text('青竹'), findsOneWidget);
    // the actions are on the card, no menu to open
    for (final a in ['编辑', '导出', '查看', '拷贝', '删除']) {
      expect(find.text(a), findsOneWidget);
    }

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('theme_apply_plaza_t1')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(ThemeProvider.instance.isApplied(ThemeManager.themes.single), isTrue);
    expect(find.text('取消应用'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('theme_apply_plaza_t1')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(ThemeProvider.instance.isApplied(ThemeManager.themes.single), isFalse); // back to the default theme

    // apply again, then delete: the theme is cancelled and removed
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('theme_apply_plaza_t1')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme_delete_plaza_t1')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('dialog_confirm')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(ThemeManager.themes, isEmpty);
    expect(ThemeProvider.instance.dayThemeId, isEmpty);
    expect(find.text('青竹'), findsNothing);
  });
}
