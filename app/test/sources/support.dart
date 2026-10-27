// Shared helpers of the sources / RSS / web tests: a fake web view, a widget-test idle loop that lets real file / socket IO finish,
// fixtures, and the per-test reset of the area's static state.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/pages/source/source_setting.dart';
import 'package:newread/pages/web/web_engine.dart';
import 'package:newread/qread/qread.dart';
import 'package:newread/qread/rssdata.dart';
import 'package:newread/util/http.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/toast.dart';
import 'package:newread/util/webbook/util/cache_manager.dart';

import '../support/env.dart';

/// A web view that records what the page asked for. [evalResults] answers `evaluate` by script (substring match), [pageCookie]
/// is what `document.cookie` gives.
class FakeWebController extends QWebController {
  static final List<FakeWebController> created = [];
  final List<String> loads = [];
  final List<String> scripts = [];
  final Map<String, String> evalResults = {};
  final Map<String, String> cookies = {};
  String cookieText = '';
  String? userAgent;
  bool js = true;
  bool cleared = false;
  final List<String> history = [];
  int _pos = -1;

  FakeWebController() {
    created.add(this);
  }

  /// Simulates the page reaching [u] (navigation policy first, then started / finished callbacks).
  Future<bool> navigate(String u) async {
    final ok = await (onNavigate?.call(u) ?? true);
    if (!ok) return false;
    _finish(u);
    return true;
  }

  void _finish(String u) {
    if (_pos < history.length - 1) history.removeRange(_pos + 1, history.length);
    history.add(u);
    _pos = history.length - 1;
    url.value = u;
    progress.value = 100;
    onPageStarted?.call(u);
    onPageFinished?.call(u);
  }

  @override
  Future<void> loadUrl(String url, {Map<String, String>? headers}) async {
    loads.add(url);
    _finish(url);
  }

  @override
  Future<void> loadHtml(String html, {String? baseUrl}) async {
    loads.add('html:${baseUrl ?? ''}:$html');
    _finish(baseUrl ?? 'about:blank');
  }

  @override
  Future<String> evaluate(String js) async {
    scripts.add(js);
    if (js == 'document.cookie') return cookieText;
    for (final e in evalResults.entries) {
      if (js.contains(e.key)) return e.value;
    }
    return '';
  }

  @override
  Future<bool> canGoBack() async => _pos > 0;
  @override
  Future<bool> canGoForward() async => _pos < history.length - 1;
  @override
  Future<void> goBack() async {
    if (_pos > 0) url.value = history[--_pos];
  }

  @override
  Future<void> goForward() async {
    if (_pos < history.length - 1) url.value = history[++_pos];
  }

  @override
  Future<void> reload() async => onPageFinished?.call(url.value);
  @override
  Future<void> setUserAgent(String? ua) async => userAgent = ua;
  @override
  Future<void> setJavaScript(bool on) async => js = on;
  @override
  Future<void> setCookie(String url, String cookie) async => cookies[url] = cookie;
  @override
  Future<bool> clearCookies() async => cleared = true;
  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: Key('fake_web'));
}

/// Lets real IO (files, sockets) complete inside a widget test: alternates real waits and pumps.
Future<void> idle(WidgetTester t, {int rounds = 12, int ms = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    // also advance the fake clock: code started in the fake zone may wait on timers (rate limits, retries)
    await t.pump(Duration(milliseconds: ms));
  }
}

/// Runs a tap (or any action whose handler does file IO) in the real async zone, then idles.
///
/// Why: the data managers serialise through static `Lock`s whose tail future keeps the zone it was created in. A future created
/// in a widget test's fake-async zone is never completed once that test is over, so every later test that touches the same lock
/// would hang. Handlers started inside `runAsync` create their futures in a zone that delegates to the root zone. For the same
/// reason widget tests preload the stores they show (`t.runAsync(() => Sourcedata.load())`) before `pumpWidget`, and open popup
/// menus / sheets through [act] too (their `onSelected` runs in the zone the menu was opened in).
Future<void> act(WidgetTester t, Future<void> Function() action, {int rounds = 12}) async {
  await t.runAsync(() async {
    await action();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await idle(t, rounds: rounds);
}

/// Idles until [done] holds (or fails after [max] rounds).
Future<void> idleUntil(WidgetTester t, bool Function() done, {int max = 400, int ms = 10}) async {
  for (var i = 0; i < max && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    // also advance the fake clock: code started in the fake zone may wait on timers (rate limits, retries)
    await t.pump(Duration(milliseconds: ms));
  }
  expect(done(), isTrue, reason: 'condition not reached; toasts: ${Toast.log}');
}

Widget app(Widget home) => GetMaterialApp(home: home);

String fixture(String name) => File('test/fixtures/sources/$name').readAsStringSync();

/// A fresh device plus the area's statics reset; returns the device (delete it in tearDown).
Future<TestDevice> freshArea() async {
  final d = await newDevice();
  // the widget-test binding answers every HttpClient request with 400; these tests talk to local fake servers
  HttpOverrides.global = null;
  // a fresh client per test: pooled connections keep the zone of the test that opened them
  AppHttp.reset();
  JsEngines.useDart();
  CookieStore.resetForTests();
  CacheManager.resetForTests();
  SourceApi.cache.clear();
  Qread.resetForTests();
  QRssSources.reset();
  Toast.log.clear();
  Toast.sink = (m, e) {};
  FakeWebController.created.clear();
  WebEngine.create = FakeWebController.new;
  SourceImport.pickFileText = () async => null;
  return d;
}
