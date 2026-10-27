import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/source.dart';
import 'package:newread/pages/rss/bedit.dart';
import 'package:newread/pages/source/edit_bqsource.dart';
import 'package:newread/pages/source/edit_sgsource.dart';
import 'package:newread/pages/source/edit_source.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';
import 'support.dart';

Map<String, dynamic> full() => Map<String, dynamic>.from(jsonDecode(fixture('legado_full.json')) as Map);

void main() {
  late TestDevice dev;
  setUp(() async => dev = await freshArea());
  tearDown(() => dev.delete());

  group('SourceForm round trip', () {
    test('JSON in = JSON out when nothing is edited (unknown keys, ints, bools, nested rules, quoting)', () {
      final src = full();
      final form = SourceForm(src);
      expect(form.build(), src);
      expect(jsonEncode(form.build()), jsonEncode(src));
      form.dispose();
    });

    test('an edited field changes only that key; an emptied one is removed; flags and type are written only when changed', () {
      final src = full();
      final form = SourceForm(src);
      form.controllers['.bookSourceName']!.text = '改名';
      form.controllers['ruleSearch.bookList']!.text = '';
      form.controllers['ruleToc.formatJs']!.text = 'title.trim()';
      form.controllers['ruleExplore.kind']!.text = 'class.k@text';
      form.flags['enabledExplore'] = true;
      final out = form.build();
      expect(out['bookSourceName'], '改名');
      expect((out['ruleSearch'] as Map).containsKey('bookList'), isFalse);
      expect((out['ruleSearch'] as Map)['checkKeyWord'], '我的');
      expect((out['ruleToc'] as Map)['formatJs'], 'title.trim()');
      expect((out['ruleExplore'] as Map)['kind'], 'class.k@text');
      expect(out['enabledExplore'], isTrue);
      expect(out['enabledCookieJar'], isFalse);
      expect(out['bookSourceType'], 0);
      // everything else is untouched
      final rest = Map<String, dynamic>.from(out)..removeWhere((k, v) => const {'bookSourceName', 'ruleSearch', 'ruleToc', 'ruleExplore', 'enabledExplore'}.contains(k));
      final orig = full()..removeWhere((k, v) => const {'bookSourceName', 'ruleSearch', 'ruleToc', 'ruleExplore', 'enabledExplore'}.contains(k));
      expect(rest, orig);
      form.type = 2;
      expect(form.build()['bookSourceType'], 2);
      form.dispose();
    });

    test('a new source starts empty and gets only the filled fields and a rule object on demand', () {
      final form = SourceForm(null);
      form.controllers['.bookSourceUrl']!.text = 'https://n.example.com';
      form.controllers['.bookSourceName']!.text = '新源';
      form.controllers['ruleContent.content']!.text = '#c@html';
      expect(form.build(), {
        'bookSourceUrl': 'https://n.example.com',
        'bookSourceName': '新源',
        'ruleContent': {'content': '#c@html'},
      });
      form.dispose();
    });

    test('RSS form (bedit fields) round trips and writes articleStyle as the type', () {
      final src = Map<String, dynamic>.from((jsonDecode(fixture('rss_sources.json')) as List).first as Map);
      final form = SourceForm(src, tabs: rssSourceTabs, switches: rssSourceSwitches, typeKey: 'articleStyle');
      expect(form.build(), src);
      form.type = 2;
      form.flags['singleUrl'] = true;
      form.controllers['.ruleTitle']!.text = 'h2@text';
      final out = form.build();
      expect((out['articleStyle'], out['singleUrl'], out['ruleTitle'], out['vendorExtra']), (2, true, 'h2@text', 'keep'));
      form.dispose();
    });
  });

  test('source kinds: backend flag, 时光源 html engine, everything else Legado', () {
    expect(sourceKindOf(full()), SourceKind.bq);
    expect(sourceKindOf({'bookSourceUrl': 'u', 'html': '<html></html>'}), SourceKind.sg);
    expect(sourceKindOf({'bookSourceUrl': 'u', 'html': '@yuedu{}'}), SourceKind.bq);
    expect(sourceKindOf({'bookSourceUrl': 'u', 'html': '<html/>', 'searchUrl': '/s'}), SourceKind.bq);
    expect(sourceKindOf({'bookSourceUrl': 'u', 'isqread': true}), SourceKind.q);
    expect((sourceMark(SourceKind.q), sourceMark(SourceKind.bq), sourceMark(SourceKind.sg)), ('📶', '📒', ''));
  });

  testWidgets('Legado editor: tabs, edit a rule, save keeps every other key of the stored source', (t) async {
    final src = full();
    await t.runAsync(() => Sources.add(src));
    await t.pumpWidget(app(EditSource(source: Sourcedata.byUrl('https://full.example.com'))));
    await t.pump();
    expect(find.text('编辑书源'), findsOneWidget);
    for (final tab in ['基本', '搜索', '发现', '详情', '目录', '正文']) {
      expect(find.text(tab), findsWidgets); // 发现 is also the explore switch of the header row
    }
    expect(find.text('类型：'), findsOneWidget);
    await t.enterText(find.descendant(of: find.byKey(const Key('field_.bookSourceName')), matching: find.byType(TextField)), '完整书源2');
    await t.tap(find.text('搜索'));
    await t.pumpAndSettle();
    await t.enterText(find.descendant(of: find.byKey(const Key('field_ruleSearch.name')), matching: find.byType(TextField)), 'h3@text');
    await act(t, () => t.tap(find.byKey(const Key('source_save'))));
    await idleUntil(t, () => Toast.log.isNotEmpty);
    expect(Toast.log, contains('保存成功'));
    final stored = Sourcedata.byUrl('https://full.example.com')!;
    expect(stored['bookSourceName'], '完整书源2');
    expect((stored['ruleSearch'] as Map)['name'], 'h3@text');
    expect(stored['vendorExtra'], {'keep': [1, 2, 3], 'flag': true});
    expect(stored['searchUrl'], src['searchUrl']);
    expect(stored['ruleBookInfo'], src['ruleBookInfo']);
    expect(Sourcedata.raw.length, 1);
  });

  testWidgets('Legado editor refuses a source without url', (t) async {
    await t.pumpWidget(app(const EditBqSourcePage()));
    await t.tap(find.byKey(const Key('source_save')));
    await t.pump();
    expect(Toast.log.last, '源URL不能为空');
  });

  testWidgets('时光源 editor: says it cannot run here, new sources get the default html, save stores it', (t) async {
    await t.runAsync(() => Sourcedata.load());
    await t.pumpWidget(app(const EditSource(kind: SourceKind.sg)));
    await t.pump();
    expect(find.byKey(const Key('sg_note')), findsOneWidget);
    expect(find.text(sgUnsupportedNote), findsOneWidget);
    await t.enterText(find.byKey(const Key('sg_bookSourceName')), '我的时光源');
    await t.enterText(find.byKey(const Key('sg_bookSourceUrl')), 'https://my.sg');
    await act(t, () => t.tap(find.byKey(const Key('sg_save'))));
    await idleUntil(t, () => Toast.log.isNotEmpty);
    expect(Toast.log, contains('保存成功'));
    final m = Sourcedata.byUrl('https://my.sg')!;
    expect(m['html'], defaultSgHtml);
    expect(m['enabled'], isTrue);
    expect(sourceKindOf(m), SourceKind.sg);
  });
}
