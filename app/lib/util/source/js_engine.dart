// util/source/js_engine.dart — `SourceJsEngine`: what the 时光源 runtime needs from a web view. The page talks to the app through
// `window.flutter_inappwebview.callHandler(name, ...args)` ([addJavaScriptHandler]); the app runs code in the page
// ([evaluateJavascript]) and learns when a page has loaded ([onLoadStop]).
//
// Original: abstract `SourceJsEngine` with two implementations, `QuickjsSourceEngine` (2.2.1026 runs book sources in QuickJS +
// domino, 0xe894b4 `QuickJS loadData`) and `InAppWebViewEngineAdapter` (flutter_inappwebview, used by the foreground browser pages).
// The replica runs book sources in a HeadlessInAppWebView (the original's earlier engine, which the editor's help text still
// describes: 运行书源其实就是拿webview加载书源html代码并执行固定的js函数), see inapp_engine.dart. The plugin stays behind this
// interface so the runtime is tested on the host with a fake engine.
import 'dart:async';

import 'inapp_engine.dart';

/// A `callHandler` target: receives the JavaScript arguments, its (awaited) result goes back to the page JSON-encoded.
typedef JsHandler = FutureOr<Object?> Function(List<dynamic> args);

/// Something handlers can be registered on (a headless engine or a foreground web view).
abstract class JsHandlerSink {
  void addJavaScriptHandler(String name, JsHandler handler);
}

/// Options of a new engine.
class SourceJsEngineOptions {
  /// Report every navigation to [SourceJsEngine.onNavigate] and every loaded resource to [SourceJsEngine.onResource].
  final bool intercept;

  /// Report the page's XMLHttpRequests to [SourceJsEngine.onAjax] (`useShouldInterceptAjaxRequest`).
  final bool interceptAjax;

  /// User agent of the web view (null = the platform default).
  final String? userAgent;

  const SourceJsEngineOptions({this.intercept = false, this.interceptAjax = false, this.userAgent});
}

/// One `onAjaxReadyStateChange` of a page: the request url, its `readyState` (4 = done) and, when done, the answer text.
class AjaxEvent {
  final String url;
  final int readyState;
  final String? responseText;

  const AjaxEvent(this.url, this.readyState, [this.responseText]);
}

abstract class SourceJsEngine implements JsHandlerSink {
  /// Creates the engine of a book source / background page; tests install a fake.
  static SourceJsEngine Function(SourceJsEngineOptions options) create = (o) => InAppWebViewEngineAdapter(o);

  /// A page (main frame) started / finished loading.
  void Function(String url)? onLoadStart;
  void Function(String url)? onLoadStop;

  /// A request of the page failed (`onReceivedError` / `onReceivedHttpError`), with [SourceJsEngineOptions.intercept].
  void Function(String url)? onLoadError;

  /// An XMLHttpRequest of the page changed state, with [SourceJsEngineOptions.interceptAjax].
  void Function(AjaxEvent event)? onAjax;

  /// `console.*` output of the page.
  void Function(String message)? onConsole;

  /// Asked before a navigation when created with [SourceJsEngineOptions.intercept]; false cancels it.
  FutureOr<bool> Function(String url)? onNavigate;

  /// A resource (script, xhr, media, …) was loaded, with [SourceJsEngineOptions.intercept].
  void Function(String url)? onResource;

  /// Loads [html] as a page whose address is [baseUrl] (relative links, cookies and storage belong to that origin).
  Future<void> loadData(String html, {required String baseUrl});

  /// Loads [url] (a POST when [body] is given).
  Future<void> loadUrl(String url, {Map<String, String>? headers, String? body});

  /// Runs [source] in the page; the value of the last expression comes back (not awaited when it is a Promise).
  Future<Object?> evaluateJavascript(String source);

  bool get disposed;

  Future<void> dispose();
}
