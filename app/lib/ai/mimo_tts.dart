// ai/mimo_tts.dart — 小米 MiMo speech synthesis with the user's own API key (`mi_ai_api_key`), the three engines of the original:
//   preset  0xe9f3ac  model `mimo-v2.5-tts`, audio {format: wav, voice: <preset name>}
//   clone   0xe9dcd0  model `mimo-v2.5-tts-voiceclone`, audio {format: wav, voice: <reference audio data URI>}
//   design  0xe9c8cc  model `mimo-v2.5-tts-voicedesign`, audio {format: wav}; the voice description is the user message
//                     (+ `\n\n【自然语言控制】\n<instruction>`)
// All: POST `https://api.xiaomimimo.com/v1/chat/completions`, `Authorization: Bearer <key>`, JSON, `stream: false`; messages =
// optional user message (natural-language instruction) + assistant message = the text (cut to 2000 characters); the reply's
// `choices[0].message.audio.data` is base64 WAV. Error texts are the original's.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../storage/storage.dart';

class MimoTTSException implements Exception {
  final String message;
  const MimoTTSException(this.message);
  @override
  String toString() => message;
}

class MimoVoice {
  final String id;
  final String name;
  final bool female;
  final String description;
  const MimoVoice(this.id, this.name, this.female, this.description);
}

abstract class MimoTTS {
  static const String keyName = 'mi_ai_api_key';
  static const String baseUrl = 'https://api.xiaomimimo.com/v1';
  static const String presetModel = 'mimo-v2.5-tts';
  static const String cloneModel = 'mimo-v2.5-tts-voiceclone';
  static const String designModel = 'mimo-v2.5-tts-voicedesign';
  static const int maxText = 2000;
  static const int maxDesign = 500;

  /// pp+0x4c948, in the original order.
  static const List<MimoVoice> voices = [
    MimoVoice('冰糖', '冰糖', true, '甜美女声，温柔亲切，情感表达细腻，默认推荐音色'),
    MimoVoice('茉莉', '茉莉', true, '清澈优雅女声，语气柔和，适合文学与情感类文本'),
    MimoVoice('苏打', '苏打', false, '磁性男声，沉稳专业，适合新闻播报与纪实类解说'),
    MimoVoice('白桦', '白桦', false, '温润男声，自然流畅，适合叙事与有声阅读'),
  ];

  /// Replaceable in tests (local server).
  static String url = '$baseUrl/chat/completions';
  static Dio? dio;

  static String get apiKey => Storage.getString(keyName);
  static Future<void> saveKey(String key) => Storage.setString(keyName, key.trim());

  static String _cut(String text) => text.length > maxText ? text.substring(0, maxText) : text;

  /// The request body (shared by the three models).
  static Map<String, dynamic> body({required String model, required String text, String user = '', String? voice}) => {
        'model': model,
        'messages': [
          if (user.trim().isNotEmpty) {'role': 'user', 'content': user.trim()},
          {'role': 'assistant', 'content': _cut(text)},
        ],
        'audio': {'format': 'wav', 'voice': ?voice},
        'stream': false,
      };

  /// 0xe9f3ac: a preset voice ([voice] = 冰糖 / 茉莉 / 苏打 / 白桦), optional natural-language [instruction].
  static Future<Uint8List> synthesize(String text, {required String voice, String instruction = ''}) async {
    if (text.trim().isEmpty) return Uint8List(0);
    final key = apiKey.trim();
    if (key.isEmpty) throw const MimoTTSException('小米 MiMo API Key 为空，请先设置 mi_ai_api_key（可在设置页或通过 getmitocken() 写入）');
    return _post(key, body(model: presetModel, text: text.trim(), user: instruction, voice: voice), 'MiMo', null);
  }

  /// 0xe9dcd0: voice cloning; [referenceAudio] is a `data:<mime>;base64,…` URI (mp3/wav; base64 ≤ about 8 MB).
  static Future<Uint8List> clone(String text, {required String referenceAudio, String instruction = ''}) async {
    if (text.trim().isEmpty) return Uint8List(0);
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const MimoTTSException('MiMoClone: 未配置 MiMo API Key，请在 MiMo 引擎菜单里先设置 Key（https://mimo.mi.com/）。音色复刻模型 mimo-v2.5-tts-voiceclone 与预置音色共享同一个 Key。');
    }
    if (referenceAudio.length > 8 * 1024 * 1024) throw const MimoTTSException('MiMoClone: 参考音频过大（base64 超过约 8MB），请使用 ≤10MB 的音频文件');
    return _post(key, body(model: cloneModel, text: text.trim(), user: instruction, voice: referenceAudio), 'MiMoClone', 'MiMoCloneTTS-Dart/1.0');
  }

  /// 0xe9c8cc: a voice from a text [description] (≤ 500 characters); [instruction] is appended as `【自然语言控制】`.
  static Future<Uint8List> voiceDesign(String text, {required String description, String instruction = ''}) async {
    if (text.trim().isEmpty) return Uint8List(0);
    final d = description.trim();
    if (d.isEmpty) throw const MimoTTSException('MiMoVoiceDesign: 音色描述不能为空');
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const MimoTTSException(
          'MiMoVoiceDesign: 未配置 MiMo API Key，请在 MiMo 引擎菜单里先设置 Key（https://mimo.mi.com/）。文本定制音色模型 mimo-v2.5-tts-voicedesign 与预置音色、克隆共享同一个 Key。');
    }
    final user = instruction.trim().isEmpty ? d : '$d\n\n【自然语言控制】\n${instruction.trim()}';
    return _post(key, body(model: designModel, text: text.trim(), user: user), 'MiMoVoiceDesign', 'MiMoVoiceDesignTTS-Dart/1.0');
  }

  /// Turns a picked file into the data URI the clone engine stores (`data:audio/wav;base64,…` / `audio/mpeg`).
  static String dataUri(Uint8List bytes, String fileName) {
    final mime = fileName.toLowerCase().endsWith('.mp3') ? 'audio/mpeg' : 'audio/wav';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  static Future<Uint8List> _post(String key, Map<String, dynamic> body, String tag, String? agent) async {
    final d = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: Duration(seconds: agent == null ? 60 : 180),
          sendTimeout: const Duration(seconds: 60),
        ));
    Response<dynamic> r;
    try {
      r = await d.post<dynamic>(
        url,
        data: jsonEncode(body),
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': ?agent,
          },
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
        throw MimoTTSException('请求超时: ${e.message ?? e.type.name}');
      }
      throw MimoTTSException('$tag 调用失败: ${e.message ?? e.type.name}');
    }
    final status = r.statusCode ?? 0;
    final text = '${r.data ?? ''}';
    if (status < 200 || status >= 300) {
      final hint = switch (status) {
        401 || 403 => '（请确认 MiMo API Key 是否正确）',
        429 => '（请求过快或限流，稍后再试）',
        _ => '',
      };
      throw MimoTTSException('$tag HTTP $status: ${text.length > 300 ? text.substring(0, 300) : text}$hint');
    }
    if (text.trim().isEmpty) throw MimoTTSException('$tag: 响应为空');
    Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw MimoTTSException('$tag: 响应为空');
    }
    if (j is Map && j['error'] != null) throw MimoTTSException('$tag 接口返回错误: ${j['error']}');
    final choices = j is Map ? j['choices'] : null;
    if (choices is! List || choices.isEmpty) throw const MimoTTSException('返回 choices 为空');
    final msg = choices.first is Map ? (choices.first as Map)['message'] : null;
    final audio = msg is Map ? msg['audio'] : null;
    final data = audio is Map ? audio['data'] : null;
    if (data is! String || data.isEmpty) throw const MimoTTSException('未找到 message.audio.data 字段，请检查模型返回');
    try {
      final bytes = base64Decode(data);
      if (bytes.isEmpty) throw const MimoTTSException('返回音频数据为空');
      return bytes;
    } on MimoTTSException {
      rethrow;
    } catch (e) {
      throw MimoTTSException('音频 base64 解码失败: $e');
    }
  }
}
