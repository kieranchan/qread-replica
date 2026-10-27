import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/txtrule.dart';
import 'package:newread/models/txt_toc_rule.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

void main() {
  late TestDevice dev;

  setUp(() async {
    dev = await newDevice();
  });
  tearDown(() => dev.delete());

  group('built-in TXT chapter rules (TxtTocRule.detxtTocRules)', () {
    test('the ten rules of the original are present in order; only the first is protected', () {
      final d = TxtTocRule.detxtTocRules;
      expect(d.map((r) => r.name).toList(), [
        '目录(去空白,内置禁止修改)',
        '目录',
        '数字 分隔符 标题名称',
        '大写数字 分隔符 标题名称',
        '正文 标题/序号',
        'Chapter/Section/Part/Episode 序号 标题',
        '特殊符号 序号 标题',
        '特殊符号 标题(单个)',
        '章/卷 序号 标题',
        '标题 特殊符号 序号',
      ]);
      expect(d.first.candel, isFalse);
      expect(d.skip(1).every((r) => r.candel), isTrue);
      expect(d.every((r) => r.isEnabled), isTrue);
      // defaults() hands out fresh objects each time
      final a = TxtTocRule.defaults();
      a.first.isEnabled = false;
      expect(TxtTocRule.defaults().first.isEnabled, isTrue);
    });

    test('every rule is a valid regular expression and the rules match typical headings', () {
      for (final r in TxtTocRule.detxtTocRules) {
        expect(() => RegExp(r.rule, multiLine: true), returnsNormally, reason: r.name);
      }
      bool matches(String ruleName, String line) {
        final rule = TxtTocRule.detxtTocRules.firstWhere((r) => r.name == ruleName);
        return RegExp(rule.rule, multiLine: true).hasMatch(line);
      }

      expect(matches('目录', '第一章 重生'), isTrue);
      expect(matches('目录', '  第12节 夜幕'), isTrue);
      expect(matches('目录', '第三百二十一章 终战'), isTrue);
      expect(matches('目录', '楔子'), isTrue);
      expect(matches('目录', '这是一段普通的正文内容，不是标题。'), isFalse);
      expect(matches('目录', '第一章${'字' * 40}'), isFalse); // longer than 30 characters after the number
      expect(matches('目录', '正文完'), isFalse); // `正文(?!完|结)`
      expect(matches('数字 分隔符 标题名称', '12、归来'), isTrue);
      expect(matches('数字 分隔符 标题名称', '3. 开始'), isTrue);
      expect(matches('Chapter/Section/Part/Episode 序号 标题', 'Chapter 12 The End'), isTrue);
      expect(matches('Chapter/Section/Part/Episode 序号 标题', 'Part 3'), isTrue);
      expect(matches('正文 标题/序号', '正文　第一回'), isTrue);
      expect(matches('特殊符号 序号 标题', ' 【第十章】 风起'), isTrue);
      expect(matches('章/卷 序号 标题', '卷二 江湖'), isTrue);
      expect(matches('标题 特殊符号 序号', '风起云涌(三)'), isTrue);
      // the first rule finds titles after a full-width space, scanning inside a text
      final trimmed = TxtTocRule.detxtTocRules.first;
      expect(RegExp(trimmed.rule).hasMatch('　第二章 对决'), isTrue);
    });
  });

  group('Txtrule store', () {
    test('first load gives the defaults without writing anything', () async {
      final rules = await Txtruledata.load();
      expect(rules.length, 10);
      expect(await Storage.exists('txt_toc_rule'), isFalse);
      expect(Txtruledata.enabled.length, 10);
    });

    test('changes persist as JSON and reload; a damaged file falls back to the defaults', () async {
      await Txtrule.add(TxtTocRule(name: '我的规则', rule: r'^第\d+话', isEnabled: true));
      await Txtrule.setEnabled('目录', false);
      expect(Txtruledata.rules.length, 11);
      final stored = jsonDecode(await Storage.read('txt_toc_rule')) as List;
      expect(stored.length, 11);
      expect((stored.last as Map)['name'], '我的规则');
      expect((stored.last as Map)['candel'], isTrue);

      Txtruledata.store.reset();
      final back = await Txtruledata.load();
      expect(back.length, 11);
      expect(back.firstWhere((r) => r.name == '目录').isEnabled, isFalse);
      expect(Txtruledata.enabled.length, 10);

      await Storage.write('txt_toc_rule', '{{{ not json');
      Txtruledata.store.reset();
      expect((await Txtruledata.load()).length, 10);
    });

    test('protected rules cannot be deleted or rewritten; user rules can', () async {
      await Txtruledata.load();
      expect(await Txtrule.delete('目录(去空白,内置禁止修改)'), isFalse);
      await Txtrule.update('目录(去空白,内置禁止修改)', TxtTocRule(name: 'x', rule: 'y', isEnabled: false));
      final first = Txtruledata.rules.first;
      expect(first.name, '目录(去空白,内置禁止修改)'); // text kept, only the enabled switch changes
      expect(first.isEnabled, isFalse);

      await Txtrule.add(TxtTocRule(name: 'A', rule: 'a', isEnabled: true));
      await Txtrule.add(TxtTocRule(name: 'A', rule: 'a2', isEnabled: true)); // same name: replaced
      expect(Txtruledata.rules.where((r) => r.name == 'A').single.rule, 'a2');
      await Txtrule.update('A', TxtTocRule(name: 'B', rule: 'b', isEnabled: true));
      expect(Txtruledata.rules.any((r) => r.name == 'A'), isFalse);
      expect(Txtruledata.rules.last.name, 'B');
      expect(await Txtrule.delete('B'), isTrue);
      expect(Txtruledata.rules.length, 10);
    });

    test('moveToTop and reset', () async {
      await Txtruledata.load();
      await Txtrule.moveToTop('章/卷 序号 标题');
      expect(Txtruledata.rules.first.name, '章/卷 序号 标题');
      await Txtrule.add(TxtTocRule(name: 'X', rule: 'x', isEnabled: true));
      await Txtrule.reset();
      expect(Txtruledata.rules.map((r) => r.name), TxtTocRule.defaults().map((r) => r.name));
    });

    test('import accepts Legado txtTocRule.json (enable / serialNumber) and updates by name', () async {
      final legado = jsonEncode([
        {'id': -1, 'enable': true, 'name': '我的章节', 'rule': r'^Ch\.\d+', 'serialNumber': 1},
        {'id': -2, 'enable': false, 'name': '另一个', 'rule': r'^# .+', 'serialNumber': 2},
        {'name': '', 'rule': 'empty name is skipped'},
      ]);
      expect(await Txtrule.importJson(legado), 2);
      final a = Txtruledata.rules.firstWhere((r) => r.name == '我的章节');
      expect((a.isEnabled, a.candel), (true, true));
      expect(Txtruledata.rules.firstWhere((r) => r.name == '另一个').isEnabled, isFalse);
      // importing the same list again changes nothing; a changed rule text updates in place
      expect(await Txtrule.importJson(legado), 0);
      expect(await Txtrule.importJson(jsonEncode([{'name': '我的章节', 'rule': r'^Chap\d+', 'enable': true}])), 1);
      expect(Txtruledata.rules.firstWhere((r) => r.name == '我的章节').rule, r'^Chap\d+');
      expect(Txtruledata.rules.length, 12);
      // a built-in name cannot be overwritten by an import
      expect(await Txtrule.importJson(jsonEncode([{'name': '目录(去空白,内置禁止修改)', 'rule': 'x', 'enable': true}])), 0);
    });

    test('export / import round trip between devices', () async {
      await Txtrule.add(TxtTocRule(name: 'Z', rule: 'z+', isEnabled: true));
      final json = await Txtrule.exportJson();
      final other = await newDevice();
      addTearDown(other.delete);
      expect(await Txtrule.importJson(json), 1); // only the user rule is new there
      expect(Txtruledata.rules.last.name, 'Z');
    });
  });
}
