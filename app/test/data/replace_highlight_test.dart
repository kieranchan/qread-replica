import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/highlight.dart';
import 'package:newread/data/replace.dart';
import 'package:newread/models/highlight_rule.dart';
import 'package:newread/models/replacerule.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

ReplaceRule rule(String name, String pattern, String repl, {String scope = '', String exclude = '', bool title = false, bool content = true, bool enabled = true}) =>
    ReplaceRule(name: name, pattern: pattern, replacement: repl, scope: scope, excludeScope: exclude, scopeTitle: title, scopeContent: content, isEnabled: enabled);

void main() {
  late TestDevice dev;

  setUp(() async {
    dev = await newDevice();
  });
  tearDown(() => dev.delete());

  group('replace rules', () {
    test('add assigns ids and increasing order numbers; the store persists and reloads', () async {
      final a = await Replaces.add(rule('a', 'x', 'y'));
      final b = await Replaces.add(rule('b', 'p', 'q'));
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
      expect([a.ruleorder, b.ruleorder], [1, 2]);
      final stored = jsonDecode(await Storage.read('replaces')) as List;
      expect(stored.map((e) => (e as Map)['name']), ['a', 'b']);
      expect((stored.first as Map)['isEnabled'], isTrue);

      ReplaceData.store.reset();
      final back = await ReplaceData.load();
      expect(back.map((r) => r.name), ['a', 'b']);
      expect(back.first.id, a.id);
    });

    test('update replaces by id, delete removes, enable switches, moveToTop reorders', () async {
      final a = await Replaces.add(rule('a', 'x', 'y'));
      final b = await Replaces.add(rule('b', 'p', 'q'));
      await Replaces.update(ReplaceRule.fromJson({...a.toJson(), 'replacement': 'NEW'}));
      expect(ReplaceData.rules.firstWhere((r) => r.id == a.id).replacement, 'NEW');
      await Replaces.setEnabled(b.id, false);
      expect(ReplaceData.rules.firstWhere((r) => r.id == b.id).isEnabled, isFalse);
      await Replaces.setAllEnabled(true);
      expect(ReplaceData.rules.every((r) => r.isEnabled), isTrue);
      await Replaces.moveToTop(b.id);
      expect(ReplaceData.forBook(bookName: 'n').map((r) => r.name), ['b', 'a']);
      await Replaces.delete(a.id);
      expect(ReplaceData.rules.map((r) => r.name), ['b']);
      await Replaces.deleteMany([b.id]);
      expect(ReplaceData.rules, isEmpty);
    });

    test('forBook honours enabled, scope, excludeScope and the title / content flags, ordered by ruleorder', () async {
      await Replaces.add(rule('all', 'a', 'A'));
      await Replaces.add(rule('onlyBookX', 'b', 'B', scope: '书X, 书Y'));
      await Replaces.add(rule('bySource', 'c', 'C', scope: 'https://src.example'));
      await Replaces.add(rule('excluded', 'd', 'D', exclude: '书X'));
      await Replaces.add(rule('off', 'e', 'E', enabled: false));
      await Replaces.add(rule('titleOnly', 'f', 'F', title: true, content: false));
      await Replaces.add(rule('empty pattern', '', 'G'));

      List<String> names(String book, {String origin = '', bool title = false}) => ReplaceData.forBook(bookName: book, origin: origin, forTitle: title).map((r) => r.name).toList();
      expect(names('书X'), ['all', 'onlyBookX']);
      expect(names('书Z'), ['all', 'excluded']);
      expect(names('书Z', origin: 'https://src.example'), ['all', 'bySource', 'excluded']);
      expect(names('书Y', title: true), ['titleOnly']);
    });

    test('import reads Legado rules (group / order keys), skips duplicates and rules without a pattern', () async {
      final legado = jsonEncode([
        {'id': 1700000000000, 'name': '去广告', 'group': '净化', 'pattern': r'广告\d+', 'replacement': '', 'scope': '', 'scopeTitle': false, 'scopeContent': true, 'excludeScope': '', 'isEnabled': true, 'isRegex': true, 'timeoutMillisecond': 3000, 'order': 7},
        {'id': 1700000000001, 'name': '空', 'pattern': '', 'replacement': 'x'},
        {'name': '全角', 'pattern': '，', 'replacement': ','},
      ]);
      expect(await Replaces.importJson(legado), 2);
      final first = ReplaceData.rules.first;
      expect((first.name, first.groupname, first.ruleorder, first.timeoutMillisecond, first.isRegex), ('去广告', '净化', 7, 3000, true));
      expect(first.id, '1700000000000');
      expect(ReplaceData.rules.last.id, isNotEmpty);
      expect(await Replaces.importJson(legado), 0); // same name/pattern/replacement already there
      // single object
      expect(await Replaces.importJson(jsonEncode({'name': 'n', 'pattern': 'p', 'replacement': 'r'})), 1);
      // export / import round trip on another device
      final json = await Replaces.exportJson();
      final other = await newDevice();
      addTearDown(other.delete);
      expect(await Replaces.importJson(json), 3);
      expect(ReplaceData.rules.map((r) => r.name), ['去广告', '全角', 'n']);
      expect(await Replaces.exportJson(ids: [ReplaceData.rules.first.id]), contains('去广告'));
    });
  });

  group('highlight rules', () {
    HighlightRule hr(String name, String pattern, {bool regex = false, bool enabled = true}) => HighlightRule(name: name, pattern: pattern, isRegex: regex, isEnabled: enabled, dayColor: '#FF0000');

    test('CRUD, ordering, enable flags and persistence', () async {
      final a = await Highlights.add(hr('names', '张三'));
      final b = await Highlights.add(hr('nums', r'\d+', regex: true));
      final c = await Highlights.add(hr('off', 'x', enabled: false));
      expect({a.id, b.id, c.id}.length, 3);
      expect(HighlightData.enabled.map((r) => r.name), ['names', 'nums']);
      await Highlights.move(b.id, -1);
      expect(HighlightData.rules.map((r) => r.name), ['nums', 'names', 'off']);
      await Highlights.setEnabled(c.id, true);
      await Highlights.update(HighlightRule.fromJson({...a.toJson(), 'dayColor': '#00FF00'}));
      expect(HighlightData.rules.firstWhere((r) => r.id == a.id).dayColor, '#00FF00');
      await Highlights.setAllEnabled(false);
      expect(HighlightData.enabled, isEmpty);
      await Highlights.delete(c.id);

      HighlightData.store.reset();
      final back = await HighlightData.load();
      expect(back.map((r) => r.name), ['nums', 'names']);
      expect(back.first.dayColor, '#FF0000');
    });

    test('isValid rejects broken regular expressions; import skips duplicates and export round-trips', () async {
      expect(HighlightData.isValid(hr('ok', r'\d+', regex: true)), isTrue);
      expect(HighlightData.isValid(hr('bad', r'(unclosed', regex: true)), isFalse);
      expect(HighlightData.isValid(hr('plain', '(unclosed')), isTrue);
      expect(HighlightData.isValid(hr('empty', '')), isFalse);
      await Highlights.add(hr('a', 'foo'));
      final json = await Highlights.exportJson();
      expect(await Highlights.importJson(json), 0);
      final other = await newDevice();
      addTearDown(other.delete);
      expect(await Highlights.importJson(json), 1);
      expect(HighlightData.rules.single.name, 'a');
      await Highlights.deleteMany([HighlightData.rules.single.id]);
      expect(HighlightData.rules, isEmpty);
    });
  });
}
