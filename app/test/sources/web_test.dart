import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/data/chromemark.dart';
import 'package:newread/pages/scanner/mobile_scanner.dart';
import 'package:newread/pages/web/bookmark_manager_page.dart';
import 'package:newread/pages/web/chrome.dart';
import 'package:newread/pages/web/chrome_inapp.dart';
import 'package:newread/pages/web/web_engine.dart';
import 'package:newread/pages/web/web_hooks.dart';
import 'package:newread/pages/web/webview.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/toast.dart';
import 'package:newread/util/webbook/util/client_app.dart';

import '../support/env.dart';
import 'support.dart';

/// A page with one button that pushes [page] and keeps what it returns.
class Pusher extends StatelessWidget {
  final Widget page;
  final void Function(Object? r) onResult;
  const Pusher(this.page, this.onResult, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('push'),
            onPressed: () async => onResult(await Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (c) => page))),
            child: const Text('go'),
          ),
        ),
      );
}

void main() {
  late TestDevice dev;
  setUp(() async => dev = await freshArea());
  tearDown(() {
    LegadoPlatform.resetForTests();
    dev.delete();
  });

  test('address bar: urls load, bare domains get https, words are searched', () {
    expect(addressToUrl('https://a.b/c'), 'https://a.b/c');
    expect(addressToUrl('m.baidu.com'), 'https://m.baidu.com');
    expect(addressToUrl('example.com:8080/x'), 'https://example.com:8080/x');
    expect(addressToUrl('斗破 苍穹'), '$webSearchUrl${Uri.encodeQueryComponent('斗破 苍穹')}');
    expect(jsResultToString('"a\\"b"'), 'a"b');
    expect(jsResultToString('null'), '');
    expect(jsResultToString(12), '12');
  });

  testWidgets('webview: java.webView mode returns the script result and keeps the page cookies', (t) async {
    Object? result = 'none';
    await t.pumpWidget(app(Pusher(const WebviewPage(url: 'https://site.test/a', js: 'getData()', autoReturn: true), (r) => result = r)));
    WebEngine.create = () => FakeWebController()
      ..evalResults['getData()'] = 'DATA'
      ..cookieText = 'sid=42';
    await act(t, () => t.tap(find.byKey(const Key('push'))));
    await idleUntil(t, () => result != 'none');
    expect(result, 'DATA');
    expect(CookieStore.getCookie('https://site.test/a'), 'sid=42');
    final c = FakeWebController.created.single;
    expect(c.loads, ['https://site.test/a']);
  });

  testWidgets('webview: an override regex closes the page with the matching url; ✓ returns the page source', (t) async {
    Object? result = 'none';
    await t.pumpWidget(app(Pusher(const WebviewPage(url: 'https://site.test/p', overrideUrlRegex: r'play\?id=\d+'), (r) => result = r)));
    await act(t, () => t.tap(find.byKey(const Key('push'))));
    await t.pumpAndSettle();
    final c = FakeWebController.created.single;
    expect(await c.navigate('https://site.test/next'), isTrue);
    expect(await c.navigate('https://cdn.test/play?id=7'), isFalse);
    await idleUntil(t, () => result != 'none');
    expect(result, 'https://cdn.test/play?id=7');

    result = 'none';
    await act(t, () => t.tap(find.byKey(const Key('push'))));
    await t.pumpAndSettle();
    final c2 = FakeWebController.created.last
      ..cookieText = 'k=v'
      ..evalResults['outerHTML'] = '<html>page</html>';
    await act(t, () => t.tap(find.byKey(const Key('webview_confirm'))));
    await idleUntil(t, () => result != 'none');
    expect(result, '<html>page</html>');
    expect(c2.scripts, contains('document.cookie'));
    expect(CookieStore.getCookie('https://site.test/p'), 'k=v');
  });

  testWidgets('navigation policy: web schemes load, import links go to the importer', (t) async {
    Uri? imported;
    importLinkHandler = (c, u) async => imported = u;
    await t.pumpWidget(app(const Scaffold(body: Text('x'))));
    final ctx = t.element(find.text('x'));
    late bool a, b;
    await act(t, () async {
      a = await webNavigationPolicy(ctx, 'https://ok.test');
      b = await webNavigationPolicy(ctx, 'legado://import/bookSource?src=https%3A%2F%2Fs.test%2Fs.json');
    });
    expect(a, isTrue);
    expect(b, isFalse);
    expect(imported?.queryParameters['src'], 'https://s.test/s.json');
    importLinkHandler = null;
  });

  testWidgets('engine hooks: java.webView pushes the web page on the root navigator and returns its result', (t) async {
    SourcesArea.installEngineHooks();
    await t.pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('home'))));
    WebEngine.create = () => FakeWebController()..evalResults['outerHTML'] = '<p>src</p>';
    String? got;
    await act(t, () async {
      unawaited(LegadoPlatform.webView!(url: 'https://hook.test/').then((v) => got = v));
    });
    await idleUntil(t, () => got != null);
    expect(got, '<p>src</p>');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('browser: bookmark start page, star, UA setting', (t) async {
    await t.runAsync(() => Chromemarks.load());
    await t.pumpWidget(app(const ChromePage()));
    await idle(t);
    expect(find.text('搜索或输入网址'), findsOneWidget);
    expect(find.text('源仓库'), findsOneWidget);
    expect(find.text('bing'), findsOneWidget);
    await act(t, () => t.tap(find.text('bing')));
    final c = FakeWebController.created.single;
    expect(c.loads, ['https://www.bing.com/']);
    // star: already a bookmark -> removed, again -> added
    await act(t, () => t.tap(find.byKey(const Key('chrome_star'))));
    await idleUntil(t, () => Toast.log.contains('已从收藏夹移除'));
    expect(Chromemarks.contains('https://www.bing.com/'), isFalse);
    expect(Toast.log, contains('已从收藏夹移除'));
    await act(t, () => t.tap(find.byKey(const Key('chrome_star'))));
    await idleUntil(t, () => Toast.log.contains('已添加到收藏夹'));
    expect(Chromemarks.contains('https://www.bing.com/'), isTrue);
    expect(Toast.log, contains('已添加到收藏夹'));
    // menu -> UA设置 -> iPhone
    await act(t, () => t.tap(find.byKey(const Key('chrome_menu'))));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.text('UA设置')));
    await t.pumpAndSettle();
    await t.tap(find.text('iPhone'));
    await t.pump();
    await act(t, () => t.tap(find.text('确定')));
    await idle(t);
    expect(Storage.getInt('userAgentType'), UAType.iphone.index);
    expect(c.userAgent, UAType.iphone.ua);
    expect(Toast.log, contains('UA设置已应用,重新打开页面后生效'));
  });

  testWidgets('bookmark manager: edit and delete', (t) async {
    await t.runAsync(() => Chromemarks.load());
    await t.pumpWidget(app(const BookmarkManagerPage()));
    await idle(t);
    expect(find.text('百度'), findsOneWidget);
    await act(t, () => t.tap(find.byType(PopupMenuButton<String>).at(2)));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.text('编辑').last));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('bm_name')), '百度一下');
    await act(t, () => t.tap(find.byKey(const Key('bm_save'))));
    await idleUntil(t, () => Toast.log.contains('书签已更新'));
    expect(Chromemarks.bookmarks.any((b) => b.title == '百度一下'), isTrue);
    await act(t, () => t.tap(find.byType(PopupMenuButton<String>).first));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.text('删除').last));
    await t.pumpAndSettle();
    await act(t, () => t.tap(find.text('删除').last));
    await idleUntil(t, () => Toast.log.contains('已删除书签'));
    expect(Chromemarks.bookmarks.length, 3);
  });

  testWidgets('scanner fallback: manual url, non-urls rejected', (t) async {
    Object? result = 'none';
    await t.pumpWidget(app(Pusher(const MobileScannerPage(), (r) => result = r)));
    await t.tap(find.byKey(const Key('push')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('scanner_note')), findsOneWidget);
    await t.enterText(find.byKey(const Key('scanner_input')), 'abc');
    await t.tap(find.byKey(const Key('scanner_ok')));
    await t.pump();
    expect(find.text('检测到的二维码不是有效的URL: abc'), findsOneWidget);
    await t.enterText(find.byKey(const Key('scanner_input')), 'https://q.test/s.json');
    await t.tap(find.byKey(const Key('scanner_ok')));
    await t.pumpAndSettle();
    expect(result, 'https://q.test/s.json');
  });

  testWidgets('scanner: a photo from the library is analysed (url accepted, other text rejected)', (t) async {
    final codes = <String>['plain text'];
    final pick = MobileScannerPage.pickImagePath;
    addTearDown(() => MobileScannerPage.pickImagePath = pick);
    MobileScannerPage.pickImagePath = () async => '/tmp/qr.png';
    MobileScannerPage.analyzeImage = (c, path) async => path == '/tmp/qr.png' ? codes : const [];
    addTearDown(() => MobileScannerPage.analyzeImage = null);
    Object? result = 'none';
    await t.pumpWidget(app(Pusher(const MobileScannerPage(), (r) => result = r)));
    await t.tap(find.byKey(const Key('push')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scanner_pick')));
    await t.pump();
    await t.pump();
    expect(find.text('检测到的二维码不是有效的URL: plain text'), findsOneWidget);
    codes
      ..clear()
      ..add('https://q.test/rss.json');
    await t.pump(const Duration(seconds: 3));
    await t.tap(find.byKey(const Key('scanner_pick')));
    await t.pumpAndSettle();
    expect(result, 'https://q.test/rss.json');
  });

  // last: the search page reads its history while building (see support.dart `act`)
  testWidgets('browser address bar: search page, words go to the search engine and into the history', (t) async {
    await t.runAsync(() => Chromemarks.load());
    await t.pumpWidget(app(const ChromePage()));
    await idle(t);
    await act(t, () => t.tap(find.byKey(const Key('chrome_address'))));
    await idle(t);
    expect(find.text('暂无搜索历史'), findsOneWidget);
    await t.enterText(find.byKey(const Key('web_search_input')), '斗破');
    await act(t, () => t.testTextInput.receiveAction(TextInputAction.go));
    await idleUntil(t, () => FakeWebController.created.isNotEmpty && FakeWebController.created.first.loads.isNotEmpty);
    expect(FakeWebController.created.first.loads.single, '$webSearchUrl${Uri.encodeQueryComponent('斗破')}');
  });
}
