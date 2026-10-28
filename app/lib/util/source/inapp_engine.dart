// util/source/inapp_engine.dart — `InAppWebViewEngineAdapter`: [SourceJsEngine] over flutter_inappwebview's HeadlessInAppWebView (the
// original's web view package; class 1229 adapts an `InAppWebViewController`, 0xfbf804 `evaluateJavascript`). One instance runs one
// book source page (util/source/run.dart) or one background page of the `webview` handler (util/source/webview.dart).
//
// Also the bridge between the app's cookie store (util/legado/cookie_jar.dart, what the `http` handler and the engine send) and the
// platform cookie store the web views use ([WebCookies]); on iOS every WKWebView of the app shares that store, so cookies a login
// page sets are visible to the source page and the other way round.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../legado/cookie_jar.dart';
import 'js_engine.dart';

class InAppWebViewEngineAdapter extends SourceJsEngine {
  final SourceJsEngineOptions options;
  HeadlessInAppWebView? _view;
  InAppWebViewController? _c;
  Completer<InAppWebViewController>? _created;
  final Map<String, JsHandler> _handlers = {};
  bool _disposed = false;

  InAppWebViewEngineAdapter([this.options = const SourceJsEngineOptions()]);

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        useShouldOverrideUrlLoading: options.intercept,
        useOnLoadResource: options.intercept,
        useShouldInterceptAjaxRequest: options.interceptAjax,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        sharedCookiesEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        isInspectable: kDebugMode,
        userAgent: options.userAgent,
      );

  Future<InAppWebViewController> _controller() {
    if (_disposed) return Future.error(StateError('页面已销毁'));
    final c = _c;
    if (c != null) return Future.value(c);
    final pending = _created;
    if (pending != null) return pending.future;
    final created = _created = Completer<InAppWebViewController>();
    final view = HeadlessInAppWebView(
      initialSettings: _settings,
      onWebViewCreated: (c) {
        _c = c;
        _handlers.forEach((name, h) => c.addJavaScriptHandler(handlerName: name, callback: (args) => h(args)));
        if (!created.isCompleted) created.complete(c);
      },
      onLoadStart: (c, url) => onLoadStart?.call(url?.toString() ?? ''),
      onLoadStop: (c, url) => onLoadStop?.call(url?.toString() ?? ''),
      onReceivedError: (c, request, error) => onLoadError?.call(request.url.toString()),
      onReceivedHttpError: (c, request, response) => onLoadError?.call(request.url.toString()),
      onAjaxReadyStateChange: (c, ajax) async {
        onAjax?.call(AjaxEvent(ajax.url?.toString() ?? '', ajax.readyState?.toValue() ?? 0, ajax.responseText));
        return null;
      },
      onConsoleMessage: (c, m) => onConsole?.call(m.message),
      shouldOverrideUrlLoading: (c, action) async {
        final f = onNavigate;
        final url = action.request.url?.toString() ?? '';
        if (f == null || url.isEmpty) return NavigationActionPolicy.ALLOW;
        return await f(url) ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
      },
      onLoadResource: (c, r) {
        final u = r.url?.toString();
        if (u != null) onResource?.call(u);
      },
    );
    _view = view;
    view.run().catchError((Object e) {
      if (!created.isCompleted) created.completeError(e);
    });
    return created.future;
  }

  @override
  void addJavaScriptHandler(String name, JsHandler handler) {
    _handlers[name] = handler;
    _c?.addJavaScriptHandler(handlerName: name, callback: (args) => handler(args));
  }

  @override
  Future<void> loadData(String html, {required String baseUrl}) async {
    final c = await _controller();
    await c.loadData(data: html, baseUrl: WebUri(baseUrl), mimeType: 'text/html', encoding: 'utf8');
  }

  @override
  Future<void> loadUrl(String url, {Map<String, String>? headers, String? body}) async {
    final c = await _controller();
    await c.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(url),
        method: body == null ? 'GET' : 'POST',
        body: body == null ? null : Uint8List.fromList(utf8.encode(body)),
        headers: headers,
      ),
    );
  }

  @override
  Future<Object?> evaluateJavascript(String source) async {
    final c = await _controller();
    return c.evaluateJavascript(source: source);
  }

  @override
  bool get disposed => _disposed;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final v = _view;
    _view = null;
    _c = null;
    final pending = _created;
    if (pending != null && !pending.isCompleted) pending.completeError(StateError('页面已销毁'));
    try {
      await v?.dispose();
    } catch (e) {
      debugPrint('销毁 webview 失败: $e');
    }
  }
}

/// Copies cookies between the app's [CookieStore] and the platform web-view cookie store. Hooks so that host tests run without a
/// web view.
abstract class WebCookies {
  /// Puts the stored cookies of [url] into the web views (before a page of that site loads).
  static Future<void> Function(String url) push = _push;

  /// Takes every cookie the web views hold for [url] (HttpOnly ones too) into the store (after a page loaded).
  static Future<void> Function(String url) pull = _pull;

  /// Takes every cookie of every site the web views know into the store (when a login / browser page closes: the page may have
  /// logged in through requests to other hosts than its own, e.g. an API server of the source). iOS / macOS only.
  static Future<void> Function() pullAll = _pullAll;

  static Future<void> _push(String url) async {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty || !u.scheme.startsWith('http')) return;
    final stored = CookieStore.cookieToMap(CookieStore.getCookie(url));
    if (stored.isEmpty) return;
    final m = CookieManager.instance();
    for (final e in stored.entries) {
      try {
        await m.setCookie(url: WebUri(url), name: e.key, value: e.value);
      } catch (err) {
        debugPrint('注入cookie失败:$err');
      }
    }
  }

  static Future<void> _pullAll() async {
    if (defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      final byHost = <String, List<String>>{};
      for (final c in await CookieManager.instance().getAllCookies()) {
        var host = (c.domain ?? '').trim();
        if (host.startsWith('.')) host = host.substring(1);
        if (host.isEmpty || c.name.isEmpty) continue;
        (byHost[host] ??= []).add('${c.name}=${c.value}');
      }
      byHost.forEach((host, pairs) => CookieStore.replaceCookie('https://$host', pairs.join(';')));
    } catch (e) {
      debugPrint('读取webview cookie失败:$e');
    }
  }

  static Future<void> _pull(String url) async {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty || !u.scheme.startsWith('http')) return;
    try {
      final list = await CookieManager.instance().getCookies(url: WebUri(url));
      if (list.isEmpty) return;
      CookieStore.replaceCookie(url, list.map((c) => '${c.name}=${c.value}').join(';'));
    } catch (e) {
      debugPrint('读取webview cookie失败:$e');
    }
  }
}
