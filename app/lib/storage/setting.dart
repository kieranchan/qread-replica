// storage/setting.dart — typed settings stored in prefs: AI model configs, AI character library, AI chat sessions, the custom
// reader header/footer slots and the reader's top-menu buttons (docs/SETTINGS.md, docs/STORAGE.md).
//
// Original functions (all `Setting` statics, names dropped by the AOT build):
//   0xf0ae00  getAiModels (prefs `aiModelList`, falls back to the legacy migration 0x2a54c8)
//   0x10915e0 saveAiModels            0x10916a8 clearLegacyAiKeys      0x1091944 buildAiBackup (cloud item `ai_model_settings_v2`)
//   0x1090800 restoreAiBackup         0xf04f58 / 0xf0607c getAiCharacters / saveAiCharacters
//   0x108e3f4 / 0x108e308 getAiChatSessions / saveAiChatSessions
//   0x1010228 0x10104d8 ...           custom header/footer slots (`customHeaderLeft` ...)
//   0x10e5cec getTopMenuButtons
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/ai_character.dart';
import '../models/ai_chat_session.dart';
import '../models/ai_model_config.dart';
import 'storage.dart';

abstract class Setting {
  // ------------------------------------------------------------------------------------------ AI model configs

  static const String aiModelListKey = 'aiModelList';

  /// Cloud item name / backup key of the AI settings (docs/API.md "Item names").
  static const String aiBackupItem = 'ai_model_settings_v2';

  /// Legacy single-model prefs keys, migrated into [AiModelConfig]s by [getAiModels].
  static const List<String> legacyAiKeys = [
    'aiUrl', 'aiKey', 'aiModel', 'purifyUrl', 'purifyKey', 'purifyModel', 'purifyConcurrent',
  ];

  /// The configured models; the legacy keys are migrated (ids `legacy_default` / `legacy_purify`, names `默认模型` /
  /// `正文净化模型`) when the new list is absent.
  static List<AiModelConfig> getAiModels() {
    final text = Storage.getString(aiModelListKey);
    if (text.isNotEmpty) {
      try {
        final v = jsonDecode(text);
        if (v is List) {
          return [for (final m in v) if (m is Map) AiModelConfig.fromJson(Map<String, dynamic>.from(m))];
        }
      } catch (_) {}
    }
    return _migrateLegacy();
  }

  /// 0x2a54c8: builds configs from the legacy keys. TODO(asm 0x2a54c8): the original also creates `legacy_role`
  /// (多角色分析模型); the field wiring of that record is not recoverable from the decompilation, the replica marks the
  /// default model as the role-analysis model instead.
  static List<AiModelConfig> _migrateLegacy() {
    final url = Storage.getString('aiUrl');
    final key = Storage.getString('aiKey');
    final model = Storage.getString('aiModel');
    final pUrl = Storage.getString('purifyUrl');
    final pKey = Storage.getString('purifyKey');
    final pModel = Storage.getString('purifyModel');
    final concurrent = Storage.getInt('purifyConcurrent', 1);
    final hasDefault = url.isNotEmpty && model.isNotEmpty;
    final hasPurify = pUrl.isNotEmpty && pModel.isNotEmpty;
    return [
      if (hasDefault)
        AiModelConfig(
            id: 'legacy_default', name: '默认模型', url: url, key: key, model: model, isRoleAnalysis: true, isPurify: !hasPurify, concurrent: concurrent),
      if (hasPurify)
        AiModelConfig(id: 'legacy_purify', name: '正文净化模型', url: pUrl, key: pKey, model: pModel, isPurify: true, concurrent: concurrent),
    ];
  }

  /// Stores the list (`aiModelList`) and drops the legacy keys so they are not migrated a second time.
  static Future<bool> saveAiModels(List<AiModelConfig> models) async {
    try {
      await Storage.setString(aiModelListKey, jsonEncode([for (final m in models) m.toJson()]));
      for (final k in legacyAiKeys) {
        await Storage.remove(k);
      }
      return true;
    } catch (e) {
      debugPrint('AI模型配置保存失败 $e');
      return false;
    }
  }

  /// The model flagged for the "multi-role analysis" / "body purification" jobs, null when none is flagged.
  static AiModelConfig? get roleAnalysisModel => _firstWhere((m) => m.isRoleAnalysis);
  static AiModelConfig? get purifyModel => _firstWhere((m) => m.isPurify);

  static AiModelConfig? modelById(String id) => _firstWhere((m) => m.id == id);

  static AiModelConfig? _firstWhere(bool Function(AiModelConfig) test) {
    for (final m in getAiModels()) {
      if (test(m)) return m;
    }
    return null;
  }

  /// JSON of the backup item: `{version: 2, models: [...], purifyConcurrent: n}` (0x1091944; the original shows `备份成功` /
  /// `备份失败: …` after uploading it).
  static String buildAiBackup() {
    final models = getAiModels();
    final concurrent = models.where((m) => m.isPurify).map((m) => m.concurrent).fold<int>(0, (a, b) => b > a ? b : a);
    return jsonEncode({
      'version': 2,
      'models': [for (final m in models) m.toJson()],
      'purifyConcurrent': concurrent == 0 ? Storage.getInt('purifyConcurrent', 1) : concurrent,
    });
  }

  /// 0x1090800: restores a backup item. Accepts the v2 shape and the legacy shape (`roleAnalysisUrl/Key/Model`,
  /// `purifyUrl/Key/Model`, `purifyConcurrent`, optional `aiUrl/aiKey/aiModel`; ids `restored_default/role/purify`).
  /// Returns the number of models; throws [FormatException] with the original texts (`未找到备份数据`, `备份数据为空`).
  static Future<int> restoreAiBackup(String json) async {
    if (json.trim().isEmpty) throw const FormatException('未找到备份数据');
    final v = jsonDecode(json);
    if (v is! Map) throw const FormatException('备份数据为空');
    final map = Map<String, dynamic>.from(v);
    List<AiModelConfig> models;
    if (map['models'] is List) {
      models = [for (final m in map['models'] as List) if (m is Map) AiModelConfig.fromJson(Map<String, dynamic>.from(m))];
    } else {
      final concurrent = int.tryParse('${map['purifyConcurrent'] ?? ''}') ?? 1;
      String s(String k) => '${map[k] ?? ''}';
      models = [
        if (s('aiUrl').isNotEmpty || s('aiModel').isNotEmpty)
          AiModelConfig(id: 'restored_default', name: '默认模型', url: s('aiUrl'), key: s('aiKey'), model: s('aiModel'), concurrent: concurrent),
        if (s('roleAnalysisUrl').isNotEmpty)
          AiModelConfig(
              id: 'restored_role', name: '多角色分析模型', url: s('roleAnalysisUrl'), key: s('roleAnalysisKey'), model: s('roleAnalysisModel'), isRoleAnalysis: true, concurrent: concurrent),
        if (s('purifyUrl').isNotEmpty)
          AiModelConfig(id: 'restored_purify', name: '正文净化模型', url: s('purifyUrl'), key: s('purifyKey'), model: s('purifyModel'), isPurify: true, concurrent: concurrent),
      ];
    }
    if (models.isEmpty) throw const FormatException('备份数据为空');
    await saveAiModels(models);
    return models.length;
  }

  // ------------------------------------------------------------------------------- AI characters and chat sessions

  /// Per-book key of the character library. TODO(asm 0xf04f58): the original builds the key as `"$static…"` from one
  /// static string (0x2480) that is not recoverable; the replica uses `ai_characters_<bookKey>`.
  static String characterKey(String bookKey) => 'ai_characters_$bookKey';

  /// Per-book key of the chat sessions. TODO(asm 0x108e3f4): see [characterKey] (static 0x2474).
  static String chatSessionKey(String bookKey) => 'ai_chat_sessions_$bookKey';

  /// 0xf04f58: `[]` when nothing is stored; a parse error is logged (`AI角色库读取失败 …`) and gives `[]`.
  static List<AiCharacter> getAiCharacters(String bookKey) {
    final text = Storage.getString(characterKey(bookKey));
    if (text.isEmpty) return [];
    try {
      final v = jsonDecode(text);
      if (v is! List) return [];
      return [for (final m in v) if (m is Map) AiCharacter.fromJson(Map<String, dynamic>.from(m))];
    } catch (e) {
      debugPrint('AI角色库读取失败 $e');
      return [];
    }
  }

  /// 0xf0607c; an empty list removes the key.
  static Future<bool> saveAiCharacters(String bookKey, List<AiCharacter> list) async {
    try {
      if (list.isEmpty) {
        await Storage.remove(characterKey(bookKey));
      } else {
        await Storage.setString(characterKey(bookKey), jsonEncode([for (final c in list) c.toJson()]));
      }
      return true;
    } catch (e) {
      debugPrint('AI角色库保存失败 $e');
      return false;
    }
  }

  /// 0x108e3f4.
  static List<AiChatSession> getAiChatSessions(String bookKey) {
    final text = Storage.getString(chatSessionKey(bookKey));
    if (text.isEmpty) return [];
    try {
      final v = jsonDecode(text);
      if (v is! List) return [];
      return [for (final m in v) if (m is Map) AiChatSession.fromJson(Map<String, dynamic>.from(m))];
    } catch (e) {
      debugPrint('AI聊天会话读取失败 $e');
      return [];
    }
  }

  /// 0x108e308.
  static Future<bool> saveAiChatSessions(String bookKey, List<AiChatSession> list) async {
    try {
      if (list.isEmpty) {
        await Storage.remove(chatSessionKey(bookKey));
      } else {
        await Storage.setString(chatSessionKey(bookKey), jsonEncode([for (final s in list) s.toJson()]));
      }
      return true;
    } catch (e) {
      debugPrint('AI聊天会话保存失败 $e');
      return false;
    }
  }

  // ------------------------------------------------------------------------------- reader header / footer slots

  static const String customHeaderLeftKey = 'customHeaderLeft';
  static const String customHeaderCenterKey = 'customHeaderCenter';
  static const String customHeaderRightKey = 'customHeaderRight';
  static const String customFooterLeftKey = 'customFooterLeft';
  static const String customFooterCenterKey = 'customFooterCenter';
  static const String customFooterRightKey = 'customFooterRight';

  /// A slot holds a list of item ids (ints) stored as JSON text; absent or invalid gives `[]`.
  static List<int> getIntList(String key) {
    final text = Storage.getString(key);
    if (text.isEmpty) return [];
    try {
      final v = jsonDecode(text);
      if (v is! List) return [];
      return [for (final e in v) if (e is num) e.toInt() else if (int.tryParse('$e') != null) int.parse('$e')];
    } catch (_) {
      return [];
    }
  }

  static Future<void> setIntList(String key, List<int> value) => Storage.setString(key, jsonEncode(value));

  static List<int> get customHeaderLeft => getIntList(customHeaderLeftKey);
  static List<int> get customHeaderCenter => getIntList(customHeaderCenterKey);
  static List<int> get customHeaderRight => getIntList(customHeaderRightKey);
  static List<int> get customFooterLeft => getIntList(customFooterLeftKey);
  static List<int> get customFooterCenter => getIntList(customFooterCenterKey);
  static List<int> get customFooterRight => getIntList(customFooterRightKey);

  // ------------------------------------------------------------------------------------- top menu buttons

  static const String topMenuButtonsKey = 'topMenuButtons';

  /// The twelve button ids the reader's top menu knows (pool list pp+0x53470), and the default of three (pp+0x53448).
  static const List<String> validTopMenuButtons = [
    'browser', 'changeSource', 'refresh', 'batchDownload', 'sourceLogin', 'chapterUrl', 'bookmark', 'searchContent',
    'buyChapter', 'backupSetting', 'restoreSetting', 'showLog',
  ];
  static const List<String> defaultTopMenuButtons = ['browser', 'changeSource', 'refresh'];

  /// 0x10e5cec: the stored ids, in stored order, keeping only known ids; the default when nothing valid is stored.
  static List<String> getTopMenuButtons() {
    final text = Storage.getString(topMenuButtonsKey);
    if (text.isEmpty) return List<String>.of(defaultTopMenuButtons);
    try {
      final v = jsonDecode(text);
      if (v is List) {
        final list = [for (final e in v) '$e'].where(validTopMenuButtons.contains).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return List<String>.of(defaultTopMenuButtons);
  }

  static Future<void> setTopMenuButtons(List<String> ids) =>
      Storage.setString(topMenuButtonsKey, jsonEncode(ids.where(validTopMenuButtons.contains).toList()));
}
