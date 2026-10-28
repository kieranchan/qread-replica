// 时光源 in the pages: the `source_login` route (init/glue_routes.dart -> pages/source/sg_login.dart) with a login url and with a
// login form, the source manager's per-source menu, and the discovery entries of a 时光源 (web entry, actions, refreshExplore).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/source.dart';
import 'package:newread/init/glue_routes.dart';
import 'package:newread/models/source.dart';
import 'package:newread/pages/search/book_search_service.dart';
import 'package:newread/pages/search/engine_book_search_service.dart';
import 'package:newread/pages/source/source_setting.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/source/baswebview.dart';
import 'package:newread/util/source/cache.dart';
import 'package:newread/util/source/inapp_engine.dart';
import 'package:newread/util/source/js_engine.dart';
import 'package:newread/util/source/run.dart';
import 'package:newread/widget/discovery/discovery_right.dart';

import '../support/env.dart';
import 'support.dart';
import 'time_source_support.dart';

late TimeServer site;

Map<String, dynamic> rawSource() => {
      'bookSourceUrl': site.base,
      'bookSourceName': '测试时光源',
      'html': fixture('time_source.html'),
      'login': true,
      'help': true,
      'enabled': true,
      'enabledExplore': true,
    };

void main() {
  late TestDevice dev;
  final opened = <SourceBrowserRequest>[];
  setUpAll(() async => site = await TimeServer.start(fixture('time_source.html')));
  tearDownAll(() => site.close());
  setUp(() async {
    dev = await freshArea();
    FakeSourceEngine.created.clear();
    SourceJsEngine.create = FakeSourceEngine.new;
    WebCookies.push = (_) async {};
    WebCookies.pull = (_) async {};
    WebCookies.pullAll = () async {};
    SourceUi.resetForTests();
    opened.clear();
    SourceUi.openBrowser = (r) async {
      opened.add(r);
      return '';
    };
    BookSearchService.instance = EngineBookSearchService();
    site.requests.clear();
  });
  tearDown(() async {
    await SourceRun.clear();
    dev.delete();
  });

  Future<BuildContext> host(WidgetTester t) async {
    late BuildContext ctx;
    await t.runAsync(() async {
      await Sourcedata.load();
      await Sources.add(rawSource());
    });
    await t.pumpWidget(app(Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }))));
    return ctx;
  }

  testWidgets('source_login: a login url from getloginurl() opens the source browser page with the bridge', (t) async {
    final ctx = await host(t);
    await act(t, () async => unawaited(GlueRoutes.open(ctx, 'source_login', arguments: site.base)));
    await idleUntil(t, () => opened.isNotEmpty);
    expect(opened.single.url, '${site.base}/login.html');
    expect(opened.single.title, '登录');
    expect(opened.single.source?.bookSourceUrl, site.base);
    expect(opened.single.overrideUrlLoading, isFalse);
  });

  testWidgets('source_login: a login form is shown, saved as LoginInfo, then login() runs and the cookie is kept', (t) async {
    final ctx = await host(t);
    await t.runAsync(() => Cache(site.base).set('loginmode', 'form'));
    await act(t, () async => unawaited(GlueRoutes.open(ctx, 'source_login', arguments: site.base)));
    await idleUntil(t, () => find.byKey(const Key('sg_login_账号')).evaluate().isNotEmpty);
    expect(find.text('检查'), findsOneWidget);
    await t.enterText(find.byKey(const Key('sg_login_账号')), 'me');
    await t.enterText(find.byKey(const Key('sg_login_密码')), 'pw');
    await act(t, () => t.tap(find.byKey(const Key('sg_login_ok'))));
    await idleUntil(t, () => CookieStore.getKey(site.base, 'token').isNotEmpty);
    expect(CookieStore.getKey(site.base, 'token'), 't-me');
    final info = await t.runAsync(() => Cache(site.base).get('LoginInfo'));
    expect(jsonDecode(info!), {'账号': 'me', '密码': 'pw'});
    expect(site.requests.any((r) => r.uri.path == '/login'), isTrue);
    await idleUntil(t, () => find.byKey(const Key('sg_login_ok')).evaluate().isEmpty);
  });

  testWidgets('source manager: 登录 and 帮助 for a 时光源 with 需要登录 / 启用帮助', (t) async {
    await t.runAsync(() async {
      await Sourcedata.load();
      await Sources.add(rawSource());
    });
    await t.pumpWidget(app(const SourceSettingPage()));
    await idle(t);
    await act(t, () => t.tap(find.byKey(Key('menu_${site.base}'))));
    await t.pumpAndSettle();
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('帮助'), findsOneWidget);
    expect(find.text('调试'), findsOneWidget);
    await act(t, () => t.tap(find.text('登录')));
    await idleUntil(t, () => opened.isNotEmpty);
    expect(opened.single.url, '${site.base}/login.html');
  });

  testWidgets('discovery: entries from getfinds(), a web entry opens the browser, a drop-down stores its value and reloads', (t) async {
    await t.runAsync(() async {
      await Sourcedata.load();
      await Sources.add(rawSource());
    });
    final source = Source.fromJson(rawSource());
    await t.pumpWidget(app(Scaffold(body: DiscoveryRightPage(source: source))));
    await idleUntil(t, () => find.text('测试书').evaluate().isNotEmpty);
    expect(find.text('线路: ${site.base}'), findsOneWidget);

    await act(t, () => t.tap(find.text('书源设置')));
    await idleUntil(t, () => opened.isNotEmpty);
    expect(opened.single.url, '${site.base}/settings.html');
    expect(opened.single.source?.bookSourceUrl, site.base);

    final page = FakeSourceEngine.created.single.page!;
    await act(t, () => t.tap(find.text('线路: ${site.base}')));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.text('${site.base}/v2').last));
    await idleUntil(t, () => page.calls.where((c) => c == 'getfinds()').length == 2);
    expect(await t.runAsync(() => Cache(site.base).get('线路')), '${site.base}/v2');
    expect(page.calls, contains("(async function(){ return await eval(\"applyFilter('线路')\"); })()"));
    await t.runAsync(() => Cache(site.base).set('server', site.base));
    // the page runner was started inside the widget test: stop it (and its idle sweep timer), let the HTTP client's idle timer run
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => SourceRun.clear());
    await t.pump(const Duration(seconds: 30));
  });
}
