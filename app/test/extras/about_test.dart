// 关于轻悦时光: the version comes from package_info_plus (`PackageInfo.version` shown, `buildNumber` sent to check_update).
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/common/common.dart';
import 'package:newread/pages/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/env.dart';

/// Real sockets inside a file that also has widget tests (the widget binding installs a 400-answering HttpClient).
class RealHttp extends HttpOverrides {}

void main() {
  late TestDevice dev;
  setUp(() async {
    dev = await newDevice();
    PackageInfo.setMockInitialValues(
        appName: '轻悦复刻', packageName: 'com.example', version: '2.2.1026', buildNumber: '1026', buildSignature: '', installerStore: null);
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

  test('check_update sends the build number as version', () async {
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
      expect(u?.description, '新版本');
      expect(seen.single['version'], '1026');
      expect(seen.single['platform'], Common.platform);
    } finally {
      Common.apiBase = old;
      await server.close(force: true);
    }
  });
}
