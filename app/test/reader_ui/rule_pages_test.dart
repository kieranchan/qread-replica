// Rule pages: replace rules (list / edit / validation / test dialog / toggle / delete), TXT TOC rules (defaults, protected rule, edit
// with "测试", add), highlight rules (add, count of active rules). One test per store key (see support.dart about the storage locks).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/highlight.dart';
import 'package:newread/data/replace.dart';
import 'package:newread/data/txtrule.dart';
import 'package:newread/pages/highlight/highlight_rule_setting.dart';
import 'package:newread/pages/replace/replace_rule_setting.dart';
import 'package:newread/pages/txtrule/txt_rule_edit.dart';
import 'package:newread/pages/txtrule/txt_rule_setting.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';
import 'support.dart';

Future<void> _device(WidgetTester tester) async {
  await tester.runAsync(newDevice);
  Toast.log.clear();
  Toast.sink = (_, _) {};
}

void main() {
  test('testTxtRule lists the lines a rule turns into chapter titles', () {
    expect(testTxtRule(r'^第.+章.*$', '第一章 开始\n正文\n第二章 继续\n'), ['第一章 开始', '第二章 继续']);
    expect(() => testTxtRule('(', 'x'), throwsFormatException);
  });

  testWidgets('replace rules: create, validate, test, toggle, delete', (tester) async {
    phoneSize(tester, size: const Size(500, 900));
    await _device(tester);
    await tester.runAsync(ReplaceData.load);
    await tester.pumpWidget(app(const ReplaceRuleSetting()));
    await settle(tester, max: 3);
    expect(find.textContaining('还没有添加替换规则'), findsOneWidget);

    await tester.tap(find.byTooltip('新建规则'));
    await settle(tester, max: 10);
    expect(find.text('替换规则编辑'), findsOneWidget);
    await tester.tap(find.byTooltip('保存'));
    await settle(tester, max: 2);
    expect(Toast.log, contains('请输入替换规则名称'));
    await tester.enterText(find.byKey(const ValueKey('rule_name')), '去广告');
    await tester.enterText(find.byKey(const ValueKey('rule_pattern')), '广告');
    await tester.enterText(find.byKey(const ValueKey('rule_replacement')), '');
    await tester.tap(find.byTooltip('保存'));
    await settle(tester, until: () => Toast.log.contains('保存成功') && find.text('替换规则编辑').evaluate().isEmpty);
    await settle(tester, max: 5);
    final r = ReplaceData.rules.single;
    expect(r.pattern, '广告');
    expect(r.isEnabled, isTrue);
    expect(r.scopeContent, isTrue);

    // 测试 dialog
    await tester.tap(find.descendant(of: find.byType(ListTile), matching: find.byType(PopupMenuButton<String>)).first);
    await settle(tester, max: 5);
    await tester.tap(find.text('测试').last);
    await settle(tester, max: 10);
    await tester.enterText(find.byType(TextField).last, '正文广告正文');
    await tester.tap(find.widgetWithText(TextButton, '测试'));
    await settle(tester, max: 2);
    expect(find.textContaining('字符数变化: 6 -> 4'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await settle(tester, max: 5);

    // toggle
    await tester.tap(find.byType(Switch));
    await settle(tester, until: () => !ReplaceData.rules.single.isEnabled);

    // delete
    await tester.tap(find.descendant(of: find.byType(ListTile), matching: find.byType(PopupMenuButton<String>)).first);
    await settle(tester, max: 5);
    await tester.tap(find.text('删除').last);
    await settle(tester, max: 5);
    expect(find.text('确定要删除《去广告》吗？'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await settle(tester, until: () => ReplaceData.rules.isEmpty);
    await finish(tester);
  });

  testWidgets('txt rules: defaults, protected rule, add with test', (tester) async {
    phoneSize(tester, size: const Size(500, 900));
    await _device(tester);
    await tester.runAsync(Txtruledata.load);
    await tester.pumpWidget(app(const TxtRuleSetting()));
    await settle(tester, max: 3);
    expect(find.text('目录规则管理'), findsOneWidget);
    expect(find.text('目录(去空白,内置禁止修改)'), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, '目录(去空白,内置禁止修改)'),
      matching: find.byType(PopupMenuButton<String>),
    ));
    await settle(tester, max: 5);
    await tester.tap(find.text('删除').last);
    await settle(tester, max: 3);
    expect(Toast.log, contains('无法删除保留内容'));

    final count = Txtruledata.rules.length;
    await tester.tap(find.byTooltip('新建规则'));
    await settle(tester, max: 10);
    expect(find.text('目录规则编辑'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('txt_name')), '测试规则');
    await tester.enterText(find.byKey(const ValueKey('txt_rule')), r'^第.+章.*$');
    await tester.tap(find.text('测试'));
    await settle(tester, max: 2);
    expect(find.text('匹配到 2 个章节'), findsOneWidget);
    await tester.tap(find.byTooltip('保存'));
    await settle(tester, until: () => Txtruledata.rules.length == count + 1);
    expect(Txtruledata.rules.last.name, '测试规则');
    expect(Txtruledata.rules.last.candel, isTrue);
    await finish(tester);
  });

  testWidgets('highlight rules: add a rule, active count', (tester) async {
    phoneSize(tester, size: const Size(500, 900));
    await _device(tester);
    await tester.runAsync(HighlightData.load);
    await tester.pumpWidget(app(const HighlightRuleSetting()));
    await settle(tester, max: 3);
    expect(find.text('点击右上角添加规则开始使用'), findsOneWidget);
    await tester.tap(find.byTooltip('新建规则'));
    await settle(tester, max: 10);
    expect(find.text('高亮规则编辑'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('hl_name')), '对话');
    await tester.tap(find.text('“对话”'));
    await settle(tester, max: 2);
    await tester.tap(find.byTooltip('保存'));
    await settle(tester, until: () => HighlightData.rules.length == 1 && find.text('起效高亮 1 条规则').evaluate().isNotEmpty);
    final r = HighlightData.rules.single;
    expect(r.isRegex, isTrue);
    expect(r.pattern, '“[^”]*”');
    expect(find.text('起效高亮 1 条规则'), findsOneWidget);
    await finish(tester);
  });
}
