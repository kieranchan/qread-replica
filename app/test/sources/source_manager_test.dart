import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/common/nav.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/source.dart';
import 'package:newread/pages/source/source_setting.dart';
import 'package:newread/util/toast.dart';
import 'package:newread/util/webbook/model/book_source.dart';

import '../support/env.dart';
import '../util/fake_site.dart';
import 'support.dart';

/// Opens the manager's more menu and picks [label] inside the real zone.
Future<void> menu(WidgetTester t, String label) async {
  await act(t, () => t.tap(find.byKey(const Key('source_menu'))));
  await t.pumpAndSettle();
  await act(t, () => t.tap(find.text(label).last));
}

Future<void> confirm(WidgetTester t) async {
  await t.pumpAndSettle();
  await act(t, () => t.tap(find.byKey(const Key('confirm_ok'))));
}

/// The manager with the fixture sources imported through 本地导入 (preview, ✓).
Future<void> importFixture(WidgetTester t) async {
  SourceImport.pickFileText = () async => fixture('book_sources.json');
  await t.runAsync(() => Sourcedata.load());
  await t.pumpWidget(app(const SourceSettingPage()));
  await t.pump();
  expect(find.text('还没有添加书源'), findsOneWidget);
  await menu(t, '本地导入');
  await idleUntil(t, () => find.text('导入').evaluate().isNotEmpty);
  expect(find.text('新增'), findsNWidgets(3)); // the entry without url is dropped
  expect(find.text('全选 (3/3)'), findsOneWidget);
  await act(t, () => t.tap(find.byKey(const Key('import_ok'))));
  await idleUntil(t, () => Toast.log.isNotEmpty && find.text('书源管理').evaluate().isNotEmpty);
  expect(Sourcedata.raw.length, 3);
  await idle(t);
}

void main() {
  late TestDevice dev;
  late FakeSite site;
  setUpAll(() async => site = await FakeSite.start());
  tearDownAll(() => site.close());
  setUp(() async => dev = await freshArea());
  tearDown(() => dev.delete());

  test('parse keeps entries with url and name; download + check run against the fake site', () async {
    expect(SourceImport.parse(fixture('book_sources.json')).map((m) => m['bookSourceName']), ['甲站', '乙站', '时光示例']);
    expect(SourceImport.parse('{"bookSourceUrl":"u","bookSourceName":"n"}').single['bookSourceUrl'], 'u');
    expect(() => SourceImport.parse('not json'), throwsFormatException);
    final text = await SourceImport.download('${site.base}/source.json');
    expect(SourceImport.parse(text).length, 2);

    final html = Map<String, dynamic>.from(jsonDecode(site.sourceJson('source_html.json')) as Map);
    final steps = <String>[];
    expect(await SourceSettingPageCheck.check(html, steps.add), '检验成功');
    expect(steps.first, '尝试搜索：我的');
    expect(steps, containsAll(['详情页检验成功', '目录获取成功：5']));
    final broken = {...html, 'searchUrl': '/nothing?q={{key}}'};
    expect(await SourceSettingPageCheck.check(broken, (_) {}), startsWith('检验失败:'));
  });

  testWidgets('import from a file: preview with 新增, then the list with marks, groups and the stored raw JSON', (t) async {
    await importFixture(t);
    expect(Toast.log, contains('轻悦时光新增3条书源，更新0条书源'));
    expect(find.text('📒甲站 [玄幻,精品]'), findsOneWidget);
    expect(find.text('📒乙站'), findsOneWidget);
    expect(find.text('时光示例 [原生]'), findsOneWidget);
    expect((Sourcedata.byUrl('https://a.example.com')!['ruleSearch'] as Map)['checkKeyWord'], '斗破');
    expect(Sourcedata.byUrl('https://sg.example.com')!['html'], contains('function search'));

    // group filter: 时光源 / 阅读源 / a named group
    Future<void> group(String g) async {
      await t.tap(find.byKey(const Key('group_menu')));
      await t.pumpAndSettle();
      await t.tap(find.text(g).last);
      await t.pumpAndSettle();
    }

    await group('时光源');
    expect(find.text('时光示例 [原生]'), findsOneWidget);
    expect(find.text('📒乙站'), findsNothing);
    await group('阅读源');
    expect(find.text('📒乙站'), findsOneWidget);
    expect(find.text('时光示例 [原生]'), findsNothing);
    await group('精品');
    expect(find.text('📒甲站 [玄幻,精品]'), findsOneWidget);
    expect(find.text('📒乙站'), findsNothing);
    await group('全部分组');

    // search
    await t.enterText(find.byKey(const Key('source_search')), '乙');
    await t.pump();
    expect(find.text('📒甲站 [玄幻,精品]'), findsNothing);
    expect(find.text('📒乙站'), findsOneWidget);
    await t.enterText(find.byKey(const Key('source_search')), '');
    await t.pump();
  });

  testWidgets('enable switch, batch group, export, top and delete persist through the store', (t) async {
    await importFixture(t);
    // enable 乙站
    expect(Sourcedata.byUrl('https://b.example.com')!['enabled'], isFalse);
    await act(t, () => t.tap(find.byKey(const Key('enable_https://b.example.com'))));
    await idleUntil(t, () => Sourcedata.byUrl('https://b.example.com')!['enabled'] == true);

    // select all -> 更多 -> 加入分组 -> new group
    await t.tap(find.byKey(const Key('select_all')));
    await t.pump();
    expect(find.text('全选 (3/3)'), findsOneWidget);
    await act(t, () => t.tap(find.byKey(const Key('more_actions'))));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.byKey(const Key('more_addGroup'))));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('group_input')), '收藏');
    await act(t, () => t.tap(find.byKey(const Key('group_ok'))));
    await idleUntil(t, () => Toast.log.contains('操作成功'));
    expect(Sourcedata.byUrl('https://b.example.com')!['bookSourceGroup'], '收藏');
    expect(Sourcedata.byUrl('https://a.example.com')!['bookSourceGroup'], '玄幻,精品,收藏');

    // export the selection
    String? shared;
    SourceImport.shareFile = (name, text) async => shared = '$name|$text';
    await act(t, () => t.tap(find.byKey(const Key('more_actions'))));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('more_export')));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.byKey(const Key('more_export'))));
    await idleUntil(t, () => shared != null);
    expect(shared, startsWith('shareBookSource.json|'));
    final exported = jsonDecode(shared!.substring(shared!.indexOf('|') + 1)) as List;
    expect(exported.map((e) => (e as Map)['bookSourceUrl']), ['https://a.example.com', 'https://b.example.com', 'https://sg.example.com']);

    // 置顶 the last one through its item menu
    await act(t, () => t.tap(find.byKey(const Key('menu_https://sg.example.com'))));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.text('置顶').last));
    await confirm(t);
    await idleUntil(t, () => Toast.log.contains('置顶成功'));
    expect(Sourcedata.raw.first['bookSourceUrl'], 'https://sg.example.com');
    expect(Toast.log, contains('置顶成功'));

    // invert the selection to just one, delete it
    await t.tap(find.byKey(const Key('select_all'))); // all -> none
    await t.pump();
    await t.tap(find.text('📒甲站 [玄幻,精品,收藏]'));
    await t.pump();
    await act(t, () => t.tap(find.byKey(const Key('delete_selected'))));
    await confirm(t);
    await idleUntil(t, () => Toast.log.contains('删除成功'));
    expect(Sourcedata.raw.length, 2);
    expect(Sourcedata.byUrl('https://a.example.com'), isNull);
    expect(Toast.log, contains('删除成功'));
  });

  test('the debugger keeps the response bodies of its own run (POST search included)', () async {
    final post = BookSource.fromJson(Map<String, dynamic>.from(jsonDecode(site.sourceJson('source_xpath_post.json')) as Map));
    final bodies = <String, String>{};
    final log = await SourceApi.debug(post, '我的', onBody: (s, b) => bodies[s] = b);
    expect(bodies.keys, containsAll(['search', 'book', 'toc', 'content']));
    expect(bodies['search'], contains('keyword=')); // the fake site echoes the POST body into the page
    expect(log.bodies, bodies);
  });

  testWidgets('item menu: 搜索 / 发现 on one source, 重载 asks first', (t) async {
    final searched = <List<Source>?>[];
    final opened = <Object?>[];
    final search0 = Nav.openSearch, named0 = Nav.openNamed;
    addTearDown(() {
      Nav.openSearch = search0;
      Nav.openNamed = named0;
    });
    Nav.openSearch = (context, {key, sources}) async => searched.add(sources);
    Nav.openNamed = (context, name, {arguments}) async => opened.add('$name|${arguments is Source ? arguments.bookSourceUrl : arguments}');
    await importFixture(t);
    Future<void> pick(String label) async {
      await act(t, () => t.tap(find.byKey(const Key('menu_https://a.example.com'))));
      await t.pumpAndSettle();
      await act(t, () => t.tap(find.text(label).last));
      await t.pumpAndSettle();
    }

    await pick('搜索');
    expect(searched.single!.single.bookSourceUrl, 'https://a.example.com');
    await pick('发现');
    expect(opened, ['discovery_page_new|https://a.example.com']);
    await pick('重载');
    expect(find.text('是否重载甲站书源线程'), findsOneWidget);
    await confirm(t);
  });

  testWidgets('network import (网络导入) downloads, previews and adds; an import link does the same', (t) async {
    await t.runAsync(() => Sourcedata.load());
    await t.pumpWidget(app(const SourceSettingPage()));
    await t.pump();
    await menu(t, '网络导入');
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ask_text')), '${site.base}/source.json');
    await act(t, () => t.tap(find.byKey(const Key('ask_ok'))));
    await idleUntil(t, () => find.byKey(const Key('import_ok')).evaluate().isNotEmpty);
    expect(find.text('新增'), findsNWidgets(2));
    await act(t, () => t.tap(find.byKey(const Key('import_ok'))));
    await idleUntil(t, () => Toast.log.isNotEmpty);
    expect(Sourcedata.raw.length, 1);
    // both sources of the file share the fake site's url: the second one updates the first
    expect(Toast.log, contains('轻悦时光新增1条书源，更新1条书源'));
    await idle(t);

    // the same file through a legado:// link: both already exist now
    final ctx = t.element(find.text('书源管理'));
    await act(t, () async {
      unawaited(SourceImport.handleLink(ctx, Uri.parse('legado://import/bookSource?src=${Uri.encodeComponent('${site.base}/source.json')}')));
    });
    await idleUntil(t, () => find.byKey(const Key('import_ok')).evaluate().isNotEmpty);
    expect(find.text('已有'), findsNWidgets(2));
    await act(t, () => t.tap(find.byKey(const Key('import_ok'))));
    await idleUntil(t, () => Toast.log.contains('轻悦时光新增0条书源，更新2条书源'));
  });
}

/// The manager's check for the plain test.
abstract class SourceSettingPageCheck {
  static Future<String> check(Map<String, dynamic> raw, void Function(String) onStep) => checkSource(raw, onStep: onStep);
}
