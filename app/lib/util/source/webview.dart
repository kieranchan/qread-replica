// util/source/webview.dart — `Webview` / `_Webview` (class 1219, list `_webviews` pool static 0x4eb0): the background pages behind
// the `webview` handler (0xe8dd28: url js html body header overrideUrlRegex urlregex) and `webviewajax` (0xe8d650: url html body
// header ajaxregex). Each request gets its own HeadlessInAppWebView (0xe540a0, 400x800, ajax interception on) that loads `html` (with
// `url` as its address) or `url` (a POST form when `body` is given), then answers (0xe495c4):
//   * `overrideUrlRegex`: a navigation whose url matches (the navigation itself goes on);
//   * `urlregex`: a navigation, loaded resource or failed request whose url matches, or (polled every second, 0xe53ce0) a url
//     found in the page's src / data-src / … / srcset attributes (0x1ab0f8);
//   * `ajaxregex`: the response text of a finished XMLHttpRequest whose url matches (0xe542ac); a matching request that has
//     not finished yet waits up to 30 s for it, then falls back to the page;
//   * otherwise the value of `js` (or the page source when `js` is empty) once the page has been quiet: 1 s after a load stop,
//     2 s after a load start / later navigation / resource, 5 s while a Cloudflare challenge page (`window._cf_chl_opt`) shows;
//   * a page that never settles gets 60 s, then answers `js` / its source as it is.
// A match answers after `waittime` (timer 0x1aafcc, 1 s; 2 s for ajax), the quiet-page answer after its own timer (0x1abdbc). The
// web view's cookies of `url` go into the app's store before the answer (0xe513ec); `endjs` runs after every page load (0xe5528c).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'baswebview.dart' show jsArg;
import 'http.dart';
import 'inapp_engine.dart';
import 'js_engine.dart';

class WebviewRequest {
  final String url;
  final String js;
  final String html;
  final String body;
  final Map<String, String> headers;
  final String overrideUrlRegex;
  final String urlregex;
  final String ajaxregex;

  /// Script run after every page load (not used by the page handlers).
  final String endjs;

  const WebviewRequest({
    this.url = '',
    this.js = '',
    this.html = '',
    this.body = '',
    this.headers = const {},
    this.overrideUrlRegex = '',
    this.urlregex = '',
    this.ajaxregex = '',
    this.endjs = '',
  });
}

abstract class Webview {
  /// One second of the original: the step of the waiting loop, of the resource poll and of every `waittime`.
  static Duration unit = const Duration(seconds: 1);

  /// Steps a page gets before it answers as it is (the original's loop of 60 one-second waits).
  static int timeoutUnits = 60;

  /// Runs [r] in a fresh background page and returns what it produced ('' on error).
  static Future<String> load(WebviewRequest r) => _Webview(r).run();

  /// 0x1ab0f8: the urls in the src / data-src / data-href / data-original / data-lazy-src / data-srcset / background / poster /
  /// srcset attributes of [html] (entities decoded, srcset lists split), in page order without repeats.
  static List<String> extractUrls(String html) {
    final out = <String>{};
    if (html.isEmpty) return const [];
    const attrs = ['src', 'data-src', 'data-href', 'data-original', 'data-lazy-src', 'data-srcset', 'background', 'poster', 'srcset'];
    for (final a in attrs) {
      for (final m in RegExp('\\b$a\\s*=\\s*"([^"]+)"', caseSensitive: false).allMatches(html)) {
        final v = (m.group(1) ?? '')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'")
            .replaceAll('&apos;', "'")
            .trim();
        if (v.isEmpty) continue;
        if (a.endsWith('srcset')) {
          for (final part in v.split(',')) {
            final u = part.trim().split(RegExp(r'\s+')).first;
            if (u.isNotEmpty) out.add(u);
          }
        } else {
          out.add(v);
        }
      }
    }
    return out.toList();
  }
}

class _Webview {
  final WebviewRequest r;
  late final SourceJsEngine engine;
  late final String url;

  bool done = false; // [0]
  bool created = false; // field_f
  bool loadedOnce = false; // field_7f
  bool busy = false; // field_97
  String matched = ''; // field_6f
  String result = ''; // field_77
  Timer? timer; // field_5f
  Timer? poll; // field_67
  final Completer<void> _end = Completer<void>();

  _Webview(this.r);

  static const String _outerHtml = 'document.documentElement.outerHTML';

  bool get _anyRegex => r.urlregex.isNotEmpty || r.overrideUrlRegex.isNotEmpty || r.ajaxregex.isNotEmpty;

  static bool _hit(String pattern, String s) {
    try {
      return RegExp(pattern).hasMatch(s);
    } catch (e) {
      debugPrint('webview 正则错误: $e');
      return false;
    }
  }

  Duration _secs(int n) => Webview.unit * n;

  Future<String> run() async {
    final headers = Map<String, String>.from(r.headers);
    final uaKey = headers.keys.firstWhere((k) => k.toLowerCase() == 'user-agent', orElse: () => '');
    final ua = uaKey.isEmpty ? null : headers.remove(uaKey);
    engine = SourceJsEngine.create(SourceJsEngineOptions(intercept: true, interceptAjax: true, userAgent: ua));
    engine
      ..onLoadStart = _onLoadStart
      ..onLoadStop = _onLoadStop
      ..onNavigate = _onNavigate
      ..onResource = _onResource
      ..onLoadError = _onResource
      ..onAjax = _onAjax
      ..onConsole = (m) => debugPrint('webview console: $m');
    url = SourceHttp.normalizeUrl(r.url);
    try {
      if (url.startsWith('http')) await WebCookies.push(url);
      // the platform reports navigations only after the load call returned; the flag is set first so that a synchronous
      // engine sees the same order
      created = true;
      if (r.html.isNotEmpty) {
        await engine.loadData(r.html, baseUrl: url.isEmpty ? 'about:blank' : url);
      } else {
        debugPrint('无html直接加载');
        final body = r.body.isEmpty ? null : r.body;
        if (body != null && !headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
        }
        await engine.loadUrl(url, headers: headers, body: body);
      }
      if (r.urlregex.isNotEmpty) {
        debugPrint('开始查询');
        poll = Timer.periodic(Webview.unit, (_) => _pollPage());
      }
      debugPrint('开始超时等待');
      var timedOut = false;
      await _end.future.timeout(_secs(Webview.timeoutUnits), onTimeout: () {
        timedOut = true;
      });
      if (timedOut && !done) {
        debugPrint('超时了');
        done = true;
        _cancelTimers();
        await _jsValue();
      }
      return result;
    } catch (e) {
      debugPrint('webview 加载失败: $e');
      return result;
    } finally {
      done = true;
      _cancelTimers();
      debugPrint('移除webview');
      await engine.dispose();
    }
  }

  void _cancelTimers() {
    timer?.cancel();
    timer = null;
    poll?.cancel();
    poll = null;
  }

  /// 0xe53f40.
  void _finish() {
    done = true;
    timer?.cancel();
    if (!_end.isCompleted) _end.complete();
  }

  /// 0xe51230: the value of `js` (the page source when empty), then the page's cookies.
  Future<void> _jsValue() async {
    try {
      final v = await engine.evaluateJavascript(r.js.isEmpty ? _outerHtml : r.js);
      result = v is String ? jsArg(v) : (v == null ? '' : jsonEncode(v));
      await _saveCookies();
    } catch (e) {
      debugPrint('js获取失败:$e');
    }
  }

  /// 0xe513ec.
  Future<void> _saveCookies() async {
    if (!url.startsWith('http')) return;
    try {
      await WebCookies.pull(url);
    } catch (e) {
      debugPrint('cookie save error:$e');
    }
  }

  /// 0x1aae48: a regex matched ([matched] is the answer); it is given after [wait] seconds.
  void _matched({int wait = 1}) {
    if (done) return;
    _cancelTimers();
    result = matched;
    timer = Timer(_secs(wait), () async {
      debugPrint('ajak ok end: $matched');
      await _saveCookies();
      _finish();
    });
  }

  /// 0x1abc64: the page is quiet; without a match, `js` / the page source is the answer after [wait] seconds (restarted by every
  /// later page event).
  void _loaded({int wait = 1}) {
    if (done || matched.isNotEmpty) return;
    timer?.cancel();
    timer = Timer(_secs(wait), () async {
      poll?.cancel();
      poll = null;
      await _jsValue();
      _finish();
    });
  }

  Future<bool> _challenge() async {
    try {
      final v = '${await engine.evaluateJavascript('!!window._cf_chl_opt')}';
      return v == 'true' || v == '"true"';
    } catch (_) {
      return false;
    }
  }

  /// 0xe53ce0: every second, the urls written in the page are tried against `urlregex`.
  Future<void> _pollPage() async {
    if (done) {
      poll?.cancel();
      poll = null;
      return;
    }
    if (busy) return;
    busy = true;
    try {
      String html;
      try {
        html = jsArg(await engine.evaluateJavascript(_outerHtml));
      } catch (e) {
        debugPrint('html获取失败:$e');
        html = '';
      }
      for (final u in Webview.extractUrls(html)) {
        if (_hit(r.urlregex, u)) {
          debugPrint('正则到了$u');
          matched = u;
          _matched();
          break;
        }
      }
    } finally {
      busy = false;
    }
  }

  /// 0xe5537c.
  Future<void> _onLoadStart(String u) async {
    if (!created) return;
    debugPrint('页面加载行为开始: $u');
    if (_anyRegex) return;
    _loaded(wait: await _challenge() ? 5 : 2);
  }

  /// 0xe55110.
  Future<void> _onLoadStop(String u) async {
    if (!created) return;
    if (r.endjs.isNotEmpty) {
      try {
        await engine.evaluateJavascript(r.endjs);
      } catch (e) {
        debugPrint('endjs执行失败:$e');
      }
    }
    loadedOnce = true;
    if (_anyRegex) return;
    _loaded(wait: await _challenge() ? 5 : 1);
  }

  /// 0xe54988: navigations are never cancelled once the page runs.
  Future<bool> _onNavigate(String u) async {
    if (!created) return false;
    debugPrint('shouldOverrideUrlLoading $u');
    if (r.urlregex.isNotEmpty && !done && _hit(r.urlregex, u)) {
      matched = u;
      _matched();
    }
    if (r.overrideUrlRegex.isNotEmpty && _hit(r.overrideUrlRegex, u)) {
      matched = u;
      _matched();
    }
    if (!_anyRegex && loadedOnce) _loaded(wait: await _challenge() ? 5 : 2);
    return true;
  }

  /// 0xe54774 (resources) / 0xe54ed4, 0xe54c98 (failed requests).
  Future<void> _onResource(String u) async {
    if (!created) return;
    if (r.urlregex.isNotEmpty && !done && _hit(r.urlregex, u)) {
      matched = u;
      _matched();
    }
    if (!_anyRegex && loadedOnce) _loaded(wait: await _challenge() ? 5 : 2);
  }

  /// 0xe542ac.
  void _onAjax(AjaxEvent e) {
    if (!created || r.ajaxregex.isEmpty) return;
    debugPrint('ajax ok: ${e.url} ${r.ajaxregex}');
    final hit = _hit(r.ajaxregex, e.url);
    if (e.readyState == 4) {
      if (!hit) return;
      debugPrint('ajax ok: ${e.url}');
      matched = e.responseText ?? '';
      _matched(wait: 2);
    } else if (hit) {
      debugPrint('ajax ok wait: ${e.url}');
      if (done) return;
      _cancelTimers();
      matched = '';
      _loaded(wait: 30);
    }
  }
}
