// ai/volcano_tts.dart — 火山引擎 (ByteDance openspeech) speech synthesis with the user's own App ID + Access Token, as the original
// `VolcanoTTS` (synthesize 0xea0b40, socket 0xea0f9c, frame parser 0xea1798, listener 0xea1518):
//   * `wss://openspeech.bytedance.com/api/v1/tts/ws_binary`, header `Authorization: Bearer; <token>`, connect timeout 15 s
//     (`火山引擎 WebSocket 连接超时`), synthesis timeout 60 s (`火山引擎 TTS 合成超时`).
//   * one binary frame: header `kDefaultHeader` [0x11, 0x10, 0x11, 0x00] (v1, 4-byte header, full client request, JSON, gzip),
//     4-byte big-endian payload size, gzip(JSON) payload
//     `{app:{appid, token, cluster:"volcano_tts"}, user:{uid:"666"}, audio:{voice_type, encoding:"mp3"},
//       request:{reqid:<uuid v4>, text, text_type:"plain", operation:"submit"}}`.
//   * replies: message type 0xB (audio-only) with flags 0 = ack, otherwise a signed sequence number + payload size + mp3 bytes
//     (negative sequence = last chunk); type 0xF = error (`code`, message, gzip when compression 1) → `火山引擎 TTS 错误(code=…): …`;
//     short frames `响应包过短` / `响应包无 payload`; a text frame → `火山引擎 TTS 返回非预期文本消息: …`.
//   * credentials: `volcano_tts_app_id` / `volcano_tts_access_token` (missing → the original's long hint).
//   * the 21 preset voices (`VolcanoVoice`, pp+0x4cb58) in the original order.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../storage/storage.dart';

class VolcanoTTSException implements Exception {
  final String message;
  const VolcanoTTSException(this.message);
  @override
  String toString() => message;
}

/// One preset voice: [id] is the `voice_type`, [female] the gender, [scene] / [description] the picker texts.
class VolcanoVoice {
  final String id;
  final String name;
  final bool female;
  final String scene;
  final String description;
  const VolcanoVoice(this.id, this.name, this.female, this.scene, this.description);

  String get gender => female ? '女' : '男';
}

abstract class VolcanoTTS {
  static const String endpoint = 'wss://openspeech.bytedance.com/api/v1/tts/ws_binary';
  static const String appIdKey = 'volcano_tts_app_id';
  static const String tokenKey = 'volcano_tts_access_token';
  static const String consoleUrl = 'https://console.volcengine.com/speech/new/setting/apikeys';
  static const String missing =
      '未配置火山引擎 TTS 凭证（App ID / Access Token）。请在「朗读设置页 → 火山引擎」弹窗右上角点「设置凭证」按钮填写。获取地址：$consoleUrl';
  static const List<int> kDefaultHeader = [0x11, 0x10, 0x11, 0x00];

  static const List<VolcanoVoice> voices = [
    VolcanoVoice('BV700_streaming', '灿灿', true, '通用场景', '通用女声，亲切自然'),
    VolcanoVoice('BV701_streaming', '擎苍', false, '通用场景', '通用男声，沉稳大气'),
    VolcanoVoice('BV406_streaming', '梓梓', true, '通用场景', '通用女声，温柔甜美'),
    VolcanoVoice('BV407_streaming', '燃燃', true, '通用场景', '通用女声，活力清新'),
    VolcanoVoice('BV705_streaming', '炀炀', true, '通用场景', '通用女声，温暖亲切'),
    VolcanoVoice('BV001_streaming', '通用女声', true, '通用场景', '通用女声'),
    VolcanoVoice('BV002_streaming', '通用男声', false, '通用场景', '通用男声'),
    VolcanoVoice('BV123_streaming', '阳光青年', false, '有声阅读', '阳光男声，适合小说朗读'),
    VolcanoVoice('BV120_streaming', '反卷青年', false, '有声阅读', '慵懒男声，反内卷风格'),
    VolcanoVoice('BV119_streaming', '通用赘婿', false, '有声阅读', '磁性男声，赘婿文风格'),
    VolcanoVoice('BV115_streaming', '古风少御', true, '有声阅读', '古风女声，清冷优雅'),
    VolcanoVoice('BV107_streaming', '霸气青叔', false, '有声阅读', '霸气男声'),
    VolcanoVoice('BV100_streaming', '质朴青年', false, '有声阅读', '质朴男声'),
    VolcanoVoice('BV104_streaming', '温柔淑女', true, '有声阅读', '温柔女声，淑女风格'),
    VolcanoVoice('BV102_streaming', '儒雅青年', false, '有声阅读', '儒雅男声'),
    VolcanoVoice('BV405_streaming', '甜美小源', true, '智能助手', '甜美女声，适合智能助手'),
    VolcanoVoice('BV007_streaming', '亲切女声', true, '智能助手', '亲切女声'),
    VolcanoVoice('BV009_streaming', '知性女声', true, '智能助手', '知性女声'),
    VolcanoVoice('BV008_streaming', '亲切男声', false, '智能助手', '亲切男声'),
    VolcanoVoice('BV034_streaming', '知性姐姐', true, '智能助手', '知性女声'),
    VolcanoVoice('BV033_streaming', '温柔小哥', false, '智能助手', '温柔男声'),
  ];

  static VolcanoVoice? voice(String id) {
    for (final v in voices) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// Replaceable in tests (a local WebSocket server).
  static String url = endpoint;
  static Duration connectTimeout = const Duration(seconds: 15);
  static Duration timeout = const Duration(seconds: 60);

  static String get appId => Storage.getString(appIdKey);
  static String get accessToken => Storage.getString(tokenKey);

  static Future<void> saveCredentials(String appId, String token) async {
    await Storage.setString(appIdKey, appId.trim());
    await Storage.setString(tokenKey, token.trim());
  }

  /// The request JSON of 0xea0b40.
  static Map<String, dynamic> requestJson({required String appId, required String token, required String voice, required String text, String? reqid}) => {
        'app': {'appid': appId, 'token': token, 'cluster': 'volcano_tts'},
        'user': {'uid': '666'},
        'audio': {'voice_type': voice, 'encoding': 'mp3'},
        'request': {'reqid': reqid ?? const Uuid().v4(), 'text': text, 'text_type': 'plain', 'operation': 'submit'},
      };

  /// header + payload size (big endian) + gzip(JSON).
  static Uint8List buildFrame(Map<String, dynamic> json) {
    final payload = gzip.encode(utf8.encode(jsonEncode(json)));
    final b = BytesBuilder()
      ..add(kDefaultHeader)
      ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
      ..add(payload);
    return b.toBytes();
  }

  /// One server frame (0xea1798): audio bytes plus whether it was the last one; throws on error frames.
  static ({Uint8List audio, bool last}) parseFrame(Uint8List data) {
    if (data.length < 4) throw const VolcanoTTSException('响应包过短');
    final headerSize = (data[0] & 0x0f) * 4;
    final type = data[1] >> 4;
    final flags = data[1] & 0x0f;
    final compression = data[2] & 0x0f;
    if (data.length < headerSize) throw const VolcanoTTSException('响应包无 payload');
    final p = ByteData.sublistView(data, headerSize);
    if (type == 0xb) {
      if (flags == 0) return (audio: Uint8List(0), last: false);
      if (p.lengthInBytes < 8) throw const VolcanoTTSException('响应包无 payload');
      final seq = p.getInt32(0);
      final size = p.getUint32(4);
      final end = 8 + size > p.lengthInBytes ? p.lengthInBytes : 8 + size;
      final audio = Uint8List.sublistView(data, headerSize + 8, headerSize + end);
      return (audio: audio, last: seq < 0 || flags == 2 || flags == 3);
    }
    if (type == 0xf) {
      final code = p.lengthInBytes >= 4 ? p.getUint32(0) : -1;
      var msg = Uint8List(0);
      if (p.lengthInBytes >= 8) {
        final size = p.getUint32(4);
        final end = 8 + size > p.lengthInBytes ? p.lengthInBytes : 8 + size;
        msg = Uint8List.sublistView(data, headerSize + 8, headerSize + end);
      }
      var text = '';
      try {
        text = utf8.decode(compression == 1 ? gzip.decode(msg) : msg, allowMalformed: true);
      } catch (_) {
        text = utf8.decode(msg, allowMalformed: true);
      }
      throw VolcanoTTSException('火山引擎 TTS 错误(code=$code): $text');
    }
    return (audio: Uint8List(0), last: false);
  }

  /// Synthesizes [text] with [voice] (`voice_type`), returning mp3 bytes. Credentials default to the stored ones.
  static Future<Uint8List> synthesize(String text, {required String voice, String? appId, String? token}) async {
    final id = (appId ?? VolcanoTTS.appId).trim();
    final tk = (token ?? accessToken).trim();
    if (id.isEmpty || tk.isEmpty) throw const VolcanoTTSException(missing);
    if (text.trim().isEmpty) return Uint8List(0);
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(url, headers: {'Authorization': 'Bearer; $tk'}).timeout(connectTimeout,
          onTimeout: () => throw const VolcanoTTSException('火山引擎 WebSocket 连接超时'));
    } on VolcanoTTSException {
      rethrow;
    } catch (e) {
      throw VolcanoTTSException('火山引擎 WebSocket 错误: $e');
    }
    final out = BytesBuilder();
    final done = Completer<Uint8List>();
    late final StreamSubscription<dynamic> sub;
    sub = ws.listen(
      (msg) {
        if (done.isCompleted) return;
        if (msg is String) {
          done.completeError(VolcanoTTSException('火山引擎 TTS 返回非预期文本消息: $msg'));
          return;
        }
        try {
          final f = parseFrame(msg is Uint8List ? msg : Uint8List.fromList(msg as List<int>));
          out.add(f.audio);
          if (f.last) done.complete(out.toBytes());
        } catch (e) {
          done.completeError(e);
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(VolcanoTTSException('火山引擎 WebSocket 错误: $e'));
      },
      onDone: () {
        if (!done.isCompleted) {
          final b = out.toBytes();
          b.isEmpty ? done.completeError(const VolcanoTTSException('火山引擎 WebSocket 错误: 连接已关闭')) : done.complete(b);
        }
      },
      cancelOnError: true,
    );
    ws.add(buildFrame(requestJson(appId: id, token: tk, voice: voice, text: text)));
    try {
      return await done.future.timeout(timeout, onTimeout: () => throw const VolcanoTTSException('火山引擎 TTS 合成超时'));
    } finally {
      await sub.cancel();
      await ws.close();
    }
  }
}
