// util/audio/my_audio_player.dart — `Myaudioplayer` (original util/audio/MyAudioPlayer.dart): the small player the settings pages use
// for previews (background music, TTS 试听) and the TTS controller uses for HTTP engines. It talks to an [AudioBackend] so tests run
// on the host without the just_audio plugin ([AudioBackend.create] is replaceable).
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;

/// What a player backend must do.
abstract class AudioBackend {
  /// Factory used by [Myaudioplayer]; tests install a fake.
  static AudioBackend Function() create = JustAudioBackend.new;

  Future<void> setSource(String pathOrUrl);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double v);
  Future<void> setSpeed(double v);
  Future<void> setLoop(bool loop);
  bool get playing;

  /// Completes when the current source finished playing (or was stopped).
  Future<void> get completed;
  Future<void> dispose();
}

class JustAudioBackend implements AudioBackend {
  final ja.AudioPlayer _p = ja.AudioPlayer();

  @override
  Future<void> setSource(String pathOrUrl) async {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      await _p.setUrl(pathOrUrl);
    } else {
      await _p.setFilePath(pathOrUrl);
    }
  }

  @override
  Future<void> play() async {
    // just_audio's play() completes when playback stops; do not await it
    _p.play();
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> stop() => _p.stop();

  @override
  Future<void> setVolume(double v) => _p.setVolume(v);

  @override
  Future<void> setSpeed(double v) => _p.setSpeed(v);

  @override
  Future<void> setLoop(bool loop) => _p.setLoopMode(loop ? ja.LoopMode.one : ja.LoopMode.off);

  @override
  bool get playing => _p.playing;

  @override
  Future<void> get completed => _p.playerStateStream
      .firstWhere((s) => s.processingState == ja.ProcessingState.completed || s.processingState == ja.ProcessingState.idle)
      .then((_) {});

  @override
  Future<void> dispose() => _p.dispose();
}

/// The app's player: a source (file / url / bytes), play / pause / stop, volume, speed, loop.
class Myaudioplayer {
  final AudioBackend _b = AudioBackend.create();
  String? source;

  Future<void> setFile(String path) async {
    source = path;
    await _b.setSource(path);
  }

  /// Writes [bytes] to [dir]/[name] and plays from there (the original's `_tts_play.mp3` / `bdtts_clone_preview.wav`).
  Future<void> setBytes(Uint8List bytes, Directory dir, String name) async {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes, flush: true);
    await setFile(f.path);
  }

  Future<void> play() => _b.play();
  Future<void> pause() => _b.pause();
  Future<void> stop() => _b.stop();
  Future<void> setVolume(double v) => _b.setVolume(v);
  Future<void> setSpeed(double v) => _b.setSpeed(v);
  Future<void> setLoop(bool loop) => _b.setLoop(loop);
  bool get playing => _b.playing;
  Future<void> get completed => _b.completed;
  Future<void> dispose() => _b.dispose();
}
