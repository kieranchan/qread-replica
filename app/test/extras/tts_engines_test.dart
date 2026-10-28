// TTS engines as the original: page templates (`getttsurl` literals), the method dispatcher, Volcano (binary WebSocket protocol
// against a local server), MiMo (chat-completions audio against a local server), original-format import / export.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/ai/mimo_tts.dart';
import 'package:newread/ai/volcano_tts.dart';
import 'package:newread/data/tts.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/httptts.dart';
import 'package:newread/models/userinfo.dart';
import 'package:newread/util/audio/tts_controller.dart';
import 'package:newread/util/audio/tts_page.dart';

import '../support/env.dart';

class FakeHost implements TtsPageHost {
  final List<String> calls = [];
  String page = '';
  @override
  Future<void> load(String p) async => page = p;
  @override
  Future<TtsPageRequest> getttsurl(String text, {int speechRate = 50, String juese = '', String gender = ''}) async {
    calls.add('$text|$speechRate|$juese|$gender');
    return TtsPageRequest('data', '', const {}, base64Encode(utf8.encode('RIFF....WAVEfake')));
  }

  @override
  Future<void> dispose() async {}
}

HttpTts pageEngine(String page, {String name = 'e'}) => HttpTts(id: 'id-$name', name: name, html: {'page': page});

void main() {
  late TestDevice dev;
  setUp(() async => dev = await newDevice());
  tearDown(() async {
    await TtsPages.disposeHosts();
    dev.delete();
  });

  group('page templates', () {
    test('every built-in page evaluates statically to the original method / url / body', () {
      final cases = <String, (String, String, String)>{
        TtsPages.volcanoPage('BV001_streaming'): ('volcano', '', 'BV001_streaming'),
        TtsPages.edgePage('zh-CN-XiaoxiaoNeural'): ('edge', '', 'zh-CN-XiaoxiaoNeural'),
        TtsPages.mimoPage('冰糖', instruction: '语速"慢"，温柔'): ('mimo', '语速"慢"，温柔', '冰糖'),
        TtsPages.mimoClonePage('data:audio/wav;base64,UklGRg==', instruction: ''): ('mimoclone', '', 'data:audio/wav;base64,UklGRg=='),
        TtsPages.mimoDesignPage('一位青年女性\n声音清澈'): ('mimovoicedesign', '', '一位青年女性\n声音清澈'),
        TtsPages.localPage('vits-zh', '3'): ('bdtts', 'vits-zh', '3'),
      };
      cases.forEach((page, want) {
        expect(page, startsWith('<!DOCTYPE html>\n<html lang="en">'));
        expect(page, endsWith('\n</html>\n      '));
        final r = TtsPages.literal(page)!;
        expect((r.method, r.url, r.body), want);
      });
      final clone = TtsPages.literal(TtsPages.localClonePage('zipvoice', '参考文字', 'data:audio/wav;base64,AA=='))!;
      expect(clone.method, 'bdttsclone');
      expect(clone.headers, {'refText': '参考文字'});
    });

    test('a computing page is not literal; the blank template is a get page', () {
      const computed = '<script>async function getttsurl(speakText,speechRate){ return JSON.stringify({"method":"get","url":"https://x/?t="+speakText}); }</script>';
      expect(TtsPages.literal(computed), isNull);
      final blank = TtsPages.literal(TtsPages.blank())!;
      expect(blank.method, 'get');
      expect(TtsPages.literal('<script>// "method": "edge"\nasync function getttsurl(a){ var u = "http://h//x"; return JSON.stringify({method: "post", url: u, body: "a=1"}); }</script>')!.url, 'http://h//x');
    });

    test('kinds and tp: 0 normal page engines, 1 multi-role', () {
      expect(TtsKind.http.tp, 0);
      expect(TtsKind.multiRole.tp, 1);
      expect(TtsKind.of(pageEngine(TtsPages.volcanoPage('BV001_streaming'))), TtsKind.volcano);
      expect(TtsKind.of(pageEngine(TtsPages.mimoDesignPage('x'))), TtsKind.mimo);
      expect(TtsKind.of(pageEngine(TtsPages.localPage('m', '1'))), TtsKind.local);
      expect(TtsKind.of(pageEngine(TtsPages.edgePage('v'))), TtsKind.edge);
      expect(TtsKind.of(HttpTts(tp: 1)), TtsKind.multiRole);
      expect(TtsKind.of(HttpTts(html: {'url': 'https://x'})), TtsKind.http);
      expect(TtsKind.of(HttpTts(tp: 2)), TtsKind.volcano, reason: 'engines of earlier replica builds');
    });
  });

  group('dispatcher', () {
    test('data / edge / local gate / computed page through the host', () async {
      final data = await TtsController.run(TtsPageRequest('data', '', const {}, base64Encode([0x49, 0x44, 0x33, 1])), 'x');
      expect(data.bytes, [0x49, 0x44, 0x33, 1]);
      expect(data.ext, 'mp3');
      await expectLater(TtsController.synthesize(pageEngine(TtsPages.edgePage('v')), 'x'), throwsA(predicate((e) => '$e' == TtsController.edgeMissing)));
      // local engines run through util/audio/local (gate and synthesis: test/extras/local_tts_test.dart); no model here
      await expectLater(TtsController.synthesize(pageEngine(TtsPages.localPage('m', '1')), 'x'), throwsA(predicate((e) => '$e' == '本地模型不存在：m')));
      await UserSession.apply(Userinfo(username: 'u', vip: '2030-01-01', tockenid: 't', email: 'e@x.io', nickname: 'u', avatarUrl: '', isvip: true));
      await expectLater(TtsController.synthesize(pageEngine(TtsPages.localPage('m', '1')), 'x'), throwsA(predicate((e) => '$e' == '本地模型不存在：m')));
      final host = FakeHost();
      final old = TtsPageHost.create;
      TtsPageHost.create = () => host;
      addTearDown(() => TtsPageHost.create = old);
      const computed = '<script>async function getttsurl(speakText,speechRate,juese,gender){ return JSON.stringify({"method":"data","body":btoa(speakText)}); }</script>';
      final a = await TtsController.synthesize(pageEngine(computed), '你好', speed: 12, juese: '张三', gender: 'male');
      expect(host.page, computed);
      expect(host.calls, ['你好|60|张三|male']);
      expect(a.ext, 'wav');
      expect(TtsController.isSystem(TTSData.defaultEngine), isTrue);
      expect(TTSData.byId('system'), same(TTSData.defaultEngine));
      expect(TTSData.defaultEngine.id, '');
    });

    test('get / post pages: the reply is the audio; POST bodies are form-encoded by default', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String>[];
      server.listen((r) async {
        final body = await utf8.decodeStream(r);
        seen.add('${r.method} ${r.uri.path} ${r.headers.contentType?.mimeType ?? ''} $body');
        r.response.headers.contentType = ContentType('audio', 'mpeg');
        r.response.add([1, 2, 3]);
        await r.response.close();
      });
      addTearDown(() => server.close(force: true));
      final base = 'http://127.0.0.1:${server.port}';
      final get = await TtsController.run(TtsPageRequest('get', '$base/a.mp3', const {}, ''), 'x');
      expect(get.bytes, [1, 2, 3]);
      await TtsController.run(TtsPageRequest('post', '$base/tts', const {'X-A': '1'}, 'text=hi'), 'x');
      expect(seen, ['GET /a.mp3  ', 'POST /tts application/x-www-form-urlencoded text=hi']);
    });
  });

  group('Volcano', () {
    test('binary frame: header, size, gzip JSON with the original keys', () {
      final f = VolcanoTTS.buildFrame(VolcanoTTS.requestJson(appId: 'app', token: 'tk', voice: 'BV700_streaming', text: '你好', reqid: 'r1'));
      expect(f.sublist(0, 4), [0x11, 0x10, 0x11, 0x00]);
      final size = ByteData.sublistView(f, 4, 8).getUint32(0);
      expect(size, f.length - 8);
      final j = jsonDecode(utf8.decode(gzip.decode(f.sublist(8))));
      expect(j, {
        'app': {'appid': 'app', 'token': 'tk', 'cluster': 'volcano_tts'},
        'user': {'uid': '666'},
        'audio': {'voice_type': 'BV700_streaming', 'encoding': 'mp3'},
        'request': {'reqid': 'r1', 'text': '你好', 'text_type': 'plain', 'operation': 'submit'},
      });
      expect(VolcanoTTS.voices.length, 21);
      expect(VolcanoTTS.voices.first.id, 'BV700_streaming');
    });

    Uint8List audioFrame(int seq, List<int> audio) {
      final b = BytesBuilder()
        ..add([0x11, seq < 0 ? 0xb3 : 0xb1, 0x10, 0x00])
        ..add((ByteData(4)..setInt32(0, seq)).buffer.asUint8List())
        ..add((ByteData(4)..setUint32(0, audio.length)).buffer.asUint8List())
        ..add(audio);
      return b.toBytes();
    }

    test('synthesize against a local server: auth header, chunks until the negative sequence; error frames', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final auth = <String>[];
      var fail = false;
      server.listen((req) async {
        auth.add(req.headers.value('authorization') ?? '');
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((msg) {
          final j = jsonDecode(utf8.decode(gzip.decode((msg as List<int>).sublist(8))));
          if (fail) {
            final err = utf8.encode('quota exceeded');
            ws.add(Uint8List.fromList([0x11, 0xf0, 0x10, 0x00, 0, 0, 0x0b, 0xb8, 0, 0, 0, err.length, ...err]));
            return;
          }
          ws.add(Uint8List.fromList([0x11, 0xb0, 0x10, 0x00])); // ack
          ws.add(audioFrame(1, utf8.encode('ID3:${j['audio']['voice_type']}:')));
          ws.add(audioFrame(-2, utf8.encode('${j['request']['text']}')));
        });
      });
      addTearDown(() => server.close(force: true));
      VolcanoTTS.url = 'ws://127.0.0.1:${server.port}/api/v1/tts/ws_binary';
      addTearDown(() => VolcanoTTS.url = VolcanoTTS.endpoint);
      await expectLater(VolcanoTTS.synthesize('x', voice: 'BV001_streaming'), throwsA(predicate((e) => '$e' == VolcanoTTS.missing)));
      await VolcanoTTS.saveCredentials(' app ', ' tk ');
      final audio = await TtsController.synthesize(pageEngine(TtsPages.volcanoPage('BV406_streaming')), '第一段');
      expect(utf8.decode(audio.bytes), 'ID3:BV406_streaming:第一段');
      expect(audio.ext, 'mp3');
      expect(auth, ['Bearer; tk']);
      fail = true;
      await expectLater(VolcanoTTS.synthesize('x', voice: 'BV001_streaming'), throwsA(predicate((e) => '$e' == '火山引擎 TTS 错误(code=3000): quota exceeded')));
    });
  });

  group('MiMo', () {
    late HttpServer server;
    final bodies = <Map<String, dynamic>>[];
    final headers = <String>[];
    setUp(() async {
      bodies.clear();
      headers.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        bodies.add(Map<String, dynamic>.from(jsonDecode(await utf8.decodeStream(r)) as Map));
        headers.add('${r.headers.value('authorization')}|${r.headers.value('user-agent')}');
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode({
          'choices': [
            {'message': {'audio': {'data': base64Encode(utf8.encode('RIFFwav'))}}},
          ],
        }));
        await r.response.close();
      });
      MimoTTS.url = 'http://127.0.0.1:${server.port}/v1/chat/completions';
    });
    tearDown(() async {
      MimoTTS.url = '${MimoTTS.baseUrl}/chat/completions';
      await server.close(force: true);
    });

    test('preset / clone / design request bodies as the original; key required', () async {
      await expectLater(MimoTTS.synthesize('x', voice: '冰糖'), throwsA(isA<MimoTTSException>()));
      await MimoTTS.saveKey('mimokey_test');
      final a = await TtsController.synthesize(pageEngine(TtsPages.mimoPage('冰糖', instruction: '语速慢')), '你好');
      expect(utf8.decode(a.bytes), 'RIFFwav');
      expect(a.ext, 'wav');
      expect(bodies.last, {
        'model': 'mimo-v2.5-tts',
        'messages': [
          {'role': 'user', 'content': '语速慢'},
          {'role': 'assistant', 'content': '你好'},
        ],
        'audio': {'format': 'wav', 'voice': '冰糖'},
        'stream': false,
      });
      await TtsController.synthesize(pageEngine(TtsPages.mimoClonePage('data:audio/wav;base64,UklGRg==')), '克隆');
      expect(bodies.last['model'], 'mimo-v2.5-tts-voiceclone');
      expect(bodies.last['messages'], [
        {'role': 'assistant', 'content': '克隆'},
      ]);
      expect(bodies.last['audio'], {'format': 'wav', 'voice': 'data:audio/wav;base64,UklGRg=='});
      await TtsController.synthesize(pageEngine(TtsPages.mimoDesignPage('清澈女声', instruction: '慢一点')), '设计');
      expect(bodies.last['model'], 'mimo-v2.5-tts-voicedesign');
      expect(bodies.last['messages'][0], {'role': 'user', 'content': '清澈女声\n\n【自然语言控制】\n慢一点'});
      expect(bodies.last['audio'], {'format': 'wav'});
      expect(headers, [startsWith('Bearer mimokey_test|Dart/'), 'Bearer mimokey_test|MiMoCloneTTS-Dart/1.0', 'Bearer mimokey_test|MiMoVoiceDesignTTS-Dart/1.0']);
      expect(MimoTTS.body(model: 'm', text: 'a' * 2500)['messages'][0]['content'].length, 2000);
    });
  });

  test('import / export in the original format (html = page string, tp 1 = role setup JSON)', () async {
    await TTSData.load();
    final page = TtsPages.volcanoPage('BV001_streaming');
    final n = await Tts.importJson(jsonEncode([
      {'id': 'x1', 'name': '火山-通用女声(女声)', 'bookurl': '', 'tp': 0, 'html': page, 'roles': [], 'login': false, 'candel': true},
      {'id': 'x2', 'name': '多角色', 'bookurl': '', 'tp': 1, 'html': jsonEncode({'narrationEngineId': 'x1'}), 'roles': [], 'login': false, 'candel': true},
      {'name': 'Legado', 'url': 'https://tts.example/?t={{speakText}}'},
    ]));
    expect(n, 3);
    final v = TTSData.engines.firstWhere((e) => e.name == '火山-通用女声(女声)');
    expect(TTSData.pageOf(v), page);
    expect(TtsKind.of(v), TtsKind.volcano);
    expect(TTSData.engines.firstWhere((e) => e.name == '多角色').html['narrationEngineId'], 'x1');
    final out = Tts.toOriginal(v);
    expect(out['html'], page);
    expect(out['tp'], 0);
  });
}
