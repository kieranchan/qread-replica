import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/ai_character.dart';
import 'package:newread/models/ai_chat_session.dart';
import 'package:newread/models/ai_model_config.dart';
import 'package:newread/storage/book_reading_time_storage.dart';
import 'package:newread/storage/item.dart';
import 'package:newread/storage/setting.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

void main() {
  late TestDevice dev;

  setUp(() async {
    dev = await newDevice();
    StorageItem.readitems.clear();
  });
  tearDown(() => dev.delete());

  group('AI model configs', () {
    test('save / load round trip keeps every field; role and purify models are found by flag', () async {
      final models = [
        AiModelConfig(id: 'a', name: 'GPT', url: 'https://api.example/v1', key: 'sk-1', model: 'm1', isRoleAnalysis: true, concurrent: 2),
        AiModelConfig(id: 'b', name: '净化', url: 'https://x/v1', key: 'sk-2', model: 'm2', isPurify: true, concurrent: 4),
      ];
      expect(await Setting.saveAiModels(models), isTrue);
      final back = Setting.getAiModels();
      expect(back.map((m) => m.toJson()).toList(), models.map((m) => m.toJson()).toList());
      expect(Setting.roleAnalysisModel?.id, 'a');
      expect(Setting.purifyModel?.id, 'b');
      expect(Setting.modelById('b')?.concurrent, 4);
      expect(Setting.modelById('zzz'), isNull);
    });

    test('legacy single-model keys migrate into legacy_default / legacy_purify and are dropped on save', () async {
      await Storage.setString('aiUrl', 'https://old/v1');
      await Storage.setString('aiKey', 'K');
      await Storage.setString('aiModel', 'gpt');
      await Storage.setString('purifyUrl', 'https://p/v1');
      await Storage.setString('purifyKey', 'PK');
      await Storage.setString('purifyModel', 'pm');
      await Storage.setInt('purifyConcurrent', 3);
      final list = Setting.getAiModels();
      expect(list.map((m) => m.id), ['legacy_default', 'legacy_purify']);
      expect(list.first.name, '默认模型');
      expect(list.last.name, '正文净化模型');
      expect(list.last.concurrent, 3);
      expect(list.first.isPurify, isFalse); // a separate purify model exists
      await Setting.saveAiModels(list);
      for (final k in Setting.legacyAiKeys) {
        expect(Storage.getString(k), '', reason: k);
      }
      expect(Setting.getAiModels().length, 2);
      expect(Storage.getString('aiModelList'), isNotEmpty);
    });

    test('nothing configured gives an empty list', () {
      expect(Setting.getAiModels(), isEmpty);
      expect(Setting.roleAnalysisModel, isNull);
    });

    test('backup item v2 round trip and legacy restore (ids restored_*)', () async {
      await Setting.saveAiModels([AiModelConfig(id: 'a', name: 'n', url: 'u', key: 'k', model: 'm', isPurify: true, concurrent: 5)]);
      final json = Setting.buildAiBackup();
      final map = jsonDecode(json) as Map;
      expect(map['version'], 2);
      expect((map['models'] as List).length, 1);
      expect(map['purifyConcurrent'], 5);
      await Setting.saveAiModels([]);
      expect(await Setting.restoreAiBackup(json), 1);
      expect(Setting.getAiModels().single.id, 'a');

      final legacy = jsonEncode({
        'roleAnalysisUrl': 'https://r', 'roleAnalysisKey': 'RK', 'roleAnalysisModel': 'rm',
        'purifyUrl': 'https://p', 'purifyKey': 'PK', 'purifyModel': 'pm', 'purifyConcurrent': '2',
      });
      expect(await Setting.restoreAiBackup(legacy), 2);
      final restored = Setting.getAiModels();
      expect(restored.map((m) => m.id), ['restored_role', 'restored_purify']);
      expect(restored.first.name, '多角色分析模型');
      expect(restored.first.isRoleAnalysis, isTrue);
      expect(restored.last.isPurify, isTrue);
      expect(restored.last.concurrent, 2);
    });

    test('restore errors carry the original texts', () async {
      await expectLater(Setting.restoreAiBackup(''), throwsA(isA<FormatException>().having((e) => e.message, 'm', '未找到备份数据')));
      await expectLater(Setting.restoreAiBackup('{}'), throwsA(isA<FormatException>().having((e) => e.message, 'm', '备份数据为空')));
      await expectLater(Setting.restoreAiBackup('[1]'), throwsA(isA<FormatException>().having((e) => e.message, 'm', '备份数据为空')));
    });
  });

  group('AI characters and chat sessions are stored per book', () {
    test('characters persist, are isolated per book and an empty list removes the key', () async {
      expect(Setting.getAiCharacters('b1'), isEmpty);
      await Setting.saveAiCharacters('b1', [AiCharacter(id: '1', name: '张三', gender: 1, personality: '勇敢', updatedAt: 5)]);
      await Setting.saveAiCharacters('b2', [AiCharacter(id: '2', name: '李四')]);
      final c = Setting.getAiCharacters('b1');
      expect(c.single.name, '张三');
      expect(c.single.gender, 1);
      expect(Setting.getAiCharacters('b2').single.id, '2');
      await Setting.saveAiCharacters('b1', []);
      expect(Setting.getAiCharacters('b1'), isEmpty);
      expect(Storage.containsKey(Setting.characterKey('b1')), isFalse);
      await Storage.setString(Setting.characterKey('bad'), 'not json');
      expect(Setting.getAiCharacters('bad'), isEmpty);
    });

    test('chat sessions persist with their messages', () async {
      final s = AiChatSession(id: 's1', title: '聊聊', modelId: 'a', deepThinking: true, messages: [
        AiChatMessage(role: 'user', content: '你好', timestamp: 1).toJson(),
      ], createdAt: 1, updatedAt: 2);
      await Setting.saveAiChatSessions('b1', [s]);
      final back = Setting.getAiChatSessions('b1');
      expect(back.single.title, '聊聊');
      expect(back.single.deepThinking, isTrue);
      expect(back.single.messages.length, 1);
      expect(Setting.getAiChatSessions('b2'), isEmpty);
    });
  });

  group('reader chrome settings', () {
    test('header / footer slots are int lists in JSON; invalid content reads as empty', () async {
      expect(Setting.customHeaderLeft, isEmpty);
      await Setting.setIntList(Setting.customHeaderCenterKey, [1, 3, 2]);
      await Setting.setIntList(Setting.customFooterRightKey, [7]);
      expect(Setting.customHeaderCenter, [1, 3, 2]);
      expect(Setting.customFooterRight, [7]);
      expect(Storage.getString('customHeaderCenter'), '[1,3,2]');
      await Storage.setString(Setting.customFooterLeftKey, '["2", 5, "x"]');
      expect(Setting.customFooterLeft, [2, 5]);
      await Storage.setString(Setting.customHeaderRightKey, '{broken');
      expect(Setting.customHeaderRight, isEmpty);
    });

    test('topMenuButtons: default of three, only known ids survive, order is kept', () async {
      expect(Setting.getTopMenuButtons(), ['browser', 'changeSource', 'refresh']);
      expect(Setting.validTopMenuButtons.length, 12);
      await Setting.setTopMenuButtons(['showLog', 'nope', 'bookmark']);
      expect(Setting.getTopMenuButtons(), ['showLog', 'bookmark']);
      await Storage.setString('topMenuButtons', '["zzz"]');
      expect(Setting.getTopMenuButtons(), Setting.defaultTopMenuButtons);
      await Storage.setString('topMenuButtons', 'garbage');
      expect(Setting.getTopMenuButtons(), Setting.defaultTopMenuButtons);
    });
  });

  group('StorageItem (cloud item readitems)', () {
    test('export packs the registered keys, import writes them back', () async {
      await Storage.write('progress:1', '{"p":1}');
      await Storage.write('progress:2', '{"p":2}');
      StorageItem.register('progress:1');
      StorageItem.register('progress:2');
      StorageItem.register('progress:3'); // no content: not exported
      final json = await StorageItem.export();
      expect(jsonDecode(json), {'progress:1': '{"p":1}', 'progress:2': '{"p":2}'});

      final other = await newDevice();
      addTearDown(other.delete);
      StorageItem.readitems.clear();
      expect(await StorageItem.import(json), 2);
      expect(await Storage.read('progress:2'), '{"p":2}');
      expect(StorageItem.readitems, containsAll(['progress:1', 'progress:2']));
      await expectLater(StorageItem.import(''), throwsA(isA<FormatException>().having((e) => e.message, 'm', '您还没有备份')));
    });
  });

  group('BookReadingTimeStorage', () {
    test('adds per book and per day, concurrent adds are not lost, range query sums days', () async {
      final d1 = DateTime(2026, 10, 1);
      final d2 = DateTime(2026, 10, 3);
      await Future.wait([for (var i = 0; i < 10; i++) BookReadingTimeStorage.addReading('book-a', 60, day: d1)]);
      await BookReadingTimeStorage.addReading('book-b', 30, day: d2);
      await BookReadingTimeStorage.addReading('book-a', 0, day: d2); // ignored
      expect(await BookReadingTimeStorage.bookSeconds('book-a'), 600);
      expect(await BookReadingTimeStorage.bookSeconds('book-b'), 30);
      expect(await BookReadingTimeStorage.bookSeconds('none'), 0);
      expect(await BookReadingTimeStorage.daySeconds(d1), 600);
      expect(BookReadingTimeStorage.dayKey(d2), '20261003');
      expect(await BookReadingTimeStorage.secondsInRange(DateTime(2026, 10, 1), DateTime(2026, 10, 2)), 600);
      expect(await BookReadingTimeStorage.secondsInRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)), 630);
      await BookReadingTimeStorage.clearBook('book-a');
      expect(await BookReadingTimeStorage.bookSeconds('book-a'), 0);
    });
  });
}
