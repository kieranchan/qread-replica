// 关于轻悦时光: the version comes from package_info_plus (`PackageInfo.version` shown, `buildNumber` sent to check_update); the update
// check of the page (progress, 发现新版本 / 已是最新版本) and of the main-page start-up (更新提醒 switch).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/common/common.dart';
import 'package:newread/pages/about_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/env.dart';

/// Real sockets inside a file that also has widget tests (the widget binding installs a 400-answering HttpClient).
class RealHttp extends HttpOverrides {}

/// Answers every request with [body] and records the urls.
class _Canned implements HttpClientAdapter {
  final Object? body;
  final List<Uri> seen = [];
  _Canned(this.body);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options.uri);
    if (body == null) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

_Canned _serve(Object? body) {
  final a = _Canned(body);
  AboutPage.dio = Dio()..httpClientAdapter = a;
  return a;
}

void main() {
  late TestDevice dev;
  final opened = <String>[];
  setUp(() async {
    dev = await newDevice();
    PackageInfo.setMockInitialValues(
        appName: '轻悦复刻', packageName: 'com.example', version: '2.2.1026', buildNumber: '1026', buildSignature: '', installerStore: null);
    opened.clear();
    AboutPage.openUrl = (u) async => opened.add(u);
  });
  tearDown(() {
    AboutPage.dio = null;
    dev.delete();
  });

  testWidgets('shows 加载中... then 版本 <PackageInfo.version>', (t) async {
    await t.pumpWidget(GetMaterialApp(home: const AboutPage()));
    expect(find.text('版本 加载中...'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('版本 2.2.1026'), findsOneWidget);
  });

  test('check_update sends platform + the build number as version; code 0 is an update, anything else or a failure is none', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <Map<String, String>>[];
    server.listen((r) async {
      seen.add(r.uri.queryParameters);
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode({'code': 0, 'updateUrl': 'https://example.invalid/x.ipa', 'description': '新版本'}));
      await r.response.close();
    });
    final old = Common.apiBase;
    Common.apiBase = 'http://127.0.0.1:${server.port}/';
    AboutPage.dio = Dio();
    try {
      final u = await HttpOverrides.runWithHttpOverrides(AboutPage.checkUpdate, RealHttp());
      expect(u.hasUpdate, isTrue);
      expect(u.description, '新版本');
      expect(u.updateUrl, 'https://example.invalid/x.ipa');
      expect(seen.single['version'], '1026');
      expect(seen.single['platform'], Common.platform);
      expect(int.tryParse(seen.single['t'] ?? ''), isNotNull);
    } finally {
      Common.apiBase = old;
      await server.close(force: true);
    }
    _serve({'code': -1, 'errorMsg': '已是最新版本'});
    expect((await AboutPage.checkUpdate()).hasUpdate, isFalse);
    _serve(null);
    expect((await AboutPage.checkUpdate()).hasUpdate, isFalse, reason: 'errors are "no update", as the original');
  });

  testWidgets('检查更新: progress, then 发现新版本 with 更新内容; 立即更新 opens the link', (t) async {
    _serve({'code': 0, 'updateUrl': 'https://example.invalid/new.ipa', 'description': '修复问题'});
    await t.pumpWidget(GetMaterialApp(home: const AboutPage()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('about_check')));
    await t.pump();
    expect(find.text('正在检查更新...'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('正在检查更新...'), findsNothing);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('更新内容:'), findsOneWidget);
    expect(find.text('修复问题'), findsOneWidget);
    expect(find.text('暂不更新'), findsOneWidget);
    await t.tap(find.text('立即更新'));
    await t.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);
    expect(opened, ['https://example.invalid/new.ipa']);
  });

  testWidgets('检查更新 without a newer build: 已是最新版本 / 确定', (t) async {
    _serve({'code': -1});
    await t.pumpWidget(GetMaterialApp(home: const AboutPage()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('about_check')));
    await t.pumpAndSettle();
    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.text('当前应用已是最新版本，无需更新。'), findsOneWidget);
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect(find.text('已是最新版本'), findsNothing);
  });

  testWidgets('main-page start-up: 更新提醒 off -> no request; on (default) -> 发现新版本 only for an update', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(GetMaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(AboutPage.reminderOn, isTrue, reason: 'unset means on (0x8e9124)');
    await Storage.setBool(AboutPage.updateReminderKey, false);
    final off = _serve({'code': 0, 'updateUrl': 'u', 'description': 'd'});
    expect(await t.runAsync(() => AboutPage.remindOnStart(ctx)), isFalse);
    expect(off.seen, isEmpty);

    await Storage.setBool(AboutPage.updateReminderKey, true);
    _serve({'code': 1});
    expect(await t.runAsync(() => AboutPage.remindOnStart(ctx)), isFalse);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    _serve({'code': 0, 'updateUrl': 'https://example.invalid/n.ipa', 'description': '说明'});
    expect(await t.runAsync(() => AboutPage.remindOnStart(ctx)), isTrue);
    await t.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('说明'), findsOneWidget);
    await t.tap(find.text('暂不更新'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(opened, isEmpty);
  });
}
