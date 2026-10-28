// pages/web/source_webview.dart — the foreground browser of 时光源: the original opens its `WebviewPage` (pages/web/webview.dart,
// InAppWebView + `InAppWebViewEngineAdapter` 0x5e88b8) from the page handlers startBrowser 0xe8d420,
// startBrowserWithShouldOverrideUrlLoading 0xe8d1fc, startBrowserDp* 0xe8cf5c / 0xe8d0a0 / 0xe8cde4 (a half-height sheet for 段评),
// from the login (`getloginurl()` returning an http url) and from discovery entries of type 1. The page gets the source's bridge:
// the shared handlers of util/source/baswebview.dart (`cache.*` of that source, `cookie.*`, `http`, …) plus `back` (only foreground
// pages have it) and `refreshExplore`; with `overrideUrlLoading` every main-frame navigation is first given to the source page's
// `shouldOverrideUrlLoading(url)`. Cookies: the app's store goes into the web view before the first load and every loaded page's
// cookies (HttpOnly too) come back into the store, so the source's `http` requests carry the login.
//
// Not covered by host tests (a platform web view); the hooks that open it are in pages/web/web_hooks.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Storage;

import '../../storage/storage.dart';
import '../../util/source/baswebview.dart';
import '../../util/source/inapp_engine.dart';
import '../../util/source/js_engine.dart';
import '../../util/source/run.dart';
import 'webview.dart' show importFileUrl, isImportFileUrl, webNavigationPolicy;

class SourceWebviewPage extends StatefulWidget {
  final SourceBrowserRequest request;

  /// Shown inside a bottom sheet (no app bar back gesture handling of its own).
  final bool sheet;

  const SourceWebviewPage({super.key, required this.request, this.sheet = false});

  /// Opens [r] as a page, or as a half-height sheet when [SourceBrowserRequest.half]; the result is the final page source.
  static Future<String?> open(NavigatorState nav, SourceBrowserRequest r) {
    if (!r.half) return nav.push<String>(MaterialPageRoute(builder: (c) => SourceWebviewPage(request: r)));
    return showModalBottomSheet<String>(
      context: nav.context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => SizedBox(height: MediaQuery.sizeOf(c).height * 0.6, child: SourceWebviewPage(request: r, sheet: true)),
    );
  }

  @override
  State<SourceWebviewPage> createState() => _SourceWebviewPageState();
}

class _SourceWebviewPageState extends State<SourceWebviewPage> implements JsHandlerSink {
  InAppWebViewController? _c;
  final Map<String, JsHandler> _handlers = {};
  final ValueNotifier<String> _title = ValueNotifier('');
  final ValueNotifier<double> _progress = ValueNotifier(0);
  bool _done = false;
  bool _ready = false;
  bool _firstNavigation = true;
  late final Map<String, String> _headers;
  String? _ua;

  SourceBrowserRequest get r => widget.request;

  @override
  void addJavaScriptHandler(String name, JsHandler handler) {
    _handlers[name] = handler;
    _c?.addJavaScriptHandler(handlerName: name, callback: (a) => handler(a));
  }

  @override
  void initState() {
    super.initState();
    _headers = Map<String, String>.from(r.headers);
    final uaKey = _headers.keys.firstWhere((k) => k.toLowerCase() == 'user-agent', orElse: () => '');
    if (uaKey.isNotEmpty) _ua = _headers.remove(uaKey);
    final s = r.source;
    if (s != null) {
      SourceHandlers.register(this, s, needhttp: true);
      addJavaScriptHandler('refreshExplore', (a) async {
        await Storage.delete(Baswebview.exploreKey(s.bookSourceUrl));
        ExploreRefresh.notify(s.bookSourceUrl);
        return '';
      });
    }
    addJavaScriptHandler('back', (a) async {
      await _back();
      return true;
    });
    addJavaScriptHandler('CookieJar', (a) => null);
    addJavaScriptHandler('log', (a) {
      debugPrint('webview log: ${a.isEmpty ? '' : jsArg(a.first)}');
      return true;
    });
    addJavaScriptHandler('text', (a) => true);
    _prepare();
  }

  Future<void> _prepare() async {
    await WebCookies.push(r.url);
    if (mounted) setState(() => _ready = true);
  }

  Future<NavigationActionPolicy> _shouldOverride(InAppWebViewController c, NavigationAction action) async {
    final url = action.request.url?.toString() ?? '';
    if (url.isEmpty) return NavigationActionPolicy.ALLOW;
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase() ?? '';
    if (!const {'http', 'https', 'about', 'data', 'blob', 'javascript', 'file'}.contains(scheme)) {
      return mounted && await webNavigationPolicy(context, url) ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
    }
    final first = _firstNavigation;
    _firstNavigation = false;
    // a link to a source / config file is imported instead of shown as raw text (see isImportFileUrl)
    if (action.isForMainFrame && !(first && url == r.url) && isImportFileUrl(url)) {
      await importFileUrl(url);
      return NavigationActionPolicy.CANCEL;
    }
    final s = r.source;
    if (r.overrideUrlLoading && s != null && action.isForMainFrame && !(first && url == r.url)) {
      try {
        final ok = await (await SourceRun.of(s)).shouldOverrideUrlLoading(url);
        return ok ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL;
      } catch (e) {
        debugPrint('shouldOverrideUrlLoading: $e');
      }
    }
    return NavigationActionPolicy.ALLOW;
  }

  Future<String> _html() async {
    try {
      return jsArg(await _c?.evaluateJavascript(source: 'document.documentElement.outerHTML'));
    } catch (_) {
      return '';
    }
  }

  Future<void> _finish() async {
    if (_done) return;
    _done = true;
    // closing must always work, even when the page does not answer (hung script, suspended web process)
    const wait = Duration(seconds: 3);
    final url = (await _c?.getUrl().timeout(wait, onTimeout: () => null))?.toString() ?? r.url;
    await WebCookies.pull(url).timeout(wait, onTimeout: () {});
    await WebCookies.pullAll().timeout(wait, onTimeout: () {});
    final html = await _html().timeout(wait, onTimeout: () => '');
    if (mounted) Navigator.of(context).pop(html);
  }

  Future<void> _back() async {
    final c = _c;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
      return;
    }
    await _finish();
  }

  @override
  void dispose() {
    _title.dispose();
    _progress.dispose();
    _error.dispose();
    super.dispose();
  }

  Widget _web() {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final html = r.html;
    return InAppWebView(
      initialUrlRequest: html == null ? URLRequest(url: WebUri(r.url), headers: _headers) : null,
      initialData: html == null ? null : InAppWebViewInitialData(data: html, baseUrl: WebUri(r.url.isEmpty ? 'about:blank' : r.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        sharedCookiesEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        userAgent: _ua,
      ),
      onWebViewCreated: (c) {
        _c = c;
        _handlers.forEach((name, h) => c.addJavaScriptHandler(handlerName: name, callback: (a) => h(a)));
      },
      shouldOverrideUrlLoading: _shouldOverride,
      onProgressChanged: (c, p) => _progress.value = p / 100,
      onTitleChanged: (c, t) => _title.value = t ?? '',
      onLoadStart: (c, url) {
        if (_error.value != null) _error.value = null;
      },
      onLoadStop: (c, url) async {
        _progress.value = 1;
        if (url != null) await WebCookies.pull(url.toString());
      },
      // a failed main-frame load is shown instead of a silent white page (and logged for debugging)
      onReceivedError: (c, request, error) {
        if (request.isForMainFrame == false) return;
        debugPrint('source browser: ${request.url} ${error.type} ${error.description}');
        _progress.value = 1;
        _error.value = '页面加载失败：${error.description}\n${request.url}';
      },
    );
  }

  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);

  // fit: expand — the web view must get the whole body (a 0x0 platform view is treated as hidden: WebKit stops drawing it and
  // pauses its scripts)
  Widget _body() => Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: _web()),
        ValueListenableBuilder<String?>(
          valueListenable: _error,
          builder: (c, e, _) => e == null
              ? const SizedBox.shrink()
              : Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(c).colorScheme.surface,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(e, key: const Key('source_browser_error'), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          OutlinedButton(onPressed: () => _c?.reload(), child: const Text('重试')),
                        ]),
                      ),
                    ),
                  ),
                ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final bar = AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(tooltip: '关闭', icon: const Icon(Icons.close), onPressed: _finish),
      titleSpacing: 0,
      title: ValueListenableBuilder<String>(
        valueListenable: _title,
        builder: (c, t, _) => Text(r.title.isNotEmpty ? r.title : (t.isEmpty ? '书源' : t), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      actions: [
        IconButton(tooltip: '返回', icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: _back),
        IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: () => _c?.reload()),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: ValueListenableBuilder<double>(
          valueListenable: _progress,
          builder: (c, p, _) => p >= 1 ? const SizedBox(height: 2) : LinearProgressIndicator(value: p, minHeight: 2),
        ),
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(appBar: bar, body: _body()),
    );
  }
}
