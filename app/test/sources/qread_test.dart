import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/common.dart';
import 'package:newread/data/qsource.dart';
import 'package:newread/pages/qread/qread_login.dart';
import 'package:newread/qread/api/qsourceapi.dart';
import 'package:newread/qread/api/rssapi.dart';
import 'package:newread/qread/qread.dart';
import 'package:newread/qread/rssdata.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';
import '../util/fake_site.dart';
import 'support.dart';

/// A user's own 轻阅读 backend: `/api/5/<cmd>?accessToken=…`, replies `{isSuccess, data, errorMsg}`.
class FakeBackend {
  final HttpServer server;
  final List<String> calls = [];
  final Map<String, Object?> bodies = {};
  FakeBackend(this.server);
  String get base => 'http://127.0.0.1:${server.port}';

  static Future<FakeBackend> start() async {
    final b = FakeBackend(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    b.server.listen(b._handle);
    return b;
  }

  Future<void> _handle(HttpRequest req) async {
    final cmd = req.uri.path.replaceFirst('/api/5', '');
    calls.add('$cmd ${req.uri.queryParameters['accessToken'] ?? ''}');
    final text = await utf8.decoder.bind(req).join();
    final body = text.isEmpty ? null : jsonDecode(text);
    bodies[cmd] = body;
    Object? reply;
    if (cmd == '/login') {
      final m = body as Map;
      reply = m['username'] == 'alice' && m['password'] == 'pw'
          ? {'isSuccess': true, 'data': {'accessToken': 'tok-1', 'username': 'alice'}}
          : {'isSuccess': false, 'errorMsg': '用户名或密码错误'};
    } else if (req.uri.queryParameters['accessToken'] != 'tok-1') {
      reply = {'isSuccess': false, 'errorMsg': '请先登录'};
    } else {
      reply = switch (cmd) {
        '/getUserInfo' => {'isSuccess': true, 'data': {'userInfo': {'username': 'alice'}, 'canEditSource': true}},
        '/getBookSourcesNew' => {
            'isSuccess': true,
            'data': {
              'list': [
                {'bookSourceUrl': 'https://q1', 'bookSourceName': '后端一', 'enabled': true},
                {'bookSourceUrl': 'https://q2', 'bookSourceName': '后端二', 'enabled': false},
              ],
              'page': 1,
              'md5': 'm5',
            },
          },
        '/getbookSourcejson' => {'isSuccess': true, 'data': jsonEncode({'bookSourceUrl': 'https://q1', 'bookSourceName': '后端一', 'searchUrl': '/s'})},
        '/editbookSources' => {'isSuccess': true, 'data': 'ok'},
        '/getRsssortUrls' => {'isSuccess': true, 'data': [{'sortName': '最新', 'sortUrl': 'u1'}]},
        '/getArticles' => {
            'isSuccess': true,
            'data': {'articles': [{'title': '后端文章', 'link': 'https://l/1'}], 'next': true},
          },
        '/getRssSourcessNew' => {'isSuccess': true, 'data': {'list': [{'sourceUrl': 'https://r1', 'sourceName': '后端订阅'}], 'page': 1, 'md5': 'r5'}},
        _ => {'isSuccess': false, 'errorMsg': '未知命令 $cmd'},
      };
    }
    req.response.headers.contentType = ContentType.json;
    req.response.add(utf8.encode(jsonEncode(reply)));
    await req.response.close();
  }
}

void main() {
  late TestDevice dev;
  late FakeBackend backend;
  late FakeSite site;
  setUpAll(() async {
    backend = await FakeBackend.start();
    site = await FakeSite.start();
  });
  tearDownAll(() async {
    await backend.server.close(force: true);
    await site.close();
  });
  setUp(() async {
    dev = await freshArea();
    Common.appid = 'dev1';
    backend.calls.clear();
  });
  tearDown(() => dev.delete());

  test('base urls typed on the bind page are normalised', () {
    expect(Qread.splitUrls(' 192.168.1.2:8080/ , https://r.example.com/api/5\nr2.test '), ['http://192.168.1.2:8080', 'https://r.example.com', 'http://r2.test']);
  });

  test('bind tries every url, stores the session under the device id, keeps the password encrypted', () async {
    await expectLater(Qread.bind(backend.base, 'alice', 'bad'), throwsA(isA<QreadException>().having((e) => e.message, 'm', '绑定失败:用户名或密码错误')));
    expect(() => Qread.api('/x'), throwsA(isA<QreadException>().having((e) => e.message, 'm', '请先绑定轻阅读后端')));

    await Qread.bind('127.0.0.1:1, ${backend.base}', 'alice', 'pw');
    expect((Qread.isbind, Qread.accessToken, Qread.caneditsource), (true, 'tok-1', true));
    expect(Qread.baseurls.first, backend.base); // the answering url goes first
    expect(Qread.api('/getUserInfo'), '${backend.base}/api/5/getUserInfo?accessToken=tok-1');
    expect(Qread.wsUrl('debug'), '${backend.base.replaceFirst('http', 'ws')}/api/5/debug?id=tok-1&sg=1');
    expect(await Storage.read('Qreadisbind'), '');
    expect(await Storage.read('Qreadisbinddev1'), 'true');
    expect(await Storage.read('accessTokendev1'), 'tok-1');
    expect(await Storage.read('Qreadusernamedev1'), 'alice');
    final stored = await Storage.read('Qreadpassworddev1');
    expect(stored, isNot(contains('pw')));
    expect(await Qread.savedPassword(), 'pw');

    // a fresh process restores the binding
    Qread.resetForTests();
    await Qread.load();
    expect((Qread.isbind, Qread.accessToken, Qread.baseurls.first), (true, 'tok-1', backend.base));

    await expectLater(Qread.post('/nope'), throwsA(isA<QreadException>().having((e) => e.message, 'm', '未知命令 /nope')));
    await Qread.unbind();
    expect(Qread.isbind, isFalse);
    expect(await Storage.read('accessTokendev1'), '');
  });

  test('backend sources and RSS through the bound backend', () async {
    await Qread.bind(backend.base, 'alice', 'pw');
    final list = await QSourceApi.refresh();
    expect(list.map((s) => (s.bookSourceName, s.isqread, s.enabled)), [('后端一', true, true), ('后端二', true, false)]);
    QSources.reset();
    expect((await QSources.load()).length, 2);
    expect(QSources.md5, 'm5');
    expect((await QSourceApi.sourceJson('https://q1'))['searchUrl'], '/s');
    await QSourceApi.save('https://q1', {'bookSourceUrl': 'https://q1', 'bookSourceName': '改'});
    expect(jsonDecode((backend.bodies['/editbookSources'] as Map)['json'] as String), {'bookSourceUrl': 'https://q1', 'bookSourceName': '改'});

    expect((await RssApi.sorts('https://r1')).single.sortName, '最新');
    final page = await RssApi.articles('https://r1', '最新', 'u1', 1);
    expect((page.articles.single.title, page.next), ('后端文章', true));
    final rss = await QRssSources.refresh();
    expect(rss.single.isqread, isTrue);
    expect(backend.calls.every((c) => c.startsWith('/login') || c.endsWith(' tok-1')), isTrue);
  });

  test('device channel: proxied GET runs on the device and answers with the page', () async {
    final r = await QreadWebsocket.handle(jsonEncode({'msg': 'get', 'id': 3, 'body': {'url': '${site.base}/echo', 'header': {'X-A': '1'}}})) as Map;
    expect(r['success'], isTrue);
    final echo = jsonDecode(r['response'] as String) as Map;
    expect((echo['method'], (echo['headers'] as Map)['x-a']), ('GET', '1'));
    expect(await QreadWebsocket.handle('{"msg":"unknown"}'), isNull);
  });

  // last: the page reads the stored binding while building (see support.dart `act`)
  testWidgets('bind page validates its fields', (t) async {
    await t.pumpWidget(app(const QReadLoginPage()));
    await idle(t);
    expect(find.text('轻阅读后端绑定'), findsOneWidget);
    expect(find.text('连接到您的轻阅读服务器'), findsOneWidget);
    await t.tap(find.byKey(const Key('qread_bind')));
    await t.pump();
    expect(find.text('请输入后端地址'), findsOneWidget);
    expect(find.text('请输入用户名'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
  });
}
