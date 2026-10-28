// 本地引擎 (sherpa-onnx offline models): model package import / validation / registry with tiny fake model folders, the engine
// config, WAV in/out, down.json parsing, the worker isolate protocol and watchdogs with a fake synthesizer (no native library),
// engine selection in the TTS dispatcher and the original member gate.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/common/common.dart';
import 'package:newread/data/tts.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/httptts.dart';
import 'package:newread/models/userinfo.dart';
import 'package:newread/pages/tts/local/local_engines.dart';
import 'package:newread/pages/tts/tts_setting.dart';
import 'package:newread/theme/widgets.dart';
import 'package:newread/util/audio/my_audio_player.dart';
import 'package:newread/util/audio/local/local_tts_downloads.dart';
import 'package:newread/util/audio/local/local_tts_files.dart';
import 'package:newread/util/audio/local/local_tts_manager.dart';
import 'package:newread/util/audio/local/local_tts_worker.dart';
import 'package:newread/util/audio/tts_controller.dart';
import 'package:newread/util/audio/tts_page.dart';
import 'package:newread/util/toast.dart';
import 'package:path/path.dart' as p;

import '../support/env.dart';

// ---------------------------------------------------------------- fake engine (runs inside the worker isolate)

/// Encodes what it was asked in the audio: sample rate = 16000 + threads (or the reference rate for clones), sample value =
/// sid / 100 (or refText length / 100), 10 samples per character. `hang` sleeps without progress, `boom` throws.
class FakeSynth implements LocalSynthesizer {
  final Map<String, String> config;
  final int threads;
  FakeSynth(this.config, this.threads);

  @override
  LocalGenerated generate({
    required String text,
    required int sid,
    Float32List? referenceAudio,
    int referenceSampleRate = 0,
    String referenceText = '',
    int numSteps = 5,
    int Function(Float32List samples, double progress)? onProgress,
  }) {
    if (text.contains('boom')) throw StateError('boom');
    if (text.contains('hang')) sleep(const Duration(milliseconds: 1500));
    onProgress?.call(Float32List(4), 0.5);
    final clone = config['engine'] == 'zipvoice';
    final v = clone ? referenceText.length / 100 : sid / 100;
    return LocalGenerated(Float32List.fromList(List.filled(text.length * 10, v)), clone ? referenceSampleRate + numSteps : 16000 + threads);
  }

  @override
  void free() {}
}

LocalSynthesizer fakeFactory(Map<String, String> config, int threads) => FakeSynth(config, threads);

// ---------------------------------------------------------------- fixtures

ArchiveFile _f(String name, [String text = 'x']) => ArchiveFile.bytes(name, utf8.encode(text));

/// A vits package with `tts.json` (2 voices) wrapped in a top folder, as a zip.
List<int> vitsZip({String name = 'vits-zh', String top = 'pkg', bool tokens = true, Map<String, dynamic>? manifest}) {
  final a = Archive()
    ..add(_f('$top/tts.json', jsonEncode(manifest ??
        {
          'name': name,
          'type': '1',
          'engine': 'vits',
          'voices': [
            {'id': 0, 'name': '女声一', 'lang': 'zh', 'gender': 'female'},
            {'id': '2', 'name': 'Bob', 'lang': 'en', 'gender': 'male'},
          ],
        })))
    ..add(_f('$top/model.onnx'))
    ..add(_f('$top/lexicon.txt'))
    ..add(_f('$top/rule.fst'))
    ..add(_f('$top/dict/jieba.dict.utf8'));
  if (tokens) a.add(_f('$top/tokens.txt'));
  return ZipEncoder().encode(a);
}

File writeTo(Directory d, String name, List<int> bytes) => File(p.join(d.path, name))..writeAsBytesSync(bytes);

String wavUri(Float32List samples, int rate) => 'data:audio/wav;base64,${base64Encode(LocalTtsFiles.wavBytes(samples, rate))}';

Future<void> signIn({required bool vip}) => UserSession.apply(Userinfo(
    username: 'u', vip: vip ? '2030-01-01' : '', tockenid: 't', email: 'e@x.io', nickname: 'u', avatarUrl: '', isvip: vip));

/// Serves files from memory to Dio (widget tests: flutter_test answers every real HTTP request with 400).
class MemoryAdapter implements HttpClientAdapter {
  final Map<String, List<int>> files;
  final List<String> seen = [];
  MemoryAdapter(this.files);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(o.uri.path);
    final b = files[o.uri.path];
    if (b == null) return ResponseBody.fromString('not found', 404);
    return ResponseBody.fromBytes(Uint8List.fromList(b), 200, headers: {
      Headers.contentLengthHeader: ['${b.length}'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// A silent player (no just_audio on the host).
class SilentAudio implements AudioBackend {
  final List<String> played = [];
  String _src = '';
  @override
  Future<void> setSource(String pathOrUrl) async => _src = pathOrUrl;
  @override
  Future<void> play() async => played.add(_src);
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setSpeed(double v) async {}
  @override
  Future<void> setLoop(bool loop) async {}
  @override
  bool get playing => false;
  @override
  Future<void> get completed async {}
  @override
  Future<void> dispose() async {}
}

/// Waits until a request is in flight at the worker.
Future<void> waitPending() async {
  for (var i = 0; i < 200 && LocalTtsManager.pendingCount == 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(LocalTtsManager.pendingCount, greaterThan(0));
}

HttpTts pageEngine(String page) => HttpTts(id: 'e', name: 'e', html: {'page': page});

/// A recording engine for the dispatcher tests.
class RecordingEngine implements LocalTtsEngine {
  final List<String> calls = [];
  @override
  Future<Uint8List> synthesize(String model, int voiceId, String text, {String referenceAudioDataUri = '', String referenceText = ''}) async {
    calls.add('$model|$voiceId|$text|$referenceAudioDataUri|$referenceText');
    return LocalTtsFiles.wavBytes(Float32List(8), 16000);
  }
}

void main() {
  late TestDevice dev;
  late Directory scratch;
  final logs = <String>[];

  setUp(() async {
    dev = await newDevice();
    scratch = Directory.systemTemp.createTempSync('local_tts_src_');
    logs.clear();
    await LocalTtsManager.reset();
    LocalTtsManager.synthesizerFactory = fakeFactory;
    LocalTtsManager.log = logs.add;
    LocalTtsManager.watchdogTimeout = const Duration(seconds: 180);
    LocalTtsManager.destroyTimeout = const Duration(seconds: 10);
    LocalTtsManager.backgroundIdle = const Duration(seconds: 20);
    LocalTtsManager.memoryCooldown = const Duration(seconds: 30);
  });

  tearDown(() async {
    await LocalTtsManager.reset();
    LocalTtsEngine.instance = const LocalTtsEngineDefault();
    dev.delete();
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('model packages', () {
    test('zip import: unpack, validate, registry, duplicate refused, reload, delete keeps engines', () async {
      final zip = writeTo(scratch, 'vits.zip', vitsZip());
      final r = await LocalTtsManager.importZip(zip.path);
      expect(r.model.name, 'vits-zh');
      expect(r.model.engine, 'vits');
      expect(r.model.type, 1);
      expect(r.model.voices.map((v) => '${v.id}:${v.name}:${v.gender}'), ['0:女声一:female', '2:Bob:male']);
      expect(r.bytes, greaterThan(0));
      final dir = LocalTtsManager.dirOf('vits-zh');
      expect(File(p.join(dir.path, 'model.onnx')).existsSync(), isTrue);
      expect(Directory(p.join(LocalTtsManager.root.path, '.importing')).existsSync(), isFalse);
      final reg = jsonDecode(File(p.join(LocalTtsManager.root.path, 'registry.json')).readAsStringSync()) as List;
      expect(reg.single['name'], 'vits-zh');
      expect(reg.single.keys, containsAll(['name', 'type', 'voices', 'engine', 'importTime', 'numThreads', 'numSteps']));

      await expectLater(LocalTtsManager.importZip(zip.path), throwsA(predicate((e) => '$e' == '模型「vits-zh」已导入，请勿重复操作')));
      expect(logs, contains('本地TTS导入失败：模型「vits-zh」已导入，请勿重复操作'));

      await LocalTtsManager.reset();
      final again = await LocalTtsManager.load();
      expect(again.single.name, 'vits-zh');
      await LocalTtsManager.setNumThreads('vits-zh', 3);
      await LocalTtsManager.load(force: true);
      expect(LocalTtsManager.byName('vits-zh')!.numThreads, 3);

      await LocalTtsManager.delete('vits-zh');
      expect(LocalTtsManager.models, isEmpty);
      expect(dir.existsSync(), isFalse);
    });

    test('validation messages of the original; tts.json must be an object', () async {
      Future<String> err(List<int> bytes, [String name = 'p.zip']) async {
        try {
          await LocalTtsManager.importZip(writeTo(scratch, name, bytes).path);
          return 'ok';
        } catch (e) {
          return '$e';
        }
      }

      expect(await err(vitsZip(tokens: false)), '模型包缺少 tokens.txt');
      expect(await err(ZipEncoder().encode(Archive()..add(_f('tts.json', '[1]'))..add(_f('tokens.txt')))), '模型不正确');
      expect(await err(ZipEncoder().encode(Archive()..add(_f('readme.txt')))), '模型不正确');
      expect(await err(utf8.encode('not a zip')), '模型不正确');
      expect(
          await err(ZipEncoder().encode(Archive()
            ..add(_f('tts.json', jsonEncode({'name': 'z', 'engine': 'zipvoice'})))
            ..add(_f('tokens.txt'))
            ..add(_f('lexicon.txt'))
            ..add(_f('encoder.onnx'))
            ..add(_f('decoder.onnx')))),
          '模型包缺少 vocoder（vocos .onnx）');
      expect(
          await err(ZipEncoder().encode(Archive()
            ..add(_f('tts.json', jsonEncode({'name': 'k', 'engine': 'kokoro'})))
            ..add(_f('tokens.txt'))
            ..add(_f('model.onnx'))
            ..add(_f('voices.bin')))),
          '模型包缺少 espeak-ng-data');
      expect(await err(vitsZip(manifest: {'name': '../evil', 'engine': 'vits'})), '模型不正确');
      expect(LocalTtsManager.models, isEmpty);
    });

    test('release tar.bz2 without tts.json: engine and voices inferred; a shared vocoder completes a zipvoice package', () async {
      final kokoro = Archive()
        ..add(_f('kokoro-en-v0_19/model.onnx'))
        ..add(ArchiveFile.bytes('kokoro-en-v0_19/voices.bin', Uint8List(LocalTtsFiles.kokoroVoiceBytes * 11)))
        ..add(_f('kokoro-en-v0_19/tokens.txt'))
        ..add(_f('kokoro-en-v0_19/lexicon-zh.txt'))
        ..add(_f('kokoro-en-v0_19/espeak-ng-data/phontab'));
      final tbz = writeTo(scratch, 'kokoro-en-v0_19.tar.bz2', BZip2Encoder().encode(TarEncoder().encode(kokoro)));
      final k = (await LocalTtsManager.importZip(tbz.path)).model;
      expect(k.name, 'kokoro-en-v0_19');
      expect(k.engine, 'kokoro');
      expect(k.voices.length, 11);
      expect((k.voices[10].name, k.voices[10].lang, k.voices[10].gender), ('bm_lewis', 'en-GB', 'male'));
      final big = Directory(p.join(scratch.path, 'kokoro-multi-lang-v1_0'))..createSync();
      writeTo(big, 'model.onnx', [1]);
      writeTo(big, 'voices.bin', Uint8List(LocalTtsFiles.kokoroVoiceBytes * 53));
      final m53 = LocalTtsModel.fromJson(LocalTtsFiles.inferManifest(big, 'kokoro-multi-lang-v1_0')!);
      expect(m53.voices.length, 53);
      expect((m53.voices[47].name, m53.voices[47].lang, m53.voices[47].gender), ('zf_xiaoxiao', 'zh', 'female'));
      expect((m53.voices[11].name, m53.voices[11].lang, m53.voices[11].gender), ('am_adam', 'en-US', 'male'));
      final vits = Directory(p.join(scratch.path, 'vits-zh-hf-fanchen-C'))..createSync();
      writeTo(vits, 'vits-zh-hf-fanchen-C.onnx', [1]);
      final fan = LocalTtsModel.fromJson(LocalTtsFiles.inferManifest(vits, 'vits-zh-hf-fanchen-C')!);
      expect((fan.engine, fan.voices.length, fan.voices.first.lang), ('vits', 187, 'zh'));
      expect(File(p.join(LocalTtsManager.dirOf(k.name).path, 'tts.json')).existsSync(), isTrue, reason: 'manifest written');
      final cfg = LocalTtsFiles.modelConfig(LocalTtsManager.dirOf(k.name), 'kokoro');
      expect(p.basename(cfg['voices']!), 'voices.bin');
      expect(p.basename(cfg['lexicon']!), 'lexicon-zh.txt');
      expect(p.basename(cfg['dataDir']!), 'espeak-ng-data');

      final zv = Archive()
        ..add(_f('sherpa-onnx-zipvoice-distill-zh-en-emilia/fm_decoder.onnx'))
        ..add(_f('sherpa-onnx-zipvoice-distill-zh-en-emilia/text_encoder.onnx'))
        ..add(_f('sherpa-onnx-zipvoice-distill-zh-en-emilia/tokens.txt'))
        ..add(_f('sherpa-onnx-zipvoice-distill-zh-en-emilia/lexicon.txt'));
      final zf = writeTo(scratch, 'zv.tar.bz2', BZip2Encoder().encode(TarEncoder().encode(zv)));
      await expectLater(LocalTtsManager.importZip(zf.path), throwsA(predicate((e) => '$e' == '模型包缺少 vocoder（vocos .onnx）')));
      final voc = writeTo(scratch, 'vocos_24khz.onnx', [1, 2, 3]);
      expect(await LocalTtsManager.importShared(voc.path), 'vocos_24khz.onnx');
      final z = (await LocalTtsManager.importZip(zf.path)).model;
      expect((z.engine, z.isClone, z.voices.length), ('zipvoice', true, 0));
      final zc = LocalTtsFiles.modelConfig(LocalTtsManager.dirOf(z.name), 'zipvoice', sharedDir: LocalTtsManager.sharedDir.path);
      expect(p.basename(zc['vocoder']!), 'vocos_24khz.onnx');
      expect(p.basename(zc['encoder']!), 'text_encoder.onnx');
      expect(p.basename(zc['decoder']!), 'fm_decoder.onnx');
    });

    test('engine config: vits files, rule FSTs, dict; missing files throw the original messages', () async {
      await LocalTtsManager.importZip(writeTo(scratch, 'v.zip', vitsZip()).path);
      final d = LocalTtsManager.dirOf('vits-zh');
      final c = LocalTtsFiles.modelConfig(d, 'vits');
      expect(p.basename(c['model']!), 'model.onnx');
      expect(p.basename(c['ruleFsts']!), 'rule.fst');
      expect(p.basename(c['dictDir']!), 'dict');
      expect(c['dataDir'], '');
      File(p.join(d.path, 'tokens.txt')).deleteSync();
      expect(() => LocalTtsFiles.modelConfig(d, 'vits'), throwsA(predicate((e) => '$e' == '模型文件不存在（tokens.txt）')));
      expect(() => LocalTtsFiles.modelConfig(d, 'matcha'), throwsA(predicate((e) => '$e' == '模型文件不存在（vocoder .onnx）')));
    });

    test('WAV out (PCM-16 mono) and reference WAV in', () {
      final wav = LocalTtsFiles.wavBytes(Float32List.fromList([0, 0.5, -1, 2]), 22050);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, 44 + 8);
      final back = LocalTtsFiles.readWav(wav);
      expect(back.sampleRate, 22050);
      expect(back.samples.length, 4);
      expect(back.samples[1], closeTo(0.5, 0.001));
      expect(back.samples[3], closeTo(1, 0.001), reason: 'clamped');
      expect(() => LocalTtsFiles.readWav(Uint8List.fromList(utf8.encode('ID3 not a wav file'))),
          throwsA(predicate((e) => '$e' == '参考音频仅支持 WAV 格式')));
      final float = Uint8List.fromList(wav)..buffer.asByteData().setUint16(20, 3, Endian.little);
      expect(() => LocalTtsFiles.readWav(float), throwsA(predicate((e) => '$e' == '参考音频仅支持 PCM 16 位 WAV')));
      expect(LocalTtsFiles.dataUriBytes('data:audio/wav;base64,AQID'), [1, 2, 3]);
      expect(LocalTtsFiles.dataUriBytes(''), isEmpty);
    });

    test('default thread count by platform (0x200da8)', () {
      expect(LocalTtsManager.defaultThreads(ios: true, ramMb: 4000), 1);
      expect(LocalTtsManager.defaultThreads(ios: true, ramMb: 6000), 2);
      expect(LocalTtsManager.defaultThreads(ios: true, ramMb: 8000), 3);
      expect(LocalTtsManager.defaultThreads(ios: false, ramMb: 0, cores: 16), 8);
      expect(LocalTtsManager.defaultThreads(ios: false, ramMb: 0, cores: 4), 4);
      expect(LocalTtsManager.defaultThreads(ios: false, ramMb: 6000, cores: 16), 4);
    });
  });

  group('down.json', () {
    test('parser of the original: non-empty values as text, order kept', () {
      final m = LocalTtsDownloads.parse(jsonDecode('{"b": "https://x/b.tar.bz2", "a": "", "n": null, "c": 5, "d": "https://x/page"}') as Map);
      expect(m.keys, ['b', 'c', 'd']);
      expect(m['c'], '5');
      expect(LocalTtsDownloads.isDirect('https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-melo-tts-zh_en.tar.bz2'), isTrue);
      expect(LocalTtsDownloads.isDirect('https://x/vocoder-models/vocos-22khz-univ.onnx'), isTrue);
      expect(LocalTtsDownloads.isDirect('https://x/model.zip?dl=1'), isTrue);
      expect(LocalTtsDownloads.isDirect('https://pan.example.com/s/abc'), isFalse);
      expect(LocalTtsDownloads.fileName('https://x/a%20b.zip'), 'a b.zip');
    });

    test('server/deploy/down.json: the original format, official k2-fsa release files only, each one the app can import', () {
      final raw = jsonDecode(File(p.join('..', 'server', 'deploy', 'down.json')).readAsStringSync()) as Map;
      final list = LocalTtsDownloads.parse(raw);
      expect(list.length, raw.length);
      expect(list.length, greaterThanOrEqualTo(5));
      for (final url in list.values) {
        expect(url, startsWith('https://github.com/k2-fsa/sherpa-onnx/releases/download/'));
        expect(url, isNot(contains('qread')));
        expect(LocalTtsDownloads.isDirect(url), isTrue, reason: url);
      }
      expect(list.values.where(LocalTtsFiles.isVocoderFile).length, 2, reason: 'matcha / zipvoice vocoders');
    });

    test('fetched from the own server (Common.apiBase + static/down.json), downloaded with progress', () async {
      // the widget tests of this file install flutter_test's HTTP mock (400 for everything): use real sockets here
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String>[];
      var reply = '{"模型A": "http://127.0.0.1:${server.port}/files/m.zip"}';
      server.listen((r) async {
        seen.add(r.uri.path);
        if (r.uri.path == '/static/down.json') {
          r.response.write(reply);
        } else {
          r.response.headers.contentLength = 4000;
          r.response.add(List.filled(4000, 7));
        }
        await r.response.close();
      });
      final oldBase = Common.apiBase;
      Common.apiBase = 'http://127.0.0.1:${server.port}/';
      addTearDown(() async {
        Common.apiBase = oldBase;
        LocalTtsDownloads.dio = null;
        await server.close(force: true);
      });
      final list = await LocalTtsDownloads.fetchList();
      expect(list!.keys, ['模型A']);
      final progress = <int>[];
      final f = await LocalTtsDownloads.download(list['模型A']!, onProgress: (got, total) => progress.add(got));
      expect(f.lengthSync(), 4000);
      expect(p.basename(f.path), 'm.zip');
      expect(progress.last, 4000);
      expect(seen, ['/static/down.json', '/files/m.zip']);
      reply = '[1,2]';
      expect(await LocalTtsDownloads.fetchList(), isNull, reason: '获取下载地址失败');
      reply = '{}';
      expect(await LocalTtsDownloads.fetchList(), isEmpty, reason: '暂无可用下载地址');
    });
  });

  group('worker isolate (fake synthesizer)', () {
    test('synthesize: voice id, threads, WAV back; one worker reused; unknown model; empty text', () async {
      await LocalTtsManager.importZip(writeTo(scratch, 'v.zip', vitsZip()).path);
      await LocalTtsManager.setNumThreads('vits-zh', 3);
      final wav = await LocalTtsManager.synthesize('vits-zh', 2, '你好');
      final w = LocalTtsFiles.readWav(wav);
      expect(w.sampleRate, 16003, reason: 'numThreads 3 reached the engine');
      expect(w.samples.length, 20);
      expect(w.samples.first, closeTo(0.02, 0.001), reason: 'sid 2');
      expect(LocalTtsManager.workerRunning, isTrue);
      final again = LocalTtsFiles.readWav(await LocalTtsManager.synthesize('vits-zh', 0, 'abc'));
      expect(again.samples.length, 30);
      expect(logs.where((l) => l.startsWith('本地TTS：rss=')), isNotEmpty);
      await expectLater(LocalTtsManager.synthesize('nope', 0, 'x'), throwsA(predicate((e) => '$e' == '本地模型不存在：nope')));
      await expectLater(LocalTtsManager.synthesize('vits-zh', 0, ''), throwsA(predicate((e) => '$e' == '本地合成为空')));
      await expectLater(LocalTtsManager.synthesize('vits-zh', 0, 'boom'), throwsA(predicate((e) => '$e' == 'Bad state: boom')));
      expect(logs, contains('本地TTS合成失败（vits-zh）：Bad state: boom'));
    });

    test('zipvoice clone: reference WAV, text and steps reach the engine; missing reference', () async {
      await LocalTtsManager.importShared(writeTo(scratch, 'vocos_24khz.onnx', [1]).path);
      final zip = ZipEncoder().encode(Archive()
        ..add(_f('tts.json', jsonEncode({'name': 'clone', 'engine': 'zipvoice', 'voices': []})))
        ..add(_f('tokens.txt'))
        ..add(_f('lexicon.txt'))
        ..add(_f('encoder.onnx'))
        ..add(_f('decoder.onnx')));
      await LocalTtsManager.importZip(writeTo(scratch, 'c.zip', zip).path);
      await LocalTtsManager.setNumSteps('clone', 16);
      final ref = wavUri(Float32List.fromList(List.filled(100, 0.1)), 24000);
      final w = LocalTtsFiles.readWav(await LocalTtsManager.synthesize('clone', 0, '你好', referenceAudioDataUri: ref, referenceText: '参考文字'));
      expect(w.sampleRate, 24016, reason: 'reference rate + numSteps');
      expect(w.samples.first, closeTo(0.04, 0.001), reason: 'reference text length');
      await expectLater(LocalTtsManager.synthesize('clone', 0, 'x'), throwsA(predicate((e) => '$e' == '克隆引擎缺少参考音频')));
      await expectLater(LocalTtsManager.synthesize('clone', 0, 'x', referenceAudioDataUri: 'data:audio/wav;base64,SUQz'),
          throwsA(predicate((e) => '$e' == '参考音频仅支持 WAV 格式')));
    });

    test('watchdog: no progress → worker killed (本地合成超时), the next request starts a new worker', () async {
      LocalTtsManager.watchdogTimeout = const Duration(milliseconds: 300);
      await LocalTtsManager.importZip(writeTo(scratch, 'v.zip', vitsZip()).path);
      await expectLater(LocalTtsManager.synthesize('vits-zh', 0, 'hang'), throwsA(predicate((e) => '$e' == '本地合成超时')));
      expect(logs, contains('本地TTS合成超时（180s 无任何进展），强杀 worker 重建'));
      expect(LocalTtsManager.workerRunning, isFalse);
      expect(LocalTtsFiles.readWav(await LocalTtsManager.synthesize('vits-zh', 0, 'ok')).samples.length, 20);
    });

    test('destroy timeout kills a busy worker; cancel; recycle cool-down; background idle destroy', () async {
      await LocalTtsManager.importZip(writeTo(scratch, 'v.zip', vitsZip()).path);
      await LocalTtsManager.synthesize('vits-zh', 0, 'warm');
      LocalTtsManager.destroyTimeout = const Duration(milliseconds: 200);
      final busy = LocalTtsManager.synthesize('vits-zh', 0, 'hang');
      await waitPending();
      await LocalTtsManager.destroy();
      await expectLater(busy, throwsA(predicate((e) => '$e' == '本地销毁超时')));
      expect(logs, contains('本地TTS销毁超时（10s），强杀 worker'));
      expect(LocalTtsManager.workerRunning, isFalse);

      final hanging = LocalTtsManager.synthesize('vits-zh', 0, 'hang');
      await waitPending();
      LocalTtsManager.cancel();
      await expectLater(hanging, throwsA(predicate((e) => '$e' == '已取消')));
      expect(logs.where((l) => l.contains('已取消')), isEmpty, reason: 'cancel is not logged as a failure');
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      LocalTtsManager.debugWorkerMessage({'event': 'recycled', 'reason': '实例增长 2000MB'});
      expect(logs, contains('本地TTS：检测到内存风险，回收实例（实例增长 2000MB）'));
      await expectLater(LocalTtsManager.synthesize('vits-zh', 0, 'x'), throwsA(predicate((e) => '$e' == '内存超限冷却中')));
      await LocalTtsManager.reset();
      await LocalTtsManager.load();

      LocalTtsManager.backgroundIdle = const Duration(milliseconds: 100);
      await LocalTtsManager.synthesize('vits-zh', 0, 'fg');
      LocalTtsManager.lifecycle(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(logs, contains('本地TTS：后台空闲 20 秒，销毁实例释放内存'));
      LocalTtsManager.lifecycle(AppLifecycleState.resumed);
      expect(LocalTtsFiles.readWav(await LocalTtsManager.synthesize('vits-zh', 1, 'ab')).samples.first, closeTo(0.01, 0.001));
    });
  });

  group('engine selection in the TTS dispatcher', () {
    test('bdtts / bdttsclone pages go to the local engine; the original member gate', () async {
      final rec = RecordingEngine();
      LocalTtsEngine.instance = rec;
      final local = pageEngine(TtsPages.localPage('vits-zh', '2'));
      expect(TtsKind.of(local), TtsKind.local);
      final a = await TtsController.synthesize(local, '正文');
      expect(a.ext, 'wav');
      expect(rec.calls.last, 'vits-zh|2|${TtsController.localVipOnly}||', reason: 'non-members hear the member notice');
      await TtsController.synthesize(local, '正文', debug: (_) {});
      expect(rec.calls.last, 'vits-zh|2|正文||', reason: 'the 试听 path (debug callback) is not gated');
      final clone = pageEngine(TtsPages.localClonePage('clone', '参考', 'data:audio/wav;base64,AA=='));
      await TtsController.synthesize(clone, '正文');
      expect(rec.calls.last, 'clone|0|正文|data:audio/wav;base64,AA==|参考', reason: 'bdttsclone has no gate in the original');
      await signIn(vip: true);
      await TtsController.synthesize(local, '正文');
      expect(rec.calls.last, 'vits-zh|2|正文||');
    });

    test('end to end: a member, a page engine of an imported model, the worker', () async {
      await signIn(vip: true);
      await LocalTtsManager.importZip(writeTo(scratch, 'v.zip', vitsZip()).path);
      final a = await TtsController.synthesize(pageEngine(TtsPages.localPage('vits-zh', '2')), '你好');
      final w = LocalTtsFiles.readWav(a.bytes);
      expect(w.samples.first, closeTo(0.02, 0.001));
      await expectLater(TtsController.synthesize(pageEngine(TtsPages.localPage('gone', '0')), 'x'),
          throwsA(predicate((e) => '$e' == '本地模型不存在：gone')));
    });
  });

  group('model manager sheet', () {
    // one backend for the group: the preview player of LocalEngines is static and keeps the backend it was made with
    final audio = SilentAudio();
    final oldPick = DeviceIo.pickFile;
    final oldAudio = AudioBackend.create;
    setUp(() {
      audio.played.clear();
      Toast.log.clear();
      AudioBackend.create = () => audio;
    });
    tearDown(() {
      DeviceIo.pickFile = oldPick;
      AudioBackend.create = oldAudio;
    });

    Widget app() => const GetMaterialApp(home: TTsSetting());

    /// Lets real IO / isolates run until [done] holds.
    Future<void> until(WidgetTester t, bool Function() done) async {
      bool spinning() =>
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty || find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      for (var i = 0; i < 300 && (!done() || spinning()); i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 20)); // Dio needs fake time to move
      }
      if (!spinning()) await t.pumpAndSettle();
      expect(done(), isTrue,
          reason: 'last toasts: ${Toast.log.reversed.take(3).toList()}; texts: '
              '${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(40).toList()}');
    }

    bool toast(String prefix) => Toast.log.any((m) => m.startsWith(prefix));

    testWidgets('download from down.json (progress dialog) → voices → engine; settings; delete keeps engines', (t) async {
      final rec = RecordingEngine();
      LocalTtsEngine.instance = rec;
      final net = MemoryAdapter({
        '/static/down.json': utf8.encode(jsonEncode({'vits 中文': 'http://models.test/files/vits-zh.zip', '网盘': 'https://pan.example.com/s/abc'})),
        '/files/vits-zh.zip': vitsZip(),
      });
      LocalTtsDownloads.dio = Dio()..httpClientAdapter = net;
      final oldBase = Common.apiBase;
      Common.apiBase = 'http://own.test/';
      addTearDown(() {
        Common.apiBase = oldBase;
        LocalTtsDownloads.dio = null;
      });

      await t.pumpWidget(app());
      await t.tap(find.byKey(const Key('tts_local')));
      await t.pumpAndSettle();
      expect(find.text('本地引擎仅 VIP 可用'), findsOneWidget);
      await t.tap(find.byKey(const Key('local_download')));
      await until(t, () => find.byKey(const Key('local_down_vits 中文')).evaluate().isNotEmpty);
      expect(find.byKey(const Key('local_down_网盘')), findsOneWidget);
      await t.tap(find.byKey(const Key('local_down_vits 中文')));
      await until(t, () => toast('已导入模型：vits-zh（2 款音色，'));
      expect(find.byKey(const Key('local_model_vits-zh')), findsOneWidget);
      expect(find.text('2 款音色 · 导入于 ${LocalEngines.date(LocalTtsManager.byName('vits-zh')!.importTime)}'), findsOneWidget);
      expect(Directory(p.join(dev.dir.path, 'cache', 'local_tts_download')).listSync(), isEmpty, reason: 'download removed after import');
      expect(net.seen, ['/static/down.json', '/files/vits-zh.zip']);

      await t.tap(find.byKey(const Key('local_engines_vits-zh')));
      await t.pumpAndSettle();
      expect(find.text('vits-zh · 2 款音色'), findsOneWidget);
      await t.tap(find.byKey(const Key('local_filter_lang_en')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('local_voice_0')), findsNothing);
      await t.tap(find.byKey(const Key('local_play_2')));
      await until(t, () => audio.played.isNotEmpty);
      expect(rec.calls.single, 'vits-zh|2|${LocalEngines.previewEn}||', reason: 'previews are not gated');
      expect(p.basename(audio.played.single), 'bdtts_preview.wav');

      await t.tap(find.byKey(const Key('local_voice_2')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('local_engine_name')), 'Bob 本地');
      await t.tap(find.byKey(const Key('local_engine_name_ok')));
      await until(t, () => toast('已添加：Bob 本地'));
      expect(TTSData.byId('bdtts_vits-zh_2')!.name, 'Bob 本地');
      expect(TtsPages.literal(TTSData.pageOf(TTSData.byId('bdtts_vits-zh_2')!))!.toJson(), {'method': 'bdtts', 'url': 'vits-zh', 'headers': {}, 'body': '2'});
      expect(find.text('已添加'), findsOneWidget);
      await t.tap(find.byKey(const Key('local_voice_2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('local_engine_name_ok')));
      await until(t, () => toast('该音色引擎已存在'));
      Navigator.of(t.element(find.text('vits-zh · 2 款音色'))).pop();
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('local_settings_vits-zh')));
      await t.pumpAndSettle();
      expect(find.text('vits-zh\n合成设置'), findsOneWidget);
      expect(find.text('流匹配步数（仅克隆模型）'), findsNothing);
      await t.tap(find.byKey(const Key('local_threads_1')));
      await t.pumpAndSettle();
      expect(find.text('当前：1 线程'), findsOneWidget);
      await t.tap(find.byKey(const Key('local_settings_save')));
      await until(t, () => toast('设置已保存'));
      expect(LocalTtsManager.byName('vits-zh')!.numThreads, 1);

      await t.tap(find.byKey(const Key('local_delete_vits-zh')));
      await t.pumpAndSettle();
      expect(find.text('确定删除模型「vits-zh」吗？\n由它生成的全部朗读引擎会被保留。'), findsOneWidget);
      await t.tap(find.byKey(const Key('dialog_confirm')));
      await until(t, () => toast('已删除模型，由它生成的朗读引擎已保留'));
      expect(find.text('尚未导入模型包\n\n点右上角「导入模型包」选择 zip 模型文件'), findsOneWidget);
      expect(TTSData.byId('bdtts_vits-zh_2'), isNotNull, reason: 'engines stay');
    });

    testWidgets('import from Files; a clone model: reference WAV, words required, engine created', (t) async {
      final rec = RecordingEngine();
      LocalTtsEngine.instance = rec;
      await t.runAsync(() => LocalTtsManager.importShared(writeTo(scratch, 'vocos_24khz.onnx', [1]).path));
      final zip = writeTo(scratch, 'clone.zip', ZipEncoder().encode(Archive()
        ..add(_f('tts.json', jsonEncode({'name': 'clone', 'engine': 'zipvoice', 'voices': []})))
        ..add(_f('tokens.txt'))
        ..add(_f('lexicon.txt'))
        ..add(_f('encoder.onnx'))
        ..add(_f('decoder.onnx'))));
      final wav = writeTo(scratch, 'me.wav', LocalTtsFiles.wavBytes(Float32List(16000 * 4), 16000));
      File? next = zip;
      DeviceIo.pickFile = ({List<String>? extensions, bool image = false}) async => next;

      await t.pumpWidget(app());
      await t.tap(find.byKey(const Key('tts_local')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('local_import')));
      await until(t, () => toast('已导入模型：clone（0 款音色，'));
      expect(find.text('克隆模型 · 上传音频即可克隆音色 · 导入于 ${LocalEngines.date(LocalTtsManager.byName('clone')!.importTime)}'), findsOneWidget);

      await t.tap(find.byKey(const Key('local_engines_clone')));
      await t.pumpAndSettle();
      expect(find.text('参考音频：未选择'), findsOneWidget);
      next = wav;
      await t.tap(find.byKey(const Key('local_clone_pick')));
      await until(t, () => find.text('参考音频：me.wav（4.0 秒）').evaluate().isNotEmpty);
      await t.tap(find.byKey(const Key('local_clone_create')));
      await t.pumpAndSettle();
      expect(Toast.log.last, '请先填写参考音频中说的文字');
      await t.enterText(find.byKey(const Key('local_clone_text')), '今天天气很好');
      await t.tap(find.byKey(const Key('local_clone_preview')));
      await until(t, () => audio.played.isNotEmpty);
      expect(rec.calls.single, startsWith('clone|0|${LocalEngines.previewClone}|data:audio/wav;base64,'));
      expect(p.basename(audio.played.single), 'bdtts_clone_preview.wav');
      await t.tap(find.byKey(const Key('local_clone_create')));
      await until(t, () => toast('已添加：克隆音色'));
      final e = TTSData.engines.singleWhere((x) => x.name == '克隆音色');
      final r = TtsPages.literal(TTSData.pageOf(e))!;
      expect((r.method, r.url, r.headers['refText']), ('bdttsclone', 'clone', '今天天气很好'));
      expect(LocalTtsFiles.readWav(LocalTtsFiles.dataUriBytes(r.body)).samples.length, 16000 * 4);
      expect(LocalEngines.modelsOf([e.id, 'nope']), ['clone']);

      await t.tap(find.byKey(const Key('local_settings_clone')));
      await t.pumpAndSettle();
      expect(find.text('流匹配步数（仅克隆模型）'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('local_steps_16')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('local_steps_16')));
      await t.pumpAndSettle();
      expect(find.text('当前：16 步'), findsOneWidget);
      await t.tap(find.byKey(const Key('local_settings_save')));
      await until(t, () => toast('设置已保存'));
      expect(LocalTtsManager.byName('clone')!.numSteps, 16);
    });
  });
}
