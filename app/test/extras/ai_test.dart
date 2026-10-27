// AI layer against a local OpenAI-compatible server: request shape (headers, thinking off), non-streamed and SSE replies, tool calls,
// error texts, the model check, the chat agent's tool loop and member gate, role analysis parsing / heuristics.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/ai/chat/chat_agent.dart';
import 'package:newread/ai/openai_client.dart';
import 'package:newread/ai/read.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/ai_model_config.dart';
import 'package:newread/models/userinfo.dart';
import 'package:newread/storage/setting.dart';

import '../support/env.dart';

/// Scripted server: each request pops the next handler.
class FakeAi {
  late HttpServer server;
  final List<Map<String, dynamic>> bodies = [];
  final List<HttpHeaders> headers = [];
  final List<Future<void> Function(HttpResponse r, Map<String, dynamic> body)> script = [];

  String get url => 'http://127.0.0.1:${server.port}/v1/chat/completions';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      bodies.add(body);
      headers.add(req.headers);
      final h = script.isEmpty ? null : script.removeAt(0);
      if (h == null) {
        req.response.statusCode = 500;
      } else {
        await h(req.response, body);
      }
      await req.response.close();
    });
  }

  static Future<void> Function(HttpResponse, Map<String, dynamic>) json(Object reply, {int status = 200}) => (r, _) async {
        r.statusCode = status;
        r.headers.contentType = ContentType.json;
        r.write(jsonEncode(reply));
      };

  static Future<void> Function(HttpResponse, Map<String, dynamic>) sse(List<Object> chunks) => (r, _) async {
        r.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
        for (final c in chunks) {
          r.write('data: ${jsonEncode(c)}\n\n');
          await r.flush();
        }
        r.write('data: [DONE]\n\n');
      };

  static Map<String, dynamic> message(String content) => {
        'choices': [
          {'message': {'role': 'assistant', 'content': content, 'reasoning_content': '想一想'}, 'finish_reason': 'stop'},
        ],
      };
}

void main() {
  late TestDevice dev;
  late FakeAi ai;
  late AiModelConfig model;

  setUp(() async {
    dev = await newDevice();
    ai = FakeAi();
    await ai.start();
    model = AiModelConfig(id: 'm1', name: 'test', url: ai.url, key: 'sk-test', model: 'gpt-x', isRoleAnalysis: true, isPurify: true);
  });
  tearDown(() async {
    await ai.server.close(force: true);
    dev.delete();
  });

  test('chat sends the original headers and body (thinking off) and reads choices[0].message.content', () async {
    ai.script.add(FakeAi.json(FakeAi.message('你好')));
    final r = await OpenAiClient(model).chat(const [AiMessage.user('hi')], temperature: 0.01, maxTokens: 10);
    expect(r.content, '你好');
    expect(ai.headers.single.value('authorization'), 'Bearer sk-test');
    expect(ai.headers.single.value('api-key'), 'sk-test');
    final b = ai.bodies.single;
    expect(b['model'], 'gpt-x');
    expect(b['messages'], [
      {'role': 'user', 'content': 'hi'},
    ]);
    expect(b['enable_thinking'], false);
    expect(b['thinking'], {'type': 'disabled'});
    expect(b['temperature'], 0.01);
    expect(b['max_tokens'], 10);
    expect(b.containsKey('top_p'), isFalse);
  });

  test('errors: error.message of the reply, invalid format, incomplete config', () async {
    ai.script.add(FakeAi.json({'error': {'message': 'Invalid API key'}}, status: 401));
    await expectLater(OpenAiClient(model).chat(const [AiMessage.user('x')]), throwsA(predicate((e) => '$e' == 'Invalid API key')));
    ai.script.add(FakeAi.json({'foo': 1}));
    await expectLater(OpenAiClient(model).chat(const [AiMessage.user('x')]), throwsA(predicate((e) => '$e' == 'Invalid response format')));
    final empty = AiModelConfig(url: ai.url);
    await expectLater(OpenAiClient(empty).chat(const [AiMessage.user('x')]), throwsA(isA<AiException>()));
  });

  test('model check (检验): success → null, failure → 检验失败: …, incomplete → the original hint', () async {
    ai.script.add(FakeAi.json(FakeAi.message('ok')));
    expect(await OpenAiClient.testModel(model), isNull);
    expect(ai.bodies.last['messages'][0]['content'], 'test');
    ai.script.add(FakeAi.json({'error': {'message': 'model not found'}}, status: 404));
    expect(await OpenAiClient.testModel(model), '检验失败: model not found');
    expect(await OpenAiClient.testModel(AiModelConfig(url: ai.url)), '请先填写完整的接口地址、密钥和模型');
    expect(OpenAiClient.validUrl('https://x/v1/chat/completions'), isTrue);
    expect(OpenAiClient.validUrl('https://x/v1'), isFalse);
  });

  test('stream: text deltas and tool calls assembled by index', () async {
    ai.script.add(FakeAi.sse([
      {'choices': [{'delta': {'content': '正在'}}]},
      {'choices': [{'delta': {'content': '查找'}}]},
      {'choices': [{'delta': {'tool_calls': [{'index': 0, 'id': 'c1', 'function': {'name': 'web_', 'arguments': '{"que'}}]}}]},
      {'choices': [{'delta': {'tool_calls': [{'index': 0, 'function': {'name': 'search', 'arguments': 'ry":"三体"}'}}]}, 'finish_reason': 'tool_calls'}]},
    ]));
    final events = await OpenAiClient(model).chatStream(const [AiMessage.user('搜')]).toList();
    expect(events.where((e) => e.done == null).map((e) => e.text).join(), '正在查找');
    final done = events.last.done!;
    expect(done.content, '正在查找');
    expect(done.finishReason, 'tool_calls');
    expect(done.toolCalls.single.name, 'web_search');
    expect(done.toolCalls.single.args, {'query': '三体'});
    expect(ai.bodies.single['stream'], true);
  });

  group('ChatAgent', () {
    Future<void> member(bool vip) => UserSession.apply(
        Userinfo(username: 'u', vip: vip ? '永久' : '', tockenid: 't', email: 'u@x.io', nickname: 'u', avatarUrl: '', isvip: vip));

    test('non-members get the original gate', () async {
      await member(false);
      final agent = ChatAgent(model);
      await expectLater(agent.run(const [], 'hi').toList(), throwsA(predicate((e) => '$e' == ChatAgent.memberOnly)));
    });

    test('runs a tool round and feeds the result back; deep thinking prefixes the question', () async {
      await member(true);
      ai.script
        ..add(FakeAi.sse([
          {'choices': [{'delta': {'tool_calls': [{'index': 0, 'id': 'c1', 'function': {'name': 'echo', 'arguments': '{"v":"42"}'}}]}}]},
        ]))
        ..add(FakeAi.sse([
          {'choices': [{'delta': {'content': '答案是 42'}}]},
        ]));
      final tool = ChatTool(const AiTool('echo', 'echo', {'type': 'object'}), (a) async => 'echo:${a['v']}');
      final agent = ChatAgent(model, tools: [tool], deepThinking: true, context: const ChatContext(bookName: '三体', chapterCount: 30));
      final events = await agent.run(const [], '问题').toList();
      expect(events.whereType<ChatToolResult>().single.result, 'echo:42');
      final done = events.whereType<ChatDone>().single;
      expect(done.content, '答案是 42');
      expect(done.messages.map((m) => m.role), ['user', 'assistant', 'tool', 'assistant']);
      final first = ai.bodies.first;
      expect((first['messages'] as List).first['content'], contains('《三体》'));
      expect((first['messages'] as List).last['content'], '${ChatAgent.deepPrefix}问题');
      expect(first['tools'], isNotEmpty);
      final second = ai.bodies.last['messages'] as List;
      expect(second.last, {'role': 'tool', 'content': 'echo:42', 'tool_call_id': 'c1', 'name': 'echo'});
    });

    test('stops after 10 rounds of tool calls', () async {
      await member(true);
      for (var i = 0; i < 10; i++) {
        ai.script.add(FakeAi.sse([
          {'choices': [{'delta': {'tool_calls': [{'index': 0, 'id': 'c$i', 'function': {'name': 'echo', 'arguments': '{}'}}]}}]},
        ]));
      }
      final tool = ChatTool(const AiTool('echo', 'echo', {'type': 'object'}), (_) async => 'x');
      await expectLater(ChatAgent(model, tools: [tool]).run(const [], 'loop').toList(),
          throwsA(predicate((e) => '$e' == '工具调用轮数超过上限（10 轮）')));
    });
  });

  group('AiRead', () {
    test('role analysis sends the original prompt and parses a fenced JSON reply', () async {
      await Setting.saveAiModels([model]);
      ai.script.add(FakeAi.json(FakeAi.message('好的\n```json\n[{"id":"2","ispb":false,"gender":1,"str":"你来了","name":"林黛玉","personality":"多愁善感"}]\n```')));
      final r = await AiRead.analyzeRoles({'1': '天色已晚。', '2': '林黛玉说：“你来了”'});
      expect(r.single.name, '林黛玉');
      expect(r.single.gender, 1);
      expect(r.single.ispb, isFalse);
      final content = ai.bodies.single['messages'][0]['content'] as String;
      expect(content, startsWith('仅输出JSON数组'));
      expect(content, endsWith(jsonEncode([{'id': '1', 'text': '天色已晚。'}, {'id': '2', 'text': '林黛玉说：“你来了”'}])));
      expect(ai.bodies.single['max_tokens'], 16384);
      expect(ai.bodies.single['top_p'], 0.01);
    });

    test('without a model: the error text; the heuristic splits quotes and guesses the speaker; results are cached', () async {
      await expectLater(AiRead.analyzeRoles({'1': 'x'}), throwsA(predicate((e) => '$e' == '多角色引擎需要ai支持，请先配置ai接口')));
      final h = AiRead.heuristic({'7': '张三笑道：“好久不见。”李四问：“你是谁？”'});
      expect(h.map((l) => l.str), ['好久不见。', '你是谁？']);
      expect(h.first.name, '张三');
      final lines = await AiRead.rolesFor('book#1', {'7': '他说：“走吧。”'});
      expect(lines.single.str, '走吧。');
      expect(AiRead.cacheFile('book#1').existsSync(), isTrue);
      expect((await AiRead.readCache('book#1'))!.single.str, '走吧。');
    });

    test('purification uses the purify model and returns the cleaned text', () async {
      await Setting.saveAiModels([model]);
      ai.script.add(FakeAi.json(FakeAi.message('第一章 正文')));
      expect(await AiRead.purify('第一章 正文 www.ad.com'), '第一章 正文');
      expect(ai.bodies.single['messages'][0]['content'], contains('www.ad.com'));
    });
  });
}
