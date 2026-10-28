// TtsBridge: engine choice (ttsEngine / useGlobalTtsEngine / the book's engine), multi-role fragments, speak -> onDone, background
// music following the listening state, lock-screen commands.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/background_music_manager.dart';
import 'package:newread/data/tts.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/models/httptts.dart';
import 'package:newread/pages/read/pages/audio_view.dart';
import 'package:newread/pages/read/read_aloud.dart';
import 'package:newread/pages/read/reader_speaker.dart';
import 'package:newread/pages/read/tts_bridge.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/model/line.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/read.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/audio/my_audio_player.dart';
import 'package:newread/util/audio/tts_controller.dart';

import '../support/env.dart';

class _FakeAudio implements AudioBackend {
  static final List<String> log = [];
  bool _playing = false;
  @override
  Future<void> setSource(String pathOrUrl) async => log.add('src ${pathOrUrl.split(RegExp(r'[\\/]')).last}');
  @override
  Future<void> play() async {
    _playing = true;
    log.add('play');
  }

  @override
  Future<void> pause() async {
    _playing = false;
    log.add('pause');
  }

  @override
  Future<void> stop() async {
    _playing = false;
    log.add('stop');
  }

  @override
  Future<void> setVolume(double v) async => log.add('vol ${v.toStringAsFixed(1)}');
  @override
  Future<void> setSpeed(double v) async {}
  @override
  Future<void> setLoop(bool loop) async => log.add('loop $loop');
  @override
  bool get playing => _playing;
  @override
  Future<void> get completed async {}
  @override
  Future<void> dispose() async {}
}

class _FakeMedia extends ListenMediaBackend {
  final List<String> updates = [];
  @override
  Future<void> update({required String title, required String album, required String artUri, required bool playing, required bool active}) async =>
      updates.add('$album/$title playing=$playing active=$active');
}

void main() {
  late TestDevice device;
  setUp(() async {
    device = await newDevice();
    TtsBridge.reset();
    await TTSData.load(force: true);
    await BackgroundMusicManager.load(force: true);
  });
  tearDown(TtsBridge.reset);

  test('chapter lyric key of the original (book_<url>_<index>_chapter_lyric)', () async {
    expect(AudioLyrics.key('http://x/b', 3), 'book_http://x/b_3_chapter_lyric');
    await AudioLyrics.write('http://x/b', 3, '[00:01.00]你好');
    expect(await AudioLyrics.read('http://x/b', 3), '[00:01.00]你好');
    expect(await AudioLyrics.read('http://x/b', 4), '');
  });

  test('engine choice: default, ttsEngine, book engine when 引擎一致 is off', () async {
    expect(TtsBridge.engineFor('b1').id, TTSData.defaultEngine.id);
    final e = await Tts.add(HttpTts(name: '在线朗读', tp: 0));
    await Storage.setString('ttsEngine', e.id);
    expect(TtsBridge.engineFor('b1').name, '在线朗读');
    await Tts.saveForBook('b1', HttpTts(name: '本书引擎', tp: 0));
    expect(TtsBridge.engineFor('b1').name, '在线朗读'); // 引擎一致 defaults to on
    await Storage.setBool('useGlobalTtsEngine', false);
    expect(TtsBridge.engineFor('b1').name, '本书引擎');
    expect(TtsBridge.engineFor('b2').name, '在线朗读');

    TtsBridge.install(media: _FakeMedia());
    final s = ReaderSpeaker.create(bookUrl: 'b1');
    expect(s, isA<TtsBridgeSpeaker>());
    expect(s.engineName, '本书引擎');
  });

  test('speak runs the fragments and reports done; multi-role uses narration / dialogue engines', () async {
    final narr = await Tts.add(HttpTts(name: '旁白', tp: 0));
    final male = await Tts.add(HttpTts(name: '男声', tp: 0));
    final female = await Tts.add(HttpTts(name: '女声', tp: 0));
    final multi = await Tts.add(HttpTts(
      name: '多角色',
      tp: TtsKind.multiRole.tp,
      narrationEngineId: narr.id,
      narrationVoiceId: 'n',
      defaultMaleDialogueEngineId: male.id,
      defaultMaleDialogueVoiceId: 'm',
      defaultFemaleDialogueEngineId: female.id,
      defaultFemaleDialogueVoiceId: 'f',
    ));
    final spoken = <String>[];
    TtsBridge.speakWith = (e, t, {int speed = 10, String voice = ''}) async => spoken.add('${e.name}:$voice:$t:$speed');
    TtsBridge.stopAll = () async {};
    final s = TtsBridgeSpeaker(fixedEngine: multi);
    var done = 0;
    s.onDone = () => done++;

    // without a role analysis the narration engine reads everything
    await s.speak('他说：“走吧。”');
    await pumpEventQueue();
    expect(spoken, ['旁白:n:他说：“走吧。”:10']);
    expect(done, 1);

    TtsBridge.roleSplitter = (book, text) async => [
          AiZLine(str: '他说：', ispb: true),
          AiZLine(str: '“走吧。”', name: '张三', gender: Gender.male.value),
          AiZLine(str: '“好。”', name: '李四', gender: Gender.female.value),
        ];
    spoken.clear();
    await s.setRate(1.5);
    await s.speak('他说：“走吧。”“好。”');
    await pumpEventQueue();
    expect(spoken, ['旁白:n:他说：:15', '男声:m:“走吧。”:15', '女声:f:“好。”:15']);
    expect(done, 2);

    // stop cancels the rest and no done is reported
    final gate = Completer<void>();
    TtsBridge.speakWith = (e, t, {int speed = 10, String voice = ''}) => gate.future;
    await s.speak('x');
    await s.stop();
    gate.complete();
    await pumpEventQueue();
    expect(done, 2);
  });

  test('background music plays while listening, media session gets the state and sends commands', () async {
    AudioBackend.create = _FakeAudio.new;
    addTearDown(() => AudioBackend.create = JustAudioBackend.new);
    _FakeAudio.log.clear();
    final src = File('${device.dir.path}/rain.mp3')..writeAsBytesSync([1, 2, 3]);
    final m = await BackgroundMusicManager.add(src, name: '雨声');
    await BackgroundMusicManager.select(m.id);
    await BackgroundMusicManager.setVolume(0.5);

    final media = _FakeMedia();
    TtsBridge.install(media: media);
    final speaker = _Silent();
    final c = ReadAloudController(
      speaker: speaker,
      chapterAt: (i) async => ReadChapter(BookChapter(index: i), '第$i章', ChapterContent.fromText('一段。\n二段。')),
      chapterCount: () => 3,
    )..bookName = '测试书';
    await c.start(0);
    await pumpEventQueue();
    expect(ReaderWakelock.keepAwake, isTrue);
    expect(_FakeAudio.log, containsAllInOrder(['src ${m.path}', 'loop true', 'vol 0.5', 'play']));
    expect(media.updates.last, '测试书/第0章 playing=true active=true');

    media.onCommand!('pause');
    await pumpEventQueue();
    expect(c.paused, isTrue);
    expect(_FakeAudio.log.last, 'pause');
    expect(ReaderWakelock.keepAwake, isFalse);
    expect(media.updates.last, '测试书/第0章 playing=false active=true');
    media.onCommand!('play');
    await pumpEventQueue();
    expect(c.paused, isFalse);
    expect(_FakeAudio.log.last, 'play');
    media.onCommand!('stop');
    await pumpEventQueue();
    expect(c.active, isFalse);
    expect(media.updates.last, contains('active=false'));
    c.dispose();
  });
}

class _Silent extends ReaderSpeaker {
  @override
  String get engineName => 'x';
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<List<SpeakerVoice>> voices() async => const [];
  @override
  Future<void> setVoice(SpeakerVoice voice) async {}
  @override
  Future<void> dispose() async {}
}
