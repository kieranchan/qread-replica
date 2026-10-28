// pages/web/webview.dart — `WebviewPage`: the web page the book-source engine opens (source login, `java.startBrowser(Await)`,
// `java.webView`, captcha / Cloudflare pages) and that keeps the page cookies in sync with the engine's CookieStore.
//
// Original `_WebviewPageState` (build 0x5e6db8, InAppWebView 0x5e7f0c, onLoadStop 0xfd3430 `落点URL:` / `页面可见cookie:` /
// `store里的cookie:` / `!!window._cf_chl_opt` -> `检测到已经过了验证`, cookie save 0xfd1fac `回传 Cookie 中`, load 0xfd4220
// `开始加载页面` / `注入cookie成功:`, policy 0xfd293c (qread/yuedu/legado links, `外部跳转确认`), menu 0xfd5258 (delete / look /
// showlog / open), cookie dialog 0x5e9074, clear 0xfd5540 `是否清除当前网站的cookie？`, confirm `_handleConfirm` 0x5e9548).
// The JAVACLASS bridge the original injects (0xfd2544) is not ported: rule JavaScript runs in the Dart engine.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../service/app_links_service.dart';
import '../../util/legado/cookie_jar.dart';
import '../../util/toast.dart';
import 'web_engine.dart';

/// Schemes the app handles itself (source import links).
const Set<String> importSchemes = {'qread', 'yuedu', 'legado'};
const Set<String> _webSchemes = {'http', 'https', 'file', 'chrome', 'blob', 'data', 'javascript', 'about'};

/// Handles `legado://` / `yuedu://` / `qread://` import links; installed by the source manager (pages/source/source_setting.dart).
Future<void> Function(BuildContext context, Uri uri)? importLinkHandler;

/// A link to a source / config file (`http(s)://…/x.json`). Source sites link their files directly (e.g. 大灰狼's
/// `…/sy/download/轻悦时光app-….json`); a web view would only show the raw text (garbled when the server sends no charset).
bool isImportFileUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return false;
  String path;
  try {
    path = Uri.decodeComponent(u.path);
  } catch (_) {
    path = u.path;
  }
  return path.toLowerCase().endsWith('.json');
}

/// Downloads such a file and imports it by its content (sources, RSS, replace rules, TTS engines, TXT rules), the path of a
/// `qread://…?src=<url>` link (AppLinksService, 0xe6ad38).
Future<void> importFileUrl(String url) =>
    AppLinksService.handle(Uri(scheme: 'qread', host: 'import', queryParameters: {'src': url}));

/// The navigation policy of the browser pages (0xfcdba4 / 0xfd293c): web schemes load, import links go to the importer, every
/// other scheme asks `外部跳转确认` and is handed to the system. Returns true when the web view may load [url].
Future<bool> webNavigationPolicy(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || url == 'about:blank') return true;
  if (isImportFileUrl(url)) {
    await importFileUrl(url);
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme.isEmpty || _webSchemes.contains(scheme)) return true;
  if (importSchemes.contains(scheme)) {
    final h = importLinkHandler;
    if (h != null && context.mounted) await h(context, uri);
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('外部跳转确认'),
      content: Text('即将跳转到外部应用打开此链接：$url\n是否继续？'),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
      ],
    ),
  );
  if (ok == true) {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) Toast.show('打开失败');
    } catch (_) {
      Toast.show('打开失败');
    }
  }
  return false;
}

class WebviewPage extends StatefulWidget {
  final String url;
  final String title;

  /// HTML to show instead of loading [url] ([url] is then the base url).
  final String? html;
  final Map<String, String>? header;

  /// Script run when the page has loaded; with [autoReturn] its result closes the page (`java.webView`).
  final String? js;

  /// A navigation whose url matches closes the page and returns that url (`webViewGetSource` / `webViewGetOverrideUrl`).
  final String? sourceRegex;
  final String? overrideUrlRegex;

  /// Close by itself once [js] produced a result (background fetch for the engine).
  final bool autoReturn;

  /// Captcha mode: close by itself when the Cloudflare challenge is gone, returning the page source.
  final bool captcha;

  const WebviewPage({
    super.key,
    required this.url,
    this.title = '',
    this.html,
    this.header,
    this.js,
    this.sourceRegex,
    this.overrideUrlRegex,
    this.autoReturn = false,
    this.captcha = false,
  });

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  late final QWebController _c;
  final List<String> _log = [];
  bool _done = false;
  bool _challengeSeen = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _c = WebEngine.create();
    _c.onNavigate = _onNavigate;
    _c.onPageFinished = _onLoadStop;
    _c.onConsole = (m) => _addLog('JS 日志 [$m]');
    if (widget.autoReturn) _timeout = Timer(const Duration(seconds: 60), () => _finish(null));
    _load();
  }

  void _addLog(String s) {
    _log.add(s);
    debugPrint(s);
  }

  /// 0xfd4220: user agent from the header, cookies of the store pushed into the web view, then load.
  Future<void> _load() async {
    final url = widget.url;
    _addLog('开始加载页面:$url');
    final headers = Map<String, String>.from(widget.header ?? const {});
    final ua = headers.remove('User-Agent') ?? headers.remove('user-agent');
    try {
      if (ua != null && ua.isNotEmpty) {
        await _c.setUserAgent(ua);
        _addLog('设置 ua：$ua');
      }
    } catch (e) {
      _addLog('修改ua错误:$e');
    }
    final cookie = CookieStore.getCookie(url);
    if (cookie.isNotEmpty) {
      try {
        await _c.setCookie(url, cookie);
        _addLog('注入cookie成功:$cookie');
      } catch (e) {
        _addLog('注入cookie失败:$e');
      }
    }
    if (widget.html != null) {
      await _c.loadHtml(widget.html!, baseUrl: url);
    } else if (url.isNotEmpty) {
      await _c.loadUrl(url, headers: headers);
    }
  }

  Future<bool> _onNavigate(String url) async {
    _addLog('shouldOverrideUrlLoading:$url');
    final o = widget.overrideUrlRegex;
    if (o != null && o.isNotEmpty && RegExp(o).hasMatch(url)) {
      _finish(url);
      return false;
    }
    final s = widget.sourceRegex;
    if (s != null && s.isNotEmpty && RegExp(s).hasMatch(url)) {
      _finish(url);
      return false;
    }
    if (!mounted) return false;
    return webNavigationPolicy(context, url);
  }

  /// 0xfd3430.
  Future<void> _onLoadStop(String url) async {
    _addLog('落点URL:$url');
    await _saveCookie(url);
    if (widget.captcha) {
      final cf = await _safeEval('!!window._cf_chl_opt');
      if (cf == 'true') {
        _challengeSeen = true;
      } else if (_challengeSeen) {
        Toast.show('检测到已经过了验证');
        _finish(await _safeEval('document.documentElement.outerHTML'));
        return;
      }
    }
    final js = widget.js;
    if (widget.autoReturn) {
      final r = await _safeEval(js == null || js.isEmpty ? 'document.documentElement.outerHTML' : js);
      // a script that returns nothing yet is retried on the next page load (Legado's webView polling)
      if (r.isNotEmpty) _finish(r);
    } else if (js != null && js.isNotEmpty) {
      await _safeEval(js);
    }
  }

  Future<String> _safeEval(String js) async {
    try {
      return await _c.evaluate(js);
    } catch (e) {
      _addLog('JS 错误: $e');
      return '';
    }
  }

  /// 0xfd1fac `回传 Cookie 中`: what the page sees goes into the engine's cookie store.
  Future<void> _saveCookie(String url) async {
    if (!url.startsWith('http')) return;
    try {
      final c = await _c.pageCookie();
      _addLog('页面可见cookie:$c');
      if (c.isNotEmpty) CookieStore.replaceCookie(url, c);
      _addLog('store里的cookie:${CookieStore.getCookie(url)}');
    } catch (e) {
      _addLog('保存Cookie失败:$e');
    }
  }

  void _finish(String? result) {
    if (_done || !mounted) return;
    _done = true;
    _timeout?.cancel();
    Navigator.of(context).pop(result);
  }

  /// `_handleConfirm` 0x5e9548: keep the cookies and return the page source.
  Future<void> _handleConfirm() async {
    final url = _c.url.value.isEmpty ? widget.url : _c.url.value;
    await _saveCookie(url);
    _finish(await _safeEval('document.documentElement.outerHTML'));
  }

  Future<void> _onMenu(String v) async {
    final url = _c.url.value.isEmpty ? widget.url : _c.url.value;
    switch (v) {
      case 'look':
        final cookie = CookieStore.getCookie(url);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Row(children: [
              const Expanded(child: Text('Cookies')),
              IconButton(
                tooltip: '复制',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cookie));
                  Toast.show('已复制到剪贴板');
                },
              ),
            ]),
            content: SingleChildScrollView(child: SelectableText(cookie.isEmpty ? '空' : cookie, style: const TextStyle(height: 1.5))),
            actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('关闭'))],
          ),
        );
      case 'delete':
        if (url.isEmpty) {
          Toast.show('获取网址失败');
          return;
        }
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('操作提醒'),
            content: const Text('是否清除当前网站的cookie？'),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
            ],
          ),
        );
        if (ok != true) return;
        try {
          CookieStore.removeCookie(url);
          await _c.clearCookies();
          Toast.show('Cookie清理成功');
        } catch (e) {
          Toast.show('Cookie清理失败:$e');
        }
      case 'showlog':
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('日志'),
            content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(_log.join('\n')))),
            actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('关闭'))],
          ),
        );
      case 'open':
        final u = Uri.tryParse(url);
        if (u == null || !await launchUrl(u, mode: LaunchMode.externalApplication)) Toast.show('打开失败');
    }
  }

  Future<void> _back() async {
    try {
      if (await _c.canGoBack()) {
        await _c.goBack();
        return;
      }
    } catch (e) {
      _addLog('返回失败:$e');
    }
    _finish(null);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => _finish(null)),
          titleSpacing: 0,
          title: ValueListenableBuilder<String>(
            valueListenable: _c.title,
            builder: (c, t, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(widget.title.isNotEmpty ? widget.title : (t.isEmpty ? '书源' : t), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: ValueListenableBuilder<String>(valueListenable: _c.url, builder: (c, u, _) => Text(u.isEmpty ? widget.url : u, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ),
          ),
          actions: [
            IconButton(tooltip: '返回', icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: _back),
            IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: () => _c.reload()),
            IconButton(key: const Key('webview_confirm'), tooltip: '确定', icon: const Icon(Icons.check), onPressed: _handleConfirm),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: _onMenu,
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'look', child: Text('查看Cookie')),
                PopupMenuItem(value: 'delete', child: Text('清除Cookie')),
                PopupMenuItem(value: 'showlog', child: Text('查看日志')),
                PopupMenuItem(value: 'open', child: Text('浏览器打开')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            ValueListenableBuilder<int>(
              valueListenable: _c.progress,
              builder: (c, p, _) => p >= 100 ? const SizedBox(height: 2) : LinearProgressIndicator(value: p / 100, minHeight: 2),
            ),
            Expanded(child: RepaintBoundary(child: _c.build(context))),
          ]),
        ),
      ),
    );
  }
}
