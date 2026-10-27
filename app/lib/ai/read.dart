// ai/read.dart — the AI helpers of reading / listening, configured from `Setting` (storage/setting.dart):
//  * role analysis for the multi-role TTS (0xf07800, caller 0xf063d0): lines `{id, text}` go to the model flagged 多角色
//    (`isRoleAnalysis`) with the original prompt (pool 0x2fc10); the reply is a JSON array of `{id, ispb, gender, str, name,
//    personality}` (dialogue only). Request: temperature 0.01, top_p 0.01, max_tokens 16384, thinking off; timeouts 30 s / 200 s.
//    Results are cached per chapter under `<root>/tts_analysis` (`保存角色分析缓存失败`). Without a model the heuristic split is used
//    (quotes; speaker from `(\S+?)[说道喊道叫呼问笑叹了哭骂]` / `(\S+?)[：:]`).
//  * purification (正文净化, model flagged `isPurify`): the chapter text is sent with a cleaning instruction; on failure the caller
//    keeps the original text (`正文获取失败:Ai净化出错 …`). TODO(asm 0xf089b0): the original purification prompt is assembled at run time
//    and not recovered; the replica's instruction is its own.
// Both need a configured model (`请先配置AiTocken`).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../common/app_dirs.dart';
import '../models/ai_model_config.dart';
import '../storage/setting.dart';
import 'openai_client.dart';

/// One analysed line.
class RoleLine {
  final String id;
  final bool ispb;

  /// 0 男 / 1 女 / 2 未知.
  final int gender;
  final String str;
  final String name;
  final String personality;
  const RoleLine({required this.id, required this.ispb, this.gender = 2, required this.str, this.name = '', this.personality = ''});

  factory RoleLine.fromJson(Map<String, dynamic> j) => RoleLine(
        id: '${j['id'] ?? ''}',
        ispb: j['ispb'] == true || '${j['ispb']}' == 'true',
        gender: int.tryParse('${j['gender'] ?? 2}') ?? 2,
        str: '${j['str'] ?? ''}',
        name: '${j['name'] ?? ''}',
        personality: '${j['personality'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {'id': id, 'ispb': ispb, 'gender': gender, 'str': str, 'name': name, 'personality': personality};
}

abstract class AiRead {
  /// pool 0x2fc10 (the original prompt; the lines follow `内容：` as a JSON array).
  static const String rolePrompt =
      '仅输出JSON数组，不要有任何思考，请只给出答案,必须非常迅速。每个对象包含以下字段：id=必须用拆分前的id，以方便我后面整理，ispb:true=旁白/false=对话，gender:0=男/1=女/2=未知，str=拆分后的文字，name=说话者名字（旁白为空）,personality=说话人的固定人设（先通读全文总结该角色整体性格，如"风流不羁""阴险狡诈"，10字以内；注意不是这句台词的语气情绪；同一角色的每一行必须输出完全相同的personality）,如果是对话名字不能为空请联系上下文判断。我会给你一个json数组，我按照换行拆分了，例如：[{"id":"24","text":"我晃动两根手指，像招狗一样：“来，你过来我告诉你。” "},] 要拆成 [{"id": "24", "ispb": false, "gender": 0, "str": "来，你过来我告诉你。", "name": "联系上下文获取具体姓名，如没有可以用我", "personality": "风流不羁"}](你可以发现拆分后的为id 为拆分前数组的id) ,请分析拆分每行文本，保留原始id，把旁白和对话分开，只有引号包裹的为对话（无论是单引号还是双引号），需要拆分，为了速度你只需输出ispb为false的对话。内容：';

  static const String purifyPrompt =
      '请净化下面的小说正文：删除广告、网址、求票求收藏、作者的话、乱码与无关符号，保持原文段落、标点和内容不变，不要改写、总结或添加任何文字，只输出净化后的正文。正文：\n';

  /// Dio used for the calls (tests inject one).
  static Dio? dio;

  static OpenAiClient _client(AiModelConfig m) =>
      OpenAiClient(m, dio: dio, connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 200));

  /// Analyses [lines] (`{id: text}`, in order). [model] defaults to the 多角色 model; throws [AiException] when none is configured.
  static Future<List<RoleLine>> analyzeRoles(Map<String, String> lines, {AiModelConfig? model}) async {
    final m = model ?? Setting.roleAnalysisModel;
    if (m == null || m.url.isEmpty || m.key.isEmpty) throw const AiException('多角色引擎需要ai支持，请先配置ai接口');
    final input = jsonEncode([for (final e in lines.entries) {'id': e.key, 'text': e.value}]);
    final r = await _client(m).chat([AiMessage.user('$rolePrompt$input')], temperature: 0.01, topP: 0.01, maxTokens: 16384);
    return parseRoles(r.content);
  }

  /// Parses a model reply (fenced or bare JSON array).
  static List<RoleLine> parseRoles(String reply) {
    final text = OpenAiClient.extractJson(reply.trim());
    Object? v;
    try {
      v = jsonDecode(text);
    } catch (_) {
      throw const AiException('Invalid response format');
    }
    if (v is Map && v['data'] is List) v = v['data'];
    if (v is! List) throw const AiException('Invalid response format');
    return [for (final e in v) if (e is Map) RoleLine.fromJson(Map<String, dynamic>.from(e))];
  }

  static final RegExp _quote = RegExp(r'[“"「『‘]([^”"」』’]+)[”"」』’]');
  static final RegExp _speakerVerb = RegExp(r'(\S+?)[说道喊道叫呼问笑叹了哭骂]');
  static final RegExp _speakerColon = RegExp(r'(\S+?)[：:]');

  /// The heuristic split used without a model: every quoted span is a dialogue line, the speaker guessed from the text before it.
  static List<RoleLine> heuristic(Map<String, String> lines) {
    final out = <RoleLine>[];
    for (final e in lines.entries) {
      for (final m in _quote.allMatches(e.value)) {
        final before = e.value.substring(0, m.start);
        final sm = _speakerColon.firstMatch(before) ?? _speakerVerb.firstMatch(before);
        var name = sm?.group(1) ?? '';
        if (name.length > 6) name = name.substring(name.length - 6);
        out.add(RoleLine(id: e.key, ispb: false, str: m.group(1)!, name: name));
      }
    }
    return out;
  }

  /// Cache file of a chapter's analysis: `<root>/tts_analysis/<md5(key)>.json`.
  static File cacheFile(String key) => File(p.join(AppDirs.path('tts_analysis'), '${crypto.md5.convert(utf8.encode(key))}.json'));

  static Future<List<RoleLine>?> readCache(String key) async {
    try {
      final f = cacheFile(key);
      if (!f.existsSync()) return null;
      return parseRoles(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeCache(String key, List<RoleLine> lines) async {
    try {
      final f = cacheFile(key);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode([for (final l in lines) l.toJson()]));
    } catch (_) {
      // 保存角色分析缓存失败
    }
  }

  static Future<void> clearCache() async {
    final d = AppDirs.dir('tts_analysis');
    if (d.existsSync()) {
      for (final f in d.listSync()) {
        try {
          f.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Cached analysis of a chapter, else the model (when [useAi] and a model exists), else the heuristic.
  static Future<List<RoleLine>> rolesFor(String cacheKey, Map<String, String> lines, {bool useAi = true}) async {
    final cached = await readCache(cacheKey);
    if (cached != null) return cached;
    List<RoleLine> r;
    if (useAi && Setting.roleAnalysisModel != null) {
      r = await analyzeRoles(lines);
    } else {
      r = heuristic(lines);
    }
    await writeCache(cacheKey, r);
    return r;
  }

  /// 正文净化 with the model flagged `isPurify`.
  static Future<String> purify(String text, {AiModelConfig? model}) async {
    final m = model ?? Setting.purifyModel;
    if (m == null || m.url.isEmpty || m.key.isEmpty) throw const AiException('请先配置AiTocken');
    final r = await _client(m).chat([AiMessage.user('$purifyPrompt$text')], temperature: 0.01, topP: 0.01, maxTokens: 16384);
    final out = r.content.trim();
    if (out.isEmpty) throw const AiException('Invalid response format');
    return out;
  }
}
