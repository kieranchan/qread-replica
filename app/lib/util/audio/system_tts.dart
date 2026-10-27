// util/audio/system_tts.dart — the 系统默认 engine (flutter_tts) behind [SystemTtsBackend] so pages and tests do not need the plugin.
// Voices come from `getVoices` (cached in prefs `ttsVoices` by the original's flutter_tts fork; here in memory). iOS hint strings of the
// voice pickers: `前往 设置 → 辅助功能 → 阅读与朗读 → 语音 下载更多发音人` (iOS) / `前往 系统设置 → … → 系统语音 …` (macOS).
import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

class TtsVoice {
  final String name;
  final String locale;
  const TtsVoice(this.name, this.locale);
}

abstract class SystemTtsBackend {
  static SystemTtsBackend Function() create = FlutterTtsBackend.new;

  Future<List<TtsVoice>> voices();

  /// Speaks [text]; completes when the utterance finished (or was stopped). [rate] 0..1 (flutter_tts scale).
  Future<void> speak(String text, {String voice = '', String locale = '', double rate = 0.5, double volume = 1});
  Future<void> stop();
}

class FlutterTtsBackend implements SystemTtsBackend {
  final FlutterTts _t = FlutterTts();
  Completer<void>? _done;

  FlutterTtsBackend() {
    _t.setCompletionHandler(_finish);
    _t.setCancelHandler(_finish);
    _t.setErrorHandler((_) => _finish());
  }

  void _finish() {
    final d = _done;
    _done = null;
    if (d != null && !d.isCompleted) d.complete();
  }

  @override
  Future<List<TtsVoice>> voices() async {
    try {
      final v = await _t.getVoices;
      if (v is! List) return [];
      return [
        for (final e in v)
          if (e is Map) TtsVoice('${e['name'] ?? ''}', '${e['locale'] ?? ''}'),
      ]..sort((a, b) {
          final za = a.locale.startsWith('zh') ? 0 : 1;
          final zb = b.locale.startsWith('zh') ? 0 : 1;
          return za != zb ? za - zb : a.name.compareTo(b.name);
        });
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> speak(String text, {String voice = '', String locale = '', double rate = 0.5, double volume = 1}) async {
    await stop();
    if (voice.isNotEmpty) await _t.setVoice({'name': voice, 'locale': locale});
    await _t.setSpeechRate(rate);
    await _t.setVolume(volume);
    _done = Completer<void>();
    final d = _done!;
    await _t.speak(text);
    return d.future;
  }

  @override
  Future<void> stop() async {
    await _t.stop();
    _finish();
  }
}
