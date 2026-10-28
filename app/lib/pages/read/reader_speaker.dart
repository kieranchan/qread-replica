// pages/read/reader_speaker.dart — the read-aloud engine as the reader sees it.
//
// The original drives `TtsController` (`_NovelViewState._tts` 0x1b0, util/audio/tts_audio_controller.dart, owned by the TTS area) which
// switches between the system voice (flutter_tts), HTTP TTS engines and the multi-role AI engine. The reader only needs "speak this
// paragraph, tell me when done", so it talks to [ReaderSpeaker]; `TtsBridge.install()` (tts_bridge.dart) points [bookFactory] at the
// TTS module (engine chosen by `ttsEngine` / `useGlobalTtsEngine` / the book's own engine); without it the system voice is used.
import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

class SpeakerVoice {
  final String name;
  final String locale;
  const SpeakerVoice(this.name, this.locale);

  @override
  bool operator ==(Object other) => other is SpeakerVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

abstract class ReaderSpeaker {
  /// Overrides every other choice (tests).
  static ReaderSpeaker Function()? factory;

  /// The engine for a book (set by `TtsBridge.install()`).
  static ReaderSpeaker Function(String bookUrl)? bookFactory;

  static ReaderSpeaker create({String bookUrl = ''}) => factory?.call() ?? bookFactory?.call(bookUrl) ?? FlutterTtsSpeaker();

  /// Called when the text given to [speak] has been spoken completely.
  void Function()? onDone;

  /// Called with an error text; the controller stops.
  void Function(String message)? onError;

  /// Starts speaking [text]; completes when speaking has started.
  Future<void> speak(String text);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  /// Speech rate, 0.1..3 where 1 is normal.
  Future<void> setRate(double rate);
  Future<void> setPitch(double pitch);
  Future<List<SpeakerVoice>> voices();
  Future<void> setVoice(SpeakerVoice voice);

  /// Name shown as "朗读引擎：".
  String get engineName;

  Future<void> dispose();
}

/// The system voice (flutter_tts). flutter_tts has no real resume on every platform, so [resume] speaks the paragraph again.
class FlutterTtsSpeaker extends ReaderSpeaker {
  final FlutterTts _tts = FlutterTts();
  String _last = '';
  bool _init = false;

  Future<void> _ensure() async {
    if (_init) return;
    _init = true;
    _tts.setCompletionHandler(() => onDone?.call());
    _tts.setErrorHandler((msg) => onError?.call('$msg'));
    try {
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {}
  }

  @override
  String get engineName => '系统默认';

  @override
  Future<void> speak(String text) async {
    await _ensure();
    _last = text;
    await _tts.speak(text);
  }

  @override
  Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (_) {
      await _tts.stop();
    }
  }

  @override
  Future<void> resume() async {
    if (_last.isNotEmpty) await speak(_last);
  }

  @override
  Future<void> stop() => _tts.stop();

  /// flutter_tts uses 0..1 with 0.5 as normal on iOS/Android.
  @override
  Future<void> setRate(double rate) => _tts.setSpeechRate((rate / 2).clamp(0.05, 1.0));

  @override
  Future<void> setPitch(double pitch) => _tts.setPitch(pitch.clamp(0.5, 2.0));

  @override
  Future<List<SpeakerVoice>> voices() async {
    try {
      final v = await _tts.getVoices;
      if (v is! List) return const [];
      return [
        for (final e in v)
          if (e is Map) SpeakerVoice('${e['name'] ?? ''}', '${e['locale'] ?? ''}'),
      ].where((e) => e.locale.toLowerCase().startsWith('zh')).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> setVoice(SpeakerVoice voice) => _tts.setVoice({'name': voice.name, 'locale': voice.locale});

  @override
  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
