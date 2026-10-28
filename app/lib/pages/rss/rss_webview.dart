// pages/rss/rss_webview.dart — `WebviewRssPage`: shows one RSS article (or a single-url source). With a `ruleContent` the article
// body is extracted by the engine (`RssRunapi.content`) and rendered as html (with the source's `style`, base url = the article
// link when `loadWithBaseUrl`); without it the article link itself is loaded. `injectJs` runs after every page load.
//
// Original `_WebviewRssPageState` (72 functions: InAppWebView, cookie injection `注入cookie成功:`, ua `修改ua错误:`, JS console
// `JS 日志 [`, external schemes `外部跳转确认`, dark mode script `注入暗黑模式JavaScript失败: `). The strings the screen list files
// under this page next to them (缓存进度 / 终止 / 隐藏, 切换书源 / 加载目录 / 匹配书籍 / 不同作者 / 相近名称) belong to the download
// progress dialog (pages/read/pages/cachebook.dart, 0x7b87ac) and the 换源 page (pages/book/book_change_yuan.dart, 0x7ab140 /
// 0x7ada38): this page has no book-matching panel.
// Navigation (0xfbd220): import links (`yuedu` / `legado` / `qread`) go to the importers; then the source's `shouldOverrideUrlLoading`
// decides (local sources run the JavaScript with `url`, backend sources ask `/rssshouldOverrideUrlLoading`); a true answer keeps
// the page; other schemes ask 「外部跳转确认」. New windows (`onCreateWindow` 0xfbf010) open in this page.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/rssapi.dart';
import '../../models/article.dart';
import '../../qread/api/rssapi.dart';
import '../../util/legado/cookie_jar.dart';
import '../../util/toast.dart';
import '../../util/webbook/model/rss_article.dart';
import '../../util/webbook/model/rss_source.dart';
import '../web/web_engine.dart';
import '../web/webview.dart';

/// The engine's article for a stored [Article].
RssArticle toRssArticle(Article a, {String sort = ''}) =>
    RssArticle(origin: a.origin, sort: sort, title: a.title, link: a.link, pubDate: a.pubDate, description: a.description, image: a.image);

/// Wraps an extracted article body into a page (viewport, images fit the width, the source's css).
String rssContentHtml(String content, {String? style}) {
  final t = content.trimLeft().toLowerCase();
  if (t.startsWith('<!doctype') || t.startsWith('<html')) return content;
  return '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
      '<style>img{max-width:100%;height:auto}body{padding:12px;line-height:1.7;word-wrap:break-word}</style>'
      '${style == null || style.trim().isEmpty ? '' : '<style>$style</style>'}</head><body>$content</body></html>';
}

bool _isRemote(Map<String, dynamic> raw) => raw['isqread'] == true || '${raw['isqread']}' == 'true';

class WebviewRssPage extends StatefulWidget {
  /// Raw JSON of the RSS source.
  final Map<String, dynamic> source;
  final Article? article;

  /// Page to load when there is no article (single-url sources).
  final String? url;
  final String? title;
  const WebviewRssPage({super.key, required this.source, this.article, this.url, this.title});

  @override
  State<WebviewRssPage> createState() => _WebviewRssPageState();
}

class _WebviewRssPageState extends State<WebviewRssPage> {
  late final QWebController _c;
  late final RssSource _src = RssSource.fromJson(widget.source);
  String? _error;
  bool _loading = true;

  String get _link => widget.article?.link ?? widget.url ?? _src.sourceUrl;

  @override
  void initState() {
    super.initState();
    _c = WebEngine.create();
    _c.onNavigate = _onNavigate;
    _c.onPageFinished = _onPageFinished;
    _c.onConsole = (m) => debugPrint('JS 日志 [$m]');
    _load();
  }

  /// 0xfbd220.
  Future<bool> _onNavigate(String u) async {
    final scheme = Uri.tryParse(u)?.scheme.toLowerCase() ?? '';
    final js = _src.shouldOverrideUrlLoading;
    if (!importSchemes.contains(scheme) && u != _link && u != 'about:blank' && js != null && js.trim().isNotEmpty) {
      try {
        final handled = _isRemote(widget.source)
            ? await RssApi.shouldOverrideUrlLoading(_src.sourceUrl, u)
            : await RssRunapi.shouldOverrideUrlLoading(_src, u);
        debugPrint('rssshouldOverrideUrlLoading $u $handled');
        if (handled) return false;
      } catch (e) {
        debugPrint('rssshouldOverrideUrlLoading $u: $e');
      }
    }
    if (!mounted) return false;
    return webNavigationPolicy(context, u);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _onPageFinished(String url) async {
    final js = _src.injectJs;
    if (js != null && js.trim().isNotEmpty) {
      try {
        await _c.evaluate(js);
      } catch (e) {
        debugPrint('JS 错误: $e');
      }
    }
    try {
      final c = await _c.pageCookie();
      if (c.isNotEmpty && url.startsWith('http')) CookieStore.replaceCookie(url, c);
    } catch (e) {
      debugPrint('保存Cookie失败:$e');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _c.setJavaScript(_src.enableJs);
      final headers = await _src.getHeaderMap(true);
      final ua = headers.remove('User-Agent');
      if (ua != null) {
        try {
          await _c.setUserAgent(ua);
        } catch (e) {
          debugPrint('修改ua错误:$e');
        }
      }
      final a = widget.article;
      final hasRule = (_src.ruleContent ?? '').trim().isNotEmpty;
      if (a != null && (hasRule || _isRemote(widget.source))) {
        final body = _isRemote(widget.source) ? await RssApi.content(_src.sourceUrl, a) : await RssRunapi.content(_src, toRssArticle(a));
        final base = a.link.startsWith('http') ? a.link : _src.sourceUrl;
        await _c.loadHtml(rssContentHtml(body, style: _src.style), baseUrl: _src.loadWithBaseUrl ? base : null);
      } else {
        final cookie = CookieStore.getCookie(_link);
        if (cookie.isNotEmpty) {
          try {
            await _c.setCookie(_link, cookie);
            debugPrint('注入cookie成功:$cookie');
          } catch (_) {}
        }
        await _c.loadUrl(_link, headers: headers);
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? widget.article?.title ?? _src.sourceName;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _load),
          PopupMenuButton<String>(
            tooltip: '菜单',
            onSelected: (v) async {
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: _link));
                Toast.show('已复制到剪贴板');
              } else if (v == 'open') {
                final u = Uri.tryParse(_link);
                if (u == null || !await launchUrl(u, mode: LaunchMode.externalApplication)) Toast.show('打开失败');
              }
            },
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'copy', child: Text('复制链接')),
              PopupMenuItem(value: 'open', child: Text('浏览器打开')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          ValueListenableBuilder<int>(
            valueListenable: _c.progress,
            builder: (c, p, _) => _loading || p < 100 ? LinearProgressIndicator(value: _loading ? null : p / 100, minHeight: 2) : const SizedBox(height: 2),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, key: const Key('rss_web_error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(child: RepaintBoundary(child: _c.build(context))),
        ]),
      ),
    );
  }
}
