// pages/web/web_engine.dart — not a file of the original. The original's browser pages run on flutter_inappwebview
// (`InAppWebView` + `InAppWebViewController`); the replica uses webview_flutter behind this small interface so that the pages
// (chrome_inapp, webview, rss_webview, web_page) can be driven by a fake controller in unit tests on the Windows host.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// What the pages need from a web view.
abstract class QWebController {
  /// Loading progress 0..100.
  final ValueNotifier<int> progress = ValueNotifier<int>(0);
  final ValueNotifier<String> url = ValueNotifier<String>('');
  final ValueNotifier<String> title = ValueNotifier<String>('');

  /// Asked before a navigation; false blocks it (the page handles non-http schemes, import links, override regexes).
  FutureOr<bool> Function(String url)? onNavigate;
  void Function(String url)? onPageStarted;
  void Function(String url)? onPageFinished;
  void Function(String message)? onConsole;

  Future<void> loadUrl(String url, {Map<String, String>? headers});
  Future<void> loadHtml(String html, {String? baseUrl});

  /// Runs [js] and gives the result as text (`''` for null / undefined).
  Future<String> evaluate(String js);
  Future<bool> canGoBack();
  Future<bool> canGoForward();
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> setUserAgent(String? ua);
  Future<void> setJavaScript(bool on);

  /// Puts `k=v; k2=v2` into the web view's cookie store for [url].
  Future<void> setCookie(String url, String cookie);

  /// The cookies the current page can see (`document.cookie`).
  Future<String> pageCookie() => evaluate('document.cookie');
  Future<bool> clearCookies();
  Widget build(BuildContext context);
  void dispose() {
    progress.dispose();
    url.dispose();
    title.dispose();
  }
}

abstract class WebEngine {
  /// Builds the controller every page uses; tests install a fake.
  static QWebController Function() create = () => FlutterWebController();
}

/// Normalises `runJavaScriptReturningResult` across platforms (Android JSON-encodes strings, iOS does not).
String jsResultToString(Object? v) {
  if (v == null) return '';
  if (v is String) {
    final s = v.trim();
    if (s == 'null' || s == 'undefined') return '';
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      try {
        final d = jsonDecode(s);
        if (d is String) return d;
      } catch (_) {}
    }
    return v;
  }
  return '$v';
}

/// webview_flutter implementation.
class FlutterWebController extends QWebController {
  late final WebViewController _c;
  final WebViewCookieManager _cookies = WebViewCookieManager();

  FlutterWebController() {
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => progress.value = p,
        onPageStarted: (u) {
          url.value = u;
          onPageStarted?.call(u);
        },
        onPageFinished: (u) async {
          url.value = u;
          progress.value = 100;
          title.value = (await _c.getTitle()) ?? '';
          onPageFinished?.call(u);
        },
        onUrlChange: (c) {
          if (c.url != null) url.value = c.url!;
        },
        onNavigationRequest: (r) async {
          final f = onNavigate;
          if (f == null) return NavigationDecision.navigate;
          return await f(r.url) ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
      ));
    try {
      _c.setOnConsoleMessage((m) => onConsole?.call(m.message));
    } catch (_) {}
  }

  @override
  Future<void> loadUrl(String url, {Map<String, String>? headers}) => _c.loadRequest(Uri.parse(url), headers: headers ?? const {});

  @override
  Future<void> loadHtml(String html, {String? baseUrl}) => _c.loadHtmlString(html, baseUrl: baseUrl);

  @override
  Future<String> evaluate(String js) async => jsResultToString(await _c.runJavaScriptReturningResult(js));

  @override
  Future<bool> canGoBack() => _c.canGoBack();

  @override
  Future<bool> canGoForward() => _c.canGoForward();

  @override
  Future<void> goBack() => _c.goBack();

  @override
  Future<void> goForward() => _c.goForward();

  @override
  Future<void> reload() => _c.reload();

  @override
  Future<void> setUserAgent(String? ua) => _c.setUserAgent(ua);

  @override
  Future<void> setJavaScript(bool on) => _c.setJavaScriptMode(on ? JavaScriptMode.unrestricted : JavaScriptMode.disabled);

  @override
  Future<void> setCookie(String url, String cookie) async {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return;
    for (final pair in cookie.split(';')) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      await _cookies.setCookie(WebViewCookie(name: pair.substring(0, i).trim(), value: pair.substring(i + 1).trim(), domain: u.host));
    }
  }

  @override
  Future<bool> clearCookies() => _cookies.clearCookies();

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _c);
}
