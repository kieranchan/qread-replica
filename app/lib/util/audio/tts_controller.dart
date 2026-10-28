// util/audio/tts_controller.dart — speaks a text with one engine of the TTS list (data/tts.dart): the entry the TTS pages use for
// 试听 and the reader's listen page can use per paragraph.
//
// `HttpTts.tp` as the original (0x1c3158 / 0xe6e2dc / the 新建引擎 dialog 0x61bf4c): 0 = normal engine, 1 = multi-role engine.
// A normal engine is a page (util/audio/tts_page.dart) whose `getttsurl` names the backend in `method` (dispatcher 0xe953c4):
//   data → base64 body · volcano → ai/volcano_tts.dart · mimo / mimoclone / mimovoicedesign → ai/mimo_tts.dart
//   edge → the Microsoft Edge voice (needs the Edge client token the porting rules forbid copying: unavailable here)
//   bdtts / bdttsclone → sherpa-onnx local models (util/audio/local/): `url` = model name, `body` = voice id (bdtts) or the reference
//     WAV data URI with `headers.refText` (bdttsclone). Member gate as the original (0xe959d4): for bdtts a non-member hears
//     `您好，本地引擎仅支持会员使用。` spoken by the model instead of the text, unless the call carries a [debug] callback (the 试听
//     path of the engine list, 0xe90260); bdttsclone has no gate in the original.
//   anything else → an HTTP request (get / post) whose reply is the audio.
// [TtsKind] is the replica's classification for the pages (derived from the page, not stored). Engines saved by earlier replica
// builds (Legado HttpTTS maps, `tp` 2 / 3 / 4 for Volcano / MiMo / local) keep working.
import 'dart:convert';
import 'dart:typed_data';

import '../../ai/mimo_tts.dart';
import '../../ai/volcano_tts.dart';
import '../../common/app_dirs.dart';
import '../../data/tts.dart';
import '../../data/user.dart';
import '../../models/httptts.dart';
import 'local/local_tts_manager.dart';
import 'http_tts.dart';
import 'my_audio_player.dart';
import 'system_tts.dart';
import 'tts_page.dart';

enum TtsKind {
  http(0, '普通引擎'),
  multiRole(1, '多角色引擎'),
  volcano(0, '火山引擎'),
  mimo(0, 'MiMo引擎'),
  local(0, '本地引擎'),
  edge(0, '大声朗读');

  /// The `tp` an engine of this kind is stored with.
  final int tp;
  final String label;
  const TtsKind(this.tp, this.label);

  /// Kind of a page `method`.
  static TtsKind ofMethod(String method) => switch (method) {
        'volcano' => volcano,
        'mimo' || 'mimoclone' || 'mimovoicedesign' => mimo,
        'bdtts' || 'bdttsclone' => local,
        'edge' => edge,
        _ => http,
      };

  static TtsKind of(HttpTts e) {
    switch (e.tp) {
      case 1:
        return multiRole;
      case 2:
        return volcano; // replica builds before the fidelity pass
      case 3:
        return mimo;
      case 4:
        return local;
    }
    final page = TTSData.pageOf(e);
    if (page.isEmpty) return http;
    final r = TtsPages.literal(page);
    return r == null ? http : ofMethod(r.method);
  }
}

class TtsUnavailable implements Exception {
  final String message;
  const TtsUnavailable(this.message);
  @override
  String toString() => message;
}

abstract class TtsController {
  static const String localVipOnly = '您好，本地引擎仅支持会员使用。';
  /// Kept for callers of earlier builds; the local engine is part of this build now.
  static const String localMissing = '当前版本不包含本地引擎（sherpa-onnx）';
  static const String edgeMissing = '大声朗读（微软 Edge 语音）在当前版本中不可用';

  static SystemTtsBackend? _system;
  static Myaudioplayer? _player;

  static SystemTtsBackend get system => _system ??= SystemTtsBackend.create();

  /// Forgets cached backends (tests swap the factories).
  static void reset() {
    _system = null;
    _player = null;
  }

  static bool isSystem(HttpTts e) => e.id == TTSData.defaultEngine.id || e.id == TTSData.legacySystemId;

  /// Speaks [text] with [engine]; completes when finished. [speed] is the app's rate (10 = normal); [voice] a voice id/name.
  /// [debug] is the original's log callback of the 试听 path (it also lifts the local-engine member gate, see the file comment).
  static Future<void> speak(HttpTts engine, String text, {int speed = 10, String voice = '', void Function(String message)? debug}) async {
    if (isSystem(engine)) {
      return system.speak(text, voice: voice, rate: (speed / 20).clamp(0.1, 1.0).toDouble());
    }
    if (TtsKind.of(engine) == TtsKind.multiRole) {
      final narr = TTSData.byId(engine.narrationEngineId) ?? TTSData.defaultEngine;
      if (narr.id == engine.id) throw const TtsUnavailable('请选择旁白朗读引擎');
      return speak(narr, text, speed: speed, voice: engine.narrationVoiceId, debug: debug);
    }
    final audio = await synthesize(engine, text, speed: speed, voice: voice, debug: debug);
    if (audio.bytes.isEmpty) return;
    return playBytes(audio.bytes, ext: audio.ext);
  }

  /// The audio [engine] produces for [text] (normal engines only; the system voice and multi-role setups have no bytes).
  /// [juese] / [gender] (`male` / `female` / `unknown`) are passed to `getttsurl` for multi-role reading.
  static Future<TtsAudio> synthesize(HttpTts engine, String text,
      {int speed = 10, String voice = '', String juese = '', String gender = '', void Function(String message)? debug}) async {
    if (isSystem(engine)) throw const TtsUnavailable('系统朗读不生成音频');
    switch (engine.tp) {
      case 1:
        throw const TtsUnavailable('请选择旁白朗读引擎');
      case 2:
        return run(TtsPageRequest('volcano', '', const {}, voice.isNotEmpty ? voice : '${engine.html['voice'] ?? ''}'), text,
            volcanoAppId: '${engine.html['appid'] ?? ''}', volcanoToken: '${engine.html['token'] ?? ''}');
      case 3:
        return run(TtsPageRequest('mimo', '', const {}, voice.isNotEmpty ? voice : '${engine.html['voice'] ?? ''}'), text);
      case 4:
        return run(const TtsPageRequest('bdtts', '', {}, ''), text, debug: debug);
    }
    final page = TTSData.pageOf(engine);
    if (page.isEmpty) {
      return HttpTtsRunner.synthesize(engine.html, text, speed: speed, voice: voice);
    }
    final req = await TtsPages.request(page, text, speechRate: speed * 5, juese: juese, gender: gender);
    return run(req, text, debug: debug);
  }

  /// Dispatches one `getttsurl` result (0xe953c4).
  static Future<TtsAudio> run(TtsPageRequest r, String text,
      {String volcanoAppId = '', String volcanoToken = '', void Function(String message)? debug}) async {
    switch (r.method) {
      case 'data':
        final bytes = base64Decode(r.body.contains(',') && r.body.startsWith('data:') ? r.body.substring(r.body.indexOf(',') + 1) : r.body);
        return TtsAudio(bytes, _sniff(bytes));
      case 'edge':
        throw const TtsUnavailable(edgeMissing);
      case 'volcano':
        final b = await VolcanoTTS.synthesize(text,
            voice: r.body, appId: volcanoAppId.isEmpty ? null : volcanoAppId, token: volcanoToken.isEmpty ? null : volcanoToken);
        return TtsAudio(b, 'audio/mpeg');
      case 'mimo':
        return TtsAudio(await MimoTTS.synthesize(text, voice: r.body, instruction: r.url), 'audio/wav');
      case 'mimoclone':
        return TtsAudio(await MimoTTS.clone(text, referenceAudio: r.body, instruction: r.url), 'audio/wav');
      case 'mimovoicedesign':
        return TtsAudio(await MimoTTS.voiceDesign(text, description: r.body, instruction: r.url), 'audio/wav');
      case 'bdtts':
        final voiceId = int.tryParse(r.body.trim()) ?? 0;
        final say = UserSession.isvip || debug != null ? text : localVipOnly;
        return TtsAudio(await LocalTtsEngine.instance.synthesize(r.url, voiceId, say), 'audio/wav');
      case 'bdttsclone':
        return TtsAudio(
            await LocalTtsEngine.instance
                .synthesize(r.url, 0, text, referenceAudioDataUri: r.body, referenceText: r.headers['refText'] ?? ''),
            'audio/wav');
    }
    final res = await TtsPages.fetch(r);
    final bytes = Uint8List.fromList(res.bytes);
    return TtsAudio(bytes, res.contentType.isEmpty ? _sniff(bytes) : res.contentType);
  }

  static String _sniff(List<int> b) {
    if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) return 'audio/wav';
    if (b.length > 4 && b[0] == 0x4f && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) return 'audio/ogg';
    return 'audio/mpeg';
  }

  /// Plays synthesized audio through `<root>/audio/_tts_play.<ext>`.
  static Future<void> playBytes(Uint8List bytes, {String ext = 'mp3'}) async {
    final p = _player ??= Myaudioplayer();
    await p.stop();
    await p.setBytes(bytes, AppDirs.dir('audio'), '_tts_play.$ext');
    await p.play();
    await p.completed;
  }

  static Future<void> stop() async {
    await _system?.stop();
    await _player?.stop();
  }
}
