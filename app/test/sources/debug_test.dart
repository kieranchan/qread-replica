import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/pages/source/debug_http_server.dart';
import 'package:newread/pages/source/debug_qsource.dart';
import 'package:newread/pages/source/debug_source.dart';
import 'package:newread/util/webbook/model/book_source.dart';

import '../support/env.dart';
import '../util/fake_site.dart';
import 'support.dart';

Future<(int, Map<String, dynamic>)> call(String method, String url, [String? body]) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl(method, Uri.parse(url));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(body));
    }
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    return (res.statusCode, text.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(text) as Map));
  } finally {
    c.close(force: true);
  }
}

void main() {
  late TestDevice dev;
  late FakeSite site;
  setUpAll(() async => site = await FakeSite.start());
  tearDownAll(() => site.close());
  setUp(() async => dev = await freshArea());
  tearDown(() => dev.delete());

  test('a run records every step and the request url of each page', () async {
    final run = DebugRun();
    final source = BookSource.fromJsonString(site.sourceJson('source_html.json'));
    run.add(debugStartLine('斗破'));
    await SourceApi.debug(source, '斗破', onLine: run.add);
    final log = run.toString();
    expect(log, startsWith('⇒开始搜索关键字:斗破'));
    expect(log, contains('︽搜索页解析完成'));
    expect(log, contains('︽详情页解析完成'));
    expect(log, contains('︽目录页解析完成 5'));
    expect(log, contains('︽正文页解析完成'));
    expect(run.urls['search'], startsWith('${site.base}/html/search?q='));
    expect(run.urls['book'], '${site.base}/book/1');
    expect(run.urls['toc'], '${site.base}/book/1/toc');
    expect(run.urls['content'], '${site.base}/chapter/1');
    expect(debugStartLine('++http://x/t'), '⇒开始访问目录页:http://x/t');
    expect(debugStartLine('--http://x/c'), '⇒开始访问正文页:http://x/c');
    expect(debugStartLine('http://x/b'), '⇒开始访问详情页:http://x/b');
    expect(debugStartLine('热门::/h'), '⇒开始访问发现页:/h');
  });

  test('POST /debug body parsing (key, typed requests, the original messages)', () {
    expect(DebugHttpServer.debugKey('{"key":"我的"}'), '我的');
    expect(DebugHttpServer.debugKey('{"type":"search","keyword":"斗破"}'), '斗破');
    expect(DebugHttpServer.debugKey('{"type":"explore","url":"/h","title":"热门"}'), '热门::/h');
    expect(DebugHttpServer.debugKey('{"type":"explore","url":"/h"}'), '发现::/h');
    expect(DebugHttpServer.debugKey('{"type":"book","url":"http://a/b"}'), 'http://a/b');
    expect(DebugHttpServer.debugKey('{"type":"toc","url":"http://a/t"}'), '++http://a/t');
    expect(DebugHttpServer.debugKey('{"type":"content","url":"https://a/c"}'), '--https://a/c');
    Matcher fails(String msg) => throwsA(isA<DebugHttpException>().having((e) => e.message, 'message', startsWith(msg)));
    expect(() => DebugHttpServer.debugKey(''), fails('请求体为空'));
    expect(() => DebugHttpServer.debugKey('[1]'), fails('请求体必须是 JSON 对象 {…}，不能是数组'));
    expect(() => DebugHttpServer.debugKey('{x'), fails('请求体不是合法 JSON: '));
    expect(() => DebugHttpServer.debugKey('{"type":"search"}'), fails('type=search 时 keyword 不能为空'));
    expect(() => DebugHttpServer.debugKey('{"type":"explore"}'), fails('type=explore 时 url 不能为空'));
    expect(() => DebugHttpServer.debugKey('{"type":"book","url":"/b"}'), fails('type=book 时 url 必须是 http(s):// 开头的详情页地址'));
    expect(() => DebugHttpServer.debugKey('{"type":"toc","url":"x"}'), fails('type=toc 时 url 必须是 http(s):// 开头的目录页地址'));
    expect(() => DebugHttpServer.debugKey('{}'), fails('无法识别的请求'));
  });

  test('HTTP service: docs, healthz, debug run, source get / put with validation, CORS, 404', () async {
    var source = <String, dynamic>{'bookSourceUrl': 'https://s.test', 'bookSourceName': '源'};
    final keys = <String>[];
    final server = DebugHttpServer(
      port: 0,
      runDebug: (k) async {
        keys.add(k);
        return DebugRunResult(k, 'log of $k', {'search': '<html>s</html>'});
      },
      partialLogs: () => '',
      getSource: () => source,
      saveSource: (body) async {
        if (body is! Map) throw const DebugHttpException('请求体必须是单个书源 JSON 对象 {…}，禁止传数组 [ … ]。');
        if (body['bookSourceUrl'] != source['bookSourceUrl']) throw const DebugHttpException('bookSourceUrl 必须与当前调试书源一致');
        source = Map<String, dynamic>.from(body);
        return {'action': 'edited', 'bookSourceUrl': source['bookSourceUrl'], 'bookSourceName': source['bookSourceName']};
      },
      currentKeyword: () => '我的',
    );
    await server.start(address: InternetAddress.loopbackIPv4);
    addTearDown(server.stop);
    final base = 'http://127.0.0.1:${server.boundPort}';

    var (code, j) = await call('GET', '$base/');
    expect(code, 200);
    expect(j['service'], '书源在线调试 HTTP');
    expect((j['current'] as Map)['bookSourceUrl'], 'https://s.test');
    expect((j['endpoints'] as List).map((e) => '${(e as Map)['method']} ${e['path']}'), ['GET /', 'GET /healthz', 'POST /debug', 'GET /source', 'PUT /source']);
    (code, j) = await call('GET', '$base/healthz');
    expect((code, j['success']), (200, true));

    (code, j) = await call('POST', '$base/debug', '{"type":"toc","url":"http://a/t"}');
    expect(code, 200);
    final data = j['data'] as Map;
    expect((data['key'], data['logs'], (data['raw'] as Map)['search'], (data['raw'] as Map)['content']), ('++http://a/t', 'log of ++http://a/t', '<html>s</html>', ''));
    (code, j) = await call('POST', '$base/debug', '[]');
    expect((code, j['success'], j['error']), (400, false, '请求体必须是 JSON 对象 {…}，不能是数组'));

    (code, j) = await call('GET', '$base/source');
    expect(((j['data'] as Map)['source'] as Map)['bookSourceName'], '源');
    (code, j) = await call('PUT', '$base/source', '{"bookSourceUrl":"https://s.test","bookSourceName":"新名"}');
    expect((code, (j['data'] as Map)['action']), (200, 'edited'));
    expect(source['bookSourceName'], '新名');
    (code, j) = await call('PUT', '$base/source', '{"bookSourceUrl":"https://other","bookSourceName":"x"}');
    expect((code, j['error']), (400, 'bookSourceUrl 必须与当前调试书源一致'));

    (code, j) = await call('DELETE', '$base/source');
    expect((code, j['error']), (404, '接口不存在: DELETE /source，请 GET / 查看全部接口'));
    final c = HttpClient();
    final opt = await (await c.openUrl('OPTIONS', Uri.parse('$base/debug'))).close();
    expect(opt.statusCode, 204);
    expect(opt.headers.value('access-control-allow-methods'), 'GET, POST, PUT, OPTIONS');
    c.close(force: true);
    expect(keys, ['++http://a/t']);
  });

  test('backend debug messages: log lines and Qwq page sources', () {
    final q = QwqLog()
      ..add('{"msg":"┌获取书名"}')
      ..add('搜索源码Qwq<html>s</html>')
      ..add('{"msg":"正文源码Qwq<p>c</p>"}')
      ..add('plain line');
    expect(q.lines, ['┌获取书名', 'plain line']);
    expect(q.sources, {'搜索源码': '<html>s</html>', '正文源码': '<p>c</p>'});
  });

  testWidgets('debug page streams the engine log of a run against the fake site', (t) async {
    final raw = Map<String, dynamic>.from(jsonDecode(site.sourceJson('source_html.json')) as Map);
    await t.pumpWidget(app(DebugSourcePage(source: raw)));
    await idle(t);
    expect(find.text('调试详情页 >> 输入详情页URL，如：'), findsOneWidget);
    expect(find.text('热门'), findsOneWidget); // explore kinds as quick links
    await t.enterText(find.byKey(const Key('debug_input')), '斗破');
    await act(t, () => t.testTextInput.receiveAction(TextInputAction.search));
    String log() => find.byKey(const Key('debug_log')).evaluate().isEmpty ? '' : (t.widget<SelectableText>(find.byKey(const Key('debug_log'))).data ?? '');
    await idleUntil(t, () => log().contains('┌获取书籍列表'));
    await idleUntil(t, () => log().contains('︽正文页解析完成'));
    expect(log(), startsWith('⇒开始搜索关键字:斗破'));
    expect(log(), contains('┌获取目录列表'));
  });
}
