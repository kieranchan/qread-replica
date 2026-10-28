// pages/read/tts_bridge.dart — connects the reader's listening (ReadAloudController / ReaderSpeaker) with the TTS module (util/audio, data/tts):
//   * [TtsBridgeSpeaker]: speaks a paragraph with the engine the original would pick — the book's own engine when 引擎一致
//     (`useGlobalTtsEngine`, default true) is off and the book has one (`TTSData.forBook`), else the default engine `ttsEngine` (empty =
//     系统默认); HTTP engines through `TtsController.speak`; the 多角色 engine splits a paragraph with [TtsBridge.roleSplitter] (the AI role
//     analysis) and reads narration / male / female lines with the engine's narration and default dialogue engines and voices;
//   * [ListenBackgroundMusic]: 选择背景音乐 / 背景音乐音量 (BackgroundMusicManager + a looping player) while listening plays;
//   * [ListenMediaSession]: lock-screen / Control Center controls and background playback through audio_service (the original's
//     `AudioPlayerHandler` in util/audio/audio_player_handler.dart).
// `TtsBridge.install()` is called once by the app (lead wiring).
import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';

import '../../ai/read.dart';
import '../../data/background_music_manager.dart';
import '../../data/tts.dart';
import '../../models/httptts.dart';
import '../../read/model/line.dart';
import '../../storage/storage.dart';
import '../../util/audio/my_audio_player.dart';
import '../../util/audio/tts_controller.dart';
import 'read_aloud.dart';
import 'reader_speaker.dart';

abstract class TtsBridge {
  static bool _installed = false;

  /// Splits a paragraph into spoken fragments with speaker and gender (the AI role analysis, `AiZLine`); null = not available, the
  /// paragraph is read by the narration engine. Set by the AI wiring.
  static Future<List<AiZLine>?> Function(String bookUrl, String text)? roleSplitter;

  /// Speaks with a TTS engine (tests replace it). Completes when the audio finished.
  static Future<void> Function(HttpTts engine, String text, {int speed, String voice}) speakWith = TtsController.speak;
  static Future<void> Function() stopAll = TtsController.stop;

  static void install({ListenMediaBackend? media}) {
    ReaderSpeaker.bookFactory = (bookUrl) => TtsBridgeSpeaker(bookUrl: bookUrl);
    roleSplitter ??= aiRoles;
    if (_installed) return;
    _installed = true;
    ReadAloudController.observers.add(ListenBackgroundMusic.instance);
    ReadAloudController.observers.add(ListenMediaSession(media ?? AudioServiceBackend()));
    unawaited(TTSData.load().then((_) {}, onError: (_) {}));
  }

  /// Forgets the installation (tests).
  static void reset() {
    _installed = false;
    ReaderSpeaker.bookFactory = null;
    ReadAloudController.observers.removeWhere((o) => o is ListenBackgroundMusic || o is ListenMediaSession);
    ListenMediaSession.backend = null;
    roleSplitter = null;
    speakWith = TtsController.speak;
    stopAll = TtsController.stop;
  }

  /// The AI role analysis of the AI module (`AiRead.rolesFor`: cached per paragraph, the 多角色 model, else the quote heuristic).
  static Future<List<AiZLine>?> aiRoles(String bookUrl, String text) async {
    final key = '$bookUrl#${md5.convert(utf8.encode(text))}';
    final lines = await AiRead.rolesFor(key, {'0': text});
    return [for (final r in lines) AiZLine(id: r.id, str: r.str, ispb: r.ispb, name: r.name, gender: r.gender, personality: r.personality)];
  }

  /// The engine for [bookUrl] (see the file comment).
  static HttpTts engineFor(String bookUrl) {
    final globalText = Storage.getString('useGlobalTtsEngine');
    final global = globalText.isEmpty ? true : Storage.getBool('useGlobalTtsEngine', true);
    if (!global && bookUrl.isNotEmpty) {
      final own = TTSData.forBook(bookUrl);
      if (own != null) return own;
    }
    final id = Storage.getString('ttsEngine');
    if (id.isEmpty) return TTSData.defaultEngine;
    return TTSData.byId(id) ?? TTSData.defaultEngine;
  }
}

/// A [ReaderSpeaker] over the TTS module. `speak` returns once speaking started; [onDone] fires when the paragraph is finished.
class TtsBridgeSpeaker extends ReaderSpeaker {
  final String bookUrl;

  /// A fixed engine (tests, previews); null = [TtsBridge.engineFor] at first use.
  final HttpTts? fixedEngine;
  HttpTts? _engine;
  String _voice = '';
  double _rate = 1;
  String _last = '';
  int _gen = 0;

  TtsBridgeSpeaker({this.bookUrl = '', this.fixedEngine});

  HttpTts get engine => fixedEngine ?? (_engine ??= TtsBridge.engineFor(bookUrl));

  @override
  String get engineName => engine.name;

  /// The app's speed scale (10 = normal) used by HTTP engines.
  int get speed => (_rate * 10).round().clamp(1, 30);

  /// Fragments of [text] with the engine and voice each one is read with.
  Future<List<(HttpTts, String, String)>> plan(String text) async {
    final e = engine;
    if (TtsKind.of(e) != TtsKind.multiRole || TtsController.isSystem(e)) return [(e, text, _voice)];
    final narr = TTSData.byId(e.narrationEngineId) ?? TTSData.defaultEngine;
    final split = TtsBridge.roleSplitter;
    final parts = split == null ? null : await split(bookUrl, text);
    if (parts == null || parts.isEmpty) return [(narr, text, e.narrationVoiceId)];
    final male = TTSData.byId(e.defaultMaleDialogueEngineId) ?? narr;
    final female = TTSData.byId(e.defaultFemaleDialogueEngineId) ?? narr;
    return [
      for (final z in parts)
        if (z.str.trim().isNotEmpty)
          z.ispb || z.name.isEmpty
              ? (narr, z.str, e.narrationVoiceId)
              : z.genderEnum == Gender.female
                  ? (female, z.str, e.defaultFemaleDialogueVoiceId)
                  : (male, z.str, e.defaultMaleDialogueVoiceId),
    ];
  }

  @override
  Future<void> speak(String text) async {
    final g = ++_gen;
    _last = text;
    unawaited(() async {
      try {
        for (final (eng, str, voice) in await plan(text)) {
          if (g != _gen) return;
          await TtsBridge.speakWith(eng, str, speed: speed, voice: voice);
        }
        if (g == _gen) onDone?.call();
      } catch (e) {
        if (g == _gen) onError?.call('$e');
      }
    }());
  }

  @override
  Future<void> pause() async {
    _gen++;
    await TtsBridge.stopAll();
  }

  /// Engines cannot continue mid-sentence: the paragraph starts again.
  @override
  Future<void> resume() async {
    if (_last.isNotEmpty) await speak(_last);
  }

  @override
  Future<void> stop() async {
    _gen++;
    await TtsBridge.stopAll();
  }

  @override
  Future<void> setRate(double rate) async => _rate = rate;

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<List<SpeakerVoice>> voices() async {
    if (!TtsController.isSystem(engine)) return const [];
    try {
      final v = await TtsController.system.voices();
      return [for (final x in v) SpeakerVoice(x.name, x.locale)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> setVoice(SpeakerVoice voice) async => _voice = voice.name;

  @override
  Future<void> dispose() => stop();
}

/// 背景音乐 of the listen page: the selected track loops at `backgroundMusicVolume` while listening plays.
class ListenBackgroundMusic implements ListenObserver {
  static final ListenBackgroundMusic instance = ListenBackgroundMusic();

  /// The player (tests replace the backend through `AudioBackend.create`).
  Myaudioplayer? _player;
  String? _playing;
  bool get isPlaying => _playing != null;
  String? get playingId => _playing;

  Myaudioplayer get _p => _player ??= Myaudioplayer();

  @override
  void listenChanged(ReadAloudController c) {
    unawaited(sync(c.active && !c.paused));
  }

  /// Starts / stops the music to match [on].
  Future<void> sync(bool on) async {
    final m = BackgroundMusicManager.selected;
    if (!on || m == null) {
      if (_playing != null) {
        _playing = null;
        try {
          await _p.pause();
        } catch (_) {}
      }
      return;
    }
    if (_playing == m.id) return;
    _playing = m.id;
    try {
      await _p.setFile(BackgroundMusicManager.filePath(m));
      await _p.setLoop(true);
      await _p.setVolume(BackgroundMusicManager.volume);
      await _p.play();
    } catch (_) {
      _playing = null;
    }
  }

  Future<void> setVolume(double v) async {
    await BackgroundMusicManager.setVolume(v);
    if (_playing != null) {
      try {
        await _p.setVolume(BackgroundMusicManager.volume);
      } catch (_) {}
    }
  }

  /// Selection changed: restart with the new track (or stop when cleared).
  Future<void> reselect(bool listening) async {
    _playing = null;
    try {
      await _p.stop();
    } catch (_) {}
    await sync(listening);
  }
}

/// The lock-screen session as the reader drives it.
abstract class ListenMediaBackend {
  /// Commands from the lock screen / headset.
  void Function(String command)? onCommand;

  Future<void> update({required String title, required String album, required String artUri, required bool playing, required bool active});
}

/// Mirrors the listening state into the system media session and forwards its buttons (play / pause / next / previous / stop).
class ListenMediaSession implements ListenObserver {
  /// The installed backend (the audio view uses it too); null before `TtsBridge.install()`.
  static ListenMediaBackend? backend;

  final ListenMediaBackend _backend;
  ReadAloudController? _c;
  (String, bool, bool)? _last;

  ListenMediaSession(ListenMediaBackend b) : _backend = b {
    backend = b;
    _bind();
  }

  void _bind() {
    final backend = _backend;
    backend.onCommand = (cmd) {
      final c = _c;
      if (c == null) return;
      switch (cmd) {
        case 'play':
          c.paused ? c.resume() : (c.active ? null : c.start(c.chapterIndex));
        case 'pause':
          c.pause();
        case 'next':
          c.nextSegment();
        case 'previous':
          c.prevSegment();
        case 'stop':
          c.stop();
      }
    };
  }

  @override
  void listenChanged(ReadAloudController c) {
    _c = c;
    final state = (c.chapterTitle, c.active, c.paused);
    if (state == _last) return;
    _last = state;
    _bind(); // the audio view may have taken the buttons
    unawaited(_backend.update(title: c.chapterTitle, album: c.bookName, artUri: c.coverUrl, playing: c.active && !c.paused, active: c.active)
        .catchError((_) {}));
  }
}

/// audio_service: started on first use (Info.plist has the background audio mode).
class AudioServiceBackend extends ListenMediaBackend {
  Future<_ReaderAudioHandler>? _handler;

  Future<_ReaderAudioHandler> _ensure() => _handler ??= AudioService.init(
        builder: () => _ReaderAudioHandler(this),
        config: const AudioServiceConfig(androidNotificationChannelName: '听书', androidNotificationOngoing: false),
      );

  @override
  Future<void> update({required String title, required String album, required String artUri, required bool playing, required bool active}) async {
    if (!active && _handler == null) return;
    final h = await _ensure();
    h.mediaItem.add(MediaItem(id: '$album/$title', title: title, album: album, artist: album, artUri: Uri.tryParse(artUri)));
    h.playbackState.add(PlaybackState(
      controls: [MediaControl.skipToPrevious, playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext, MediaControl.stop],
      systemActions: const {MediaAction.skipToNext, MediaAction.skipToPrevious},
      processingState: active ? AudioProcessingState.ready : AudioProcessingState.idle,
      playing: playing,
    ));
  }
}

class _ReaderAudioHandler extends BaseAudioHandler {
  final AudioServiceBackend owner;
  _ReaderAudioHandler(this.owner);

  void _cmd(String c) => owner.onCommand?.call(c);

  @override
  Future<void> play() async => _cmd('play');
  @override
  Future<void> pause() async => _cmd('pause');
  @override
  Future<void> stop() async => _cmd('stop');
  @override
  Future<void> skipToNext() async => _cmd('next');
  @override
  Future<void> skipToPrevious() async => _cmd('previous');
}
