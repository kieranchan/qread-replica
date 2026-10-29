// The theme editor's page styles (pages/theme/new_theme_page.dart): 添加页面样式 opens the page picker with its search box
// (`搜索页面…`, `无匹配页面`), the chosen pages become a bound style listed with the original's summary line.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/app_dirs.dart';
import 'package:newread/pages/theme/new_theme_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qread_theme_editor_');
    SharedPreferences.setMockInitialValues({});
    await Storage.init(prefs: await SharedPreferences.getInstance(), root: tmp);
    AppDirs.root = tmp;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('添加页面样式: search filters the pages, 无匹配页面 for no hit, the style lands with its summary', (tester) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: NewThemePage()));
    await tester.pumpAndSettle();
    // the editor is a long list: scroll the page-style section into view first
    await tester.scrollUntilVisible(find.text('暂无自定义样式，点击右上角添加'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('页面样式设置'), findsOneWidget);
    await tester.ensureVisible(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('添加页面样式'), findsOneWidget);
    expect(find.text('选择要绑定的页面（可多选）'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, '书架'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, '我的'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('style_page_search')), '书架');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, '书架'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, '我的'), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, '书架'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('style_page_search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('无匹配页面'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.tap(find.byKey(const Key('style_pages_ok')));
    await tester.pumpAndSettle();
    expect(find.text('样式 #1'), findsOneWidget);
    expect(find.textContaining('已绑定: 书架 · 透明度 0'), findsOneWidget);
    expect(find.text('暂无自定义样式，点击右上角添加'), findsNothing);
  });
}
