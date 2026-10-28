// util/source/webview.dart — `Webview` / `_Webview` (class 1219, pool static 0x4eb0): the background pages behind the `webview`
// handler (0xe8dd28, named arguments url js html body header overrideUrlRegex urlregex) and `webviewajax` (0xe8d650, url body
// ajaxregex). Each request gets its own HeadlessInAppWebView (0xe541c4) that loads `html` (with `url` as its address) or `url` (a POST
// when `body` is given, headers from the JSON `header`), and answers, as the page bridge documents it:
//   * `overrideUrlRegex`: the first navigation whose url matches (the navigation is cancelled);
//   * `urlregex`: the first loaded resource (or navigation) whose url matches;
//   * otherwise, or when nothing matched, the value of `js` after the page loaded, or the page source when `js` is empty.
// TODO(asm 0x1aafcc / 0x1abdbc): the original's timer values; the replica gives a page 60 s and, in the regex modes, 5 s after the
// last page load before it falls back to `js` / the page source.
import 'dart:async';

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

  const WebviewRequest({
    this.url = '',
    this.js = '',
    this.html = '',
    this.body = '',
    this.headers = const {},
    this.overrideUrlRegex = '',
    this.urlregex = '',
  });
}

abstract class Webview {
  static Duration timeout = const Duration(seconds: 60);
  static Duration regexGrace = const Duration(seconds: 5);

  static RegExp? _re(String s) {
    if (s.trim().isEmpty) return null;
    try {
      return RegExp(s);
    } catch (e) {
      debugPrint('webview 正则错误: $e');
      return null;
    }
  }

  /// Runs [r] in a fresh background page and returns what it produced ('' on timeout or error).
  static Future<String> load(WebviewRequest r) async {
    final headers = Map<String, String>.from(r.headers);
    final uaKey = headers.keys.firstWhere((k) => k.toLowerCase() == 'user-agent', orElse: () => '');
    final ua = uaKey.isEmpty ? null : headers.remove(uaKey);
    final engine = SourceJsEngine.create(SourceJsEngineOptions(intercept: true, userAgent: ua));
    final done = Completer<String>();
    final override = _re(r.overrideUrlRegex);
    final source = _re(r.urlregex);
    Timer? grace;
    void finish(String v) {
      if (!done.isCompleted) done.complete(v);
    }

    Future<String> pageValue() async {
      try {
        return jsArg(await engine.evaluateJavascript(r.js.trim().isEmpty ? 'document.documentElement.outerHTML' : r.js));
      } catch (e) {
        debugPrint('webview js 错误: $e');
        return '';
      }
    }

    engine.onNavigate = (u) {
      if (override != null && override.hasMatch(u)) {
        finish(u);
        return false;
      }
      if (source != null && source.hasMatch(u)) {
        finish(u);
        return false;
      }
      return true;
    };
    engine.onResource = (u) {
      if (source != null && source.hasMatch(u)) finish(u);
    };
    engine.onLoadStop = (u) async {
      if (done.isCompleted) return;
      await WebCookies.pull(u);
      if (override != null || source != null) {
        grace?.cancel();
        grace = Timer(regexGrace, () async => finish(await pageValue()));
        return;
      }
      final v = await pageValue();
      // a script that has no value yet is asked again on the next page load (redirects, challenge pages)
      if (v.isNotEmpty || r.js.trim().isEmpty) finish(v);
    };
    try {
      final url = SourceHttp.normalizeUrl(r.url);
      if (url.isNotEmpty) await WebCookies.push(url);
      if (r.html.isNotEmpty) {
        await engine.loadData(r.html, baseUrl: url.isEmpty ? 'about:blank' : url);
      } else {
        await engine.loadUrl(url, headers: headers, body: r.body.isEmpty ? null : r.body);
      }
      return await done.future.timeout(timeout, onTimeout: () async => r.js.trim().isEmpty ? '' : await pageValue());
    } catch (e) {
      debugPrint('webview 加载失败: $e');
      return '';
    } finally {
      grace?.cancel();
      await engine.dispose();
    }
  }
}
