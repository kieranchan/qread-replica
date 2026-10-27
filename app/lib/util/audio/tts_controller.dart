// util/audio/tts_controller.dart — speaks a text with one engine of the TTS list (data/tts.dart): the entry the TTS pages use for
// 试听 and the reader's listen page can use per paragraph. Engine kinds by `HttpTts.tp` (the 新建引擎 dialog of tts_setting.dart):
//   0 HTTP 朗读引擎 (imported Legado HttpTTS, util/audio/http_tts.dart)   1 多角色引擎 (per-role engines, needs an AI model)
//   2 火山引擎 (ByteDance WebSocket binary protocol)                     3 MiMo 引擎 (Xiaomi chat-completions audio)
//   4 本地引擎 (sherpa-onnx offline models; member-only)
// TODO(asm 0x61bf4c): the numeric values of `tp` are not recovered; the replica fixes them as above. Volcano, MiMo and local models
// are configured and stored but cannot synthesize in this build (no WebSocket binary client, no sherpa-onnx FFI).
import 'dart:typed_data';

import '../../common/app_dirs.dart';
import '../../data/tts.dart';
import '../../models/httptts.dart';
import 'http_tts.dart';
import 'my_audio_player.dart';
import 'system_tts.dart';

enum TtsKind {
  http(0, '大声朗读'),
  multiRole(1, '中文角色'),
  volcano(2, '火山引擎'),
  mimo(3, 'MiMo引擎'),
  local(4, '本地引擎');

  final int tp;
  final String label;
  const TtsKind(this.tp, this.label);

  static TtsKind of(HttpTts e) => values.firstWhere((k) => k.tp == e.tp, orElse: () => TtsKind.http);
}

class TtsUnavailable implements Exception {
  final String message;
  const TtsUnavailable(this.message);
  @override
  String toString() => message;
}

abstract class TtsController {
  static SystemTtsBackend? _system;
  static Myaudioplayer? _player;

  static SystemTtsBackend get system => _system ??= SystemTtsBackend.create();

  /// Forgets cached backends (tests swap the factories).
  static void reset() {
    _system = null;
    _player = null;
  }

  static bool isSystem(HttpTts e) => e.id == TTSData.defaultEngine.id;

  /// Speaks [text] with [engine]; completes when finished. [speed] is the app's rate (10 = normal); [voice] a voice id/name.
  static Future<void> speak(HttpTts engine, String text, {int speed = 10, String voice = ''}) async {
    if (isSystem(engine)) {
      return system.speak(text, voice: voice, rate: (speed / 20).clamp(0.1, 1.0).toDouble());
    }
    switch (TtsKind.of(engine)) {
      case TtsKind.http:
        final audio = await HttpTtsRunner.synthesize(engine.html, text, speed: speed, voice: voice);
        return playBytes(audio.bytes, ext: audio.ext);
      case TtsKind.multiRole:
        final narr = TTSData.byId(engine.narrationEngineId) ?? TTSData.defaultEngine;
        if (narr.id == engine.id) throw const TtsUnavailable('请选择旁白朗读引擎');
        return speak(narr, text, speed: speed, voice: engine.narrationVoiceId);
      case TtsKind.volcano:
      case TtsKind.mimo:
        throw TtsUnavailable('${TtsKind.of(engine).label}在当前版本中不可用');
      case TtsKind.local:
        throw const TtsUnavailable('本地引擎在当前版本中不可用');
    }
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
