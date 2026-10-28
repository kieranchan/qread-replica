// Device-channel jobs of the bound 轻阅读 backend (0x2ad0ac) and 导入后端 (0xf77e50), against a fake backend on 127.0.0.1.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/common.dart';
import 'package:newread/common/nav.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/data/qsource.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/source.dart';
import 'package:newread/qread/qread.dart';
import 'package:newread/qread/qread_jobs.dart';
import 'package:newread/qread/rssdata.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

class Backend {
  final HttpServer server;
  final List<String> calls = [];
  final Map<String, Object?> bodies = {};
  final List<String> uploads = [];
  Backend(this.server);
  String get base => 'http://127.0.0.1:${server.port}';

  static Future<Backend> start() async {
    final b = Backend(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    b.server.listen(b._handle);
    return b;
  }

  Future<void> _handle(HttpRequest req) async {
    final cmd = req.uri.path.replaceFirst('/api/5', '');
    calls.add(cmd);
    Object? reply;
    if (cmd == '/importBookPreview') {
      final raw = utf8.decode(await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b)), allowMalformed: true);
      final name = RegExp(r'filename="([^"]*)"').firstMatch(raw)?.group(1) ?? '';
      uploads.add(name);
      reply = name.startsWith('bad')
          ? {'isSuccess': false, 'errorMsg': '文件格式错误'}
          : {
              'isSuccess': true,
              'data': {
                'books': [
                  {'name': name.replaceAll('.txt', ''), 'author': '作者', 'bookUrl': 'qread://book/$name', 'origin': 'loc_book'},
                ],
              },
            };
    } else {
      final text = await utf8.decoder.bind(req).join();
      final body = text.isEmpty ? null : jsonDecode(text);
      bodies[cmd] = body;
      reply = switch (cmd) {
        '/login' => {'isSuccess': true, 'data': {'accessToken': 'tok', 'username': 'u'}},
        '/getUserInfo' => {'isSuccess': true, 'data': {'userInfo': {'username': 'u'}}},
        '/urlsaveBook' => (body as Map)['url'] == 'https://book.example/1'
            ? {'isSuccess': true, 'data': {'name': '网址书', 'author': '甲', 'bookUrl': 'https://book.example/1', 'origin': 'https://src'}}
            : {'isSuccess': false, 'errorMsg': '未找到书源'},
        '/getBookSourcesNew' => {'isSuccess': true, 'data': {'list': [{'bookSourceUrl': 'https://q1', 'bookSourceName': '后端一'}], 'page': 1, 'md5': 'm5'}},
        '/getRssSourcessNew' => {'isSuccess': true, 'data': {'list': [{'sourceUrl': 'https://r1', 'sourceName': '后端订阅'}], 'page': 1, 'md5': 'r5'}},
        '/noCookies' => {'isSuccess': true, 'data': 'ok'},
        _ => {'isSuccess': false, 'errorMsg': '未知命令 $cmd'},
      };
    }
    req.response.headers.contentType = ContentType.json;
    req.response.add(utf8.encode(jsonEncode(reply)));
    await req.response.close();
  }
}

Future<Object?> job(Map<String, Object?> m) => QreadWebsocket.handle(jsonEncode(m));

void main() {
  late TestDevice dev;
  late Backend backend;
  setUpAll(() async => backend = await Backend.start());
  tearDownAll(() => backend.server.close(force: true));
  setUp(() async {
    dev = await newDevice();
    // the widget-test binding answers every HttpClient request with 400; these tests talk to a local fake backend
    HttpOverrides.global = null;
    Common.appid = 'dev1';
    Qread.resetForTests();
    QreadHooks.reset();
    backend.calls.clear();
    backend.uploads.clear();
    Toast.log.clear();
    await Qread.bind(backend.base, 'u', 'pw');
    backend.calls.clear();
  });
  tearDown(() {
    QreadHooks.reset();
    dev.delete();
  });

  test('logout: the binding ends (file store, allowchange 2, no edit permission), the main page is told', () async {
    var told = 0;
    QreadHooks.onLogout = () => told++;
    await Qread.setCanEditSource(true);
    QreadJobs.inited = true;
    await job({'msg': 'logout'});
    expect(Qread.isbind, isFalse);
    expect(await Storage.read('Qreadisbinddev1'), 'false');
    expect(Qread.allowchange, 2);
    expect(Qread.caneditsource, isFalse);
    expect(QreadJobs.inited, isFalse);
    expect(told, 1);
  });

  test('sourcemd5 / rssmd5 fetch the lists again only when the md5 changed; bookmd5 does nothing', () async {
    await job({'msg': 'sourcemd5', 'md5': 'm5'});
    expect(QSources.sources.single.bookSourceUrl, 'https://q1');
    expect(QSources.sources.single.isqread, isTrue);
    expect(QSources.md5, 'm5');
    await job({'msg': 'sourcemd5', 'md5': 'm5'});
    expect(backend.calls.where((c) => c == '/getBookSourcesNew').length, 1);
    await job({'msg': 'rssmd5', 'md5': 'r5'});
    expect(QRssSources.sources.single.sourceUrl, 'https://r1');
    await job({'msg': 'rssmd5', 'md5': 'r5'});
    expect(backend.calls.where((c) => c == '/getRssSourcessNew').length, 1);
    await job({'msg': 'bookmd5', 'md5': 'x'});
    expect(backend.calls, ['/getBookSourcesNew', '/getRssSourcessNew']);
  });

  test('init asks /getUserInfo once per binding; unknown jobs are answered with /noCookies {id}', () async {
    await job({'msg': 'init'});
    await job({'msg': 'init'});
    expect(backend.calls.where((c) => c == '/getUserInfo').length, 1);
    await job({'msg': 'somethingNew', 'id': 'j-7'});
    expect(backend.bodies['/noCookies'], {'id': 'j-7'});
  });

  test('refreshBookInfo / Toc / Content act on the backend book open in the reader whose origin is the title; refreshExplore', () async {
    final seen = <String>[];
    QreadHooks.refreshToc = () async => seen.add('toc');
    QreadHooks.refreshContent = () async => seen.add('content');
    QreadHooks.refreshBookInfo = (b) async => seen.add('info ${b.name}');
    await job({'msg': 'refreshBookToc', 'title': 'https://src'});
    expect(seen, isEmpty, reason: 'no book open');
    QreadHooks.currentBook = Book(name: '书', origin: 'https://src', isqread: true);
    await job({'msg': 'refreshBookToc', 'title': 'https://other'});
    expect(seen, isEmpty, reason: 'another source');
    await job({'msg': 'refreshBookToc', 'title': 'https://src'});
    await job({'msg': 'refreshContent', 'title': 'https://src'});
    await job({'msg': 'refreshBookInfo', 'title': 'https://src'});
    expect(seen, ['toc', 'content', 'info 书']);
    QreadHooks.currentBook = Book(name: '本地', origin: 'https://src');
    await job({'msg': 'refreshContent', 'title': 'https://src'});
    expect(seen.length, 3, reason: 'only backend books');

    await Storage.write('QExploreUrlhttps://src', '[cached]');
    var reloaded = 0;
    QreadHooks.refreshExplore = () async => reloaded++;
    await job({'msg': 'refreshExplore', 'title': 'https://src'});
    expect(await Storage.read('QExploreUrlhttps://src'), '');
    expect(reloaded, 1);
    final data = <String>[];
    QreadHooks.upLoginData = data.add;
    var relogin = 0;
    QreadHooks.reLoginView = () => relogin++;
    await job({'msg': 'upLoginData', 'title': '{"k":"v"}'});
    await job({'msg': 'reLoginView'});
    expect(data, ['{"k":"v"}']);
    expect(relogin, 1);
  });

  testWidgets('searchBook / addBook / openurl / gonggao use the pages', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    QreadHooks.context = () => ctx;
    final searches = <String>[];
    final opened = <Book>[];
    Nav.openSearch = (context, {key, sources}) async => searches.add('$key ${sources?.map((s) => s.bookSourceUrl).join(',')}');
    Nav.openBook = (context, book) async => opened.add(book);
    QSources.sources.add(Source(bookSourceUrl: 'https://q1', bookSourceName: '后端一'));

    await t.runAsync(() async {
      await job({'msg': 'searchBook', 'title': '三体', 'url': ''});
      await job({'msg': 'searchBook', 'title': '三体', 'url': 'group::https://q1'});
      await job({'msg': 'addBook', 'url': 'https://book.example/1'});
      await job({'msg': 'addBook', 'url': 'https://nothing'});
    });
    expect(searches, ['三体 null', '三体 https://q1']);
    expect(opened.single.name, '网址书');
    expect(opened.single.isqread, isTrue);
    expect(Toast.log, contains('未找到书源'));

    final launched = <String>[];
    final links = <String>[];
    var answer = false;
    QreadHooks.confirmOpen = (c, title) async => answer;
    QreadHooks.launch = (u) async => launched.add(u);
    QreadHooks.openAppLink = (u) async => links.add(u);
    await t.runAsync(() async {
      await job({'msg': 'openurl', 'url': 'https://x.example', 'title': '网页'});
      answer = true;
      await job({'msg': 'openurl', 'url': 'https://x.example', 'title': '网页'});
      await job({'msg': 'openurl', 'url': 'legado://import/bookSource?src=u', 'title': '书源'});
    });
    expect(launched, ['https://x.example']);
    expect(links, ['legado://import/bookSource?src=u']);

    await job({'msg': 'gonggao', 'md5': '后端公告内容'});
    await t.pumpAndSettle();
    expect(find.text('提示'), findsOneWidget);
    expect(find.text('后端公告内容'), findsOneWidget);
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    await job({'msg': 'gonggao', 'md5': '第二次'});
    await t.pumpAndSettle();
    expect(find.text('第二次'), findsNothing, reason: 'once per run');
  });

  test('导入后端: txt files are uploaded to /importBookPreview, the answered books go on the shelf as backend books', () async {
    final dir = Directory.systemTemp.createTempSync('qread_up_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ok = File('${dir.path}/好书.txt')..writeAsStringSync('第一章\n正文');
    final bad = File('${dir.path}/bad.txt')..writeAsStringSync('x');
    QreadImport.pickFiles = () async => [ok, bad];
    final n = await QreadImport.run();
    expect(n, 1);
    expect(backend.uploads, ['好书.txt', 'bad.txt']);
    await Bookdata.load(force: true);
    final b = Bookdata.books.singleWhere((b) => b.name == '好书');
    expect((b.isqread, b.type_, b.isinfo), (true, 0, true));
    expect(Toast.log, containsAll(['请选择您想要导入的小说文件', '正在导入文件1', '正在导入文件2', '第2本书，导入失败:文件格式错误!']));

    await Qread.unbind();
    Toast.log.clear();
    expect(await QreadImport.run(), 0);
    expect(Toast.log, ['请先绑定轻阅读后端']);
  });
}
