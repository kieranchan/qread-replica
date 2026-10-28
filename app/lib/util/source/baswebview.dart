// util/source/baswebview.dart — `Baswebview` (class 1236, fields `controller` 0xe8 and `sid` 0x100): the app side of the
// `window.flutter_inappwebview.callHandler(name, …)` bridge of a 时光源 page.
//
// Handlers of the original:
//   * per runner (0xe8ad88): setHtml 0xea8320, refreshExplore 0xea822c, call 0xea80ac (the result channel of [Baswebview.evalCall]),
//     CookieJar 0xea7f70 (the page-ready signal, its argument is the page's `isCookieJar`), log 0x227f5c, text 0x227e74 (debug html
//     of type 0 search / 1 info / 2 toc / 3 content), http 0xea7dcc (cookie jar as the page asked);
//   * shared with the foreground browser pages (dispatcher 0xe8af80, [SourceHandlers.register]): http 0xea6d40 (only with
//     `needhttp`), showvideoplay 0xea6b90, getDirectoryList 0xea6790, getsourceurl 0xea6740, getWidth 0xea6618, getHeight 0xea6568,
//     getsearch 0xea650c, showsvg 0xea64b8, getsvg 0xea646c, addsvg 0xea53b8, refreshContent 0xea52e0, getReadBook 0xea524c,
//     searchbook 0xea5138, voice 0xe9011c, addbook 0xe8fe58, toTraditional 0xe8fb9c, toSimplified 0xe8f2d0, buildNumber 0xe8f274,
//     version 0xe8ec4c, id 0xe8ec00, device 0xe8eb18, showToast 0x1f957c, showLongToast 0x1f94bc, getWebViewUA 0xe8eacc, putLyric
//     0xe8e8d8, cache.allget/allset/allremove 0xe8e828/0xe8e740/0xe8e68c, cache.get/set/remove 0xe8e5d4/0xe8e4e4/0xe8e428,
//     cookie.get 0xe8e39c, cookie.getCookie 0xe8e228, cookie.remove 0xe8e198, cookie.set 0xe8e0d4, cookie.setcookie 0xe8df0c,
//     webview 0xe8dd28, getdurChapterIndex 0xe8d7c8, webviewajax 0xe8d650, startBrowser 0xe8d420,
//     startBrowserWithShouldOverrideUrlLoading 0xe8d1fc, startBrowserDpWithShouldOverrideUrlLoading 0xe8d0a0, startBrowserDp 0xe8cf5c,
//     startBrowserDpwithHtml 0xe8cde4, openurl 0xe8cbec, base64encode 0xe8cb48, base64decode 0xe8caa8, getLoginUser 0xe8ca5c,
//     htmlToText 0xe8c3d4, getVerificationCode 0xe8bec0, utf8ToGbkUrlEncoded 0xe8bc10.
// Every argument goes through the original's normaliser 0xd576c ([jsArg]). Pages, the reader and other areas are reached through
// [SourceUi] hooks that the app installs (pages/web/web_hooks.dart); without a hook a handler answers an empty value.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../common/common.dart';
import '../../data/user.dart';
import '../chinese_utils.dart';
import '../http.dart';
import '../legado/cookie_jar.dart';
import '../legado/html_formatter.dart';
import '../toast.dart';
import 'cache.dart';
import 'http.dart';
import 'js_engine.dart';
import 'source.dart';
import 'webview.dart';

/// 0xd576c: a JavaScript value as text — null / undefined / `"null"` -> '', a JSON-quoted string is unquoted, objects and arrays
/// become JSON.
String jsArg(Object? v) {
  if (v == null) return '';
  if (v is String) {
    final s = v;
    if (s == 'null' || s == 'undefined') return '';
    if (s.length >= 2 && ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'")))) {
      try {
        final d = jsonDecode(s.startsWith("'") ? jsonEncode(s.substring(1, s.length - 1)) : s);
        if (d is String) return d;
      } catch (_) {}
    }
    return s;
  }
  if (v is Map || v is List) return jsonEncode(v);
  if (v is double && v == v.roundToDouble() && v.abs() < 1e15) return '${v.toInt()}';
  return '$v';
}

String _arg(List<dynamic> a, int i) => i < a.length ? jsArg(a[i]) : '';

bool _boolArg(List<dynamic> a, int i, bool def) {
  if (i >= a.length || a[i] == null) return def;
  final v = a[i];
  if (v is bool) return v;
  final s = jsArg(v).toLowerCase();
  return !(s == 'false' || s == '0' || s.isEmpty);
}

/// A foreground browser page a handler asks for.
class SourceBrowserRequest {
  final String url;
  final String title;
  final Map<String, String> headers;

  /// HTML shown instead of loading [url] (`startBrowserDpwithHtml`).
  final String? html;

  /// The source whose bridge the page gets (`cache.*` of that source, `shouldOverrideUrlLoading`).
  final BaseSource? source;

  /// Every navigation is first given to the source page's `shouldOverrideUrlLoading(url)`; false cancels it.
  final bool overrideUrlLoading;

  /// Half-height sheet (段评, `startBrowserDp*`).
  final bool half;

  const SourceBrowserRequest({
    required this.url,
    this.title = '',
    this.headers = const {},
    this.html,
    this.source,
    this.overrideUrlLoading = false,
    this.half = false,
  });
}

/// What the handlers need from the UI and the other areas. The app installs them at start-up; tests install fakes.
abstract class SourceUi {
  /// Opens a foreground browser page; the result is the page source when it closed (`startBrowser`), or null.
  static Future<String?> Function(SourceBrowserRequest request)? openBrowser;

  /// Shows the captcha image ('' = no image) and returns what the user typed.
  static Future<String?> Function(String imageUrl, Map<String, String> headers)? verificationCode;

  /// `addbook`: the detail page of [bookUrl] of the source (the user adds it to the shelf there).
  static Future<void> Function(String sourceUrl, String bookUrl)? openBook;

  /// `searchbook`: the search page with [key], restricted to the source.
  static Future<void> Function(String sourceUrl, String key)? searchBook;

  /// `openurl`: hands [url] to the system (default: url_launcher).
  static Future<bool> Function(String url, String mimeType)? openUrl;

  /// `showvideoplay`.
  static Future<void> Function(String url, String title)? playVideo;

  /// `voice`: reads [text] aloud.
  static Future<void> Function(String text)? speak;

  /// Screen size in logical pixels (`getWidth` / `getHeight`).
  static Size Function()? screenSize;

  /// `getsearch`: the category chosen on the search page (-1 all, 0 小说, 1 听书, 2 漫画).
  static int Function()? searchType;

  /// Reader hooks: `getReadBook` (the open book as JSON), `getdurChapterIndex`, `refreshContent`, `getDirectoryList`, `putLyric`.
  static Map<String, dynamic>? Function()? readBook;
  static int Function(String bookUrl)? durChapterIndex;
  static Future<void> Function()? refreshContent;
  static Future<List<dynamic>> Function(String bookUrl)? directoryList;
  static void Function(String lyric)? putLyric;

  static void resetForTests() {
    openBrowser = null;
    verificationCode = null;
    openBook = null;
    searchBook = null;
    openUrl = null;
    playVideo = null;
    speak = null;
    screenSize = null;
    searchType = null;
    readBook = null;
    durChapterIndex = null;
    refreshContent = null;
    directoryList = null;
    putLyric = null;
  }
}

/// App facts the handlers report.
abstract class SourceRuntime {
  static Future<PackageInfo> Function() packageInfo = PackageInfo.fromPlatform;

  /// The web view's user agent once a page reported it (`navigator.userAgent`), else the app's HTTP user agent.
  static String? webViewUA;

  static Future<String> version() async {
    try {
      return (await packageInfo()).version;
    } catch (_) {
      return '0.0.0';
    }
  }

  static Future<String> buildNumber() async {
    try {
      return (await packageInfo()).buildNumber;
    } catch (_) {
      return '0';
    }
  }

  /// 0xe8eb18: windows / macos / ohos / android / ios, else `unknow`.
  static String device() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        TargetPlatform.macOS => 'macos',
        TargetPlatform.windows => 'windows',
        _ => 'unknow',
      };

  static String userAgent() => (webViewUA ?? '').isNotEmpty ? webViewUA! : AppHttp.userAgent;
}

/// The handlers every page of a source gets (dispatcher 0xe8af80).
abstract class SourceHandlers {
  /// `cookie.*` take host names too (`fanqienovel.com`): 0xe521ac puts `http://` in front of anything that does not start with http.
  static String cookieUrl(String url) {
    final t = url.trim();
    return t.toLowerCase().startsWith('http') ? t : 'http://$t';
  }

  /// 0xe8bc10: GBK bytes of [s], each written `%XX`.
  static String utf8ToGbkUrlEncoded(String s) {
    try {
      final sb = StringBuffer();
      for (final b in gbk.encode(s)) {
        sb.write('%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
      return sb.toString();
    } catch (e) {
      debugPrint('UTF-8转GBK URL编码失败: $e');
      return '';
    }
  }

  static void register(JsHandlerSink sink, BaseSource source, {bool needhttp = false}) {
    void on(String name, JsHandler h) => sink.addJavaScriptHandler(name, h);
    final cache = Cache(source.bookSourceUrl);
    const shared = Cache(Cache.all);

    if (needhttp) {
      on('http', (a) async => (await SourceHttp.request(
            method: _arg(a, 0),
            url: _arg(a, 1),
            body: _arg(a, 2),
            headers: _arg(a, 3),
            followRedirects: a.length > 4 ? a[4] : true,
            contentType: _arg(a, 5),
          ))
              .toJson());
    }
    on('showvideoplay', (a) async {
      await SourceUi.playVideo?.call(_arg(a, 0), _arg(a, 1));
      return null;
    });
    on('getDirectoryList', (a) async => await SourceUi.directoryList?.call(_arg(a, 0)) ?? const []);
    on('getsourceurl', (a) => source.bookSourceUrl);
    on('getWidth', (a) => SourceUi.screenSize?.call().width ?? 0.0);
    on('getHeight', (a) => SourceUi.screenSize?.call().height ?? 0.0);
    on('getsearch', (a) => SourceUi.searchType?.call() ?? -1);
    // TODO(asm 0xea64b8 / 0xea646c / 0xea53b8): the 段评 bubble store (Svgimage) is not ported; the page gets an empty list.
    on('showsvg', (a) => null);
    on('getsvg', (a) => const []);
    on('addsvg', (a) => null);
    on('refreshContent', (a) async {
      await SourceUi.refreshContent?.call();
      return null;
    });
    on('getReadBook', (a) => SourceUi.readBook?.call());
    on('searchbook', (a) async {
      await SourceUi.searchBook?.call(source.bookSourceUrl, _arg(a, 0));
      return null;
    });
    on('voice', (a) async {
      final f = SourceUi.speak;
      if (f == null) {
        Toast.show('获取朗读引擎失败');
      } else {
        await f(_arg(a, 0));
      }
      return null;
    });
    on('addbook', (a) async {
      try {
        await SourceUi.openBook?.call(source.bookSourceUrl, _arg(a, 0));
      } catch (e) {
        Toast.log.add('addbook错误:$e');
      }
      return null;
    });
    on('toTraditional', (a) => ChineseUtils.toTraditional(_arg(a, 0)));
    on('toSimplified', (a) => ChineseUtils.toSimplified(_arg(a, 0)));
    on('buildNumber', (a) => SourceRuntime.buildNumber());
    on('version', (a) => SourceRuntime.version());
    on('id', (a) => Common.appid);
    on('device', (a) => SourceRuntime.device());
    on('showToast', (a) {
      Toast.log.add('弹窗:${_arg(a, 0)}');
      Toast.show(_arg(a, 0));
      return true;
    });
    on('showLongToast', (a) {
      Toast.show(_arg(a, 0));
      return true;
    });
    on('getWebViewUA', (a) => SourceRuntime.userAgent());
    on('putLyric', (a) {
      SourceUi.putLyric?.call(_arg(a, 0));
      return null;
    });
    on('cache.allget', (a) => shared.get(_arg(a, 0)));
    on('cache.allset', (a) async {
      await shared.set(_arg(a, 0), _arg(a, 1));
      return null;
    });
    on('cache.allremove', (a) async {
      await shared.remove(_arg(a, 0));
      return null;
    });
    on('cache.get', (a) => cache.get(_arg(a, 0)));
    on('cache.set', (a) async {
      await cache.set(_arg(a, 0), _arg(a, 1));
      return null;
    });
    on('cache.remove', (a) async {
      await cache.remove(_arg(a, 0));
      return null;
    });
    on('cookie.get', (a) => CookieStore.getCookie(cookieUrl(_arg(a, 0))));
    on('cookie.getCookie', (a) {
      final v = CookieStore.getKey(cookieUrl(_arg(a, 0)), _arg(a, 1));
      return v.isEmpty ? null : v;
    });
    on('cookie.remove', (a) {
      CookieStore.removeCookie(cookieUrl(_arg(a, 0)));
      return null;
    });
    on('cookie.set', (a) {
      CookieStore.setCookie(cookieUrl(_arg(a, 0)), _arg(a, 1));
      return null;
    });
    on('cookie.setcookie', (a) {
      final url = cookieUrl(_arg(a, 0));
      final m = CookieStore.cookieToMap(CookieStore.getCookie(url))..[_arg(a, 1)] = _arg(a, 2);
      CookieStore.setCookie(url, CookieStore.mapToCookie(m));
      return null;
    });
    on('webview', (a) => Webview.load(WebviewRequest(
          url: _arg(a, 0),
          js: _arg(a, 1),
          html: _arg(a, 2),
          body: _arg(a, 3),
          headers: SourceHttp.headersOf(_arg(a, 4)),
          overrideUrlRegex: _arg(a, 5),
          urlregex: _arg(a, 6),
        )));
    on('getdurChapterIndex', (a) => SourceUi.durChapterIndex?.call(_arg(a, 0)) ?? 0);
    // TODO(asm 0xe8d650): the original watches the page's ajax requests; the replica answers the first request url matching
    // `ajaxregex` (like `webViewGetSource`).
    on('webviewajax', (a) => Webview.load(WebviewRequest(url: _arg(a, 0), body: _arg(a, 1), urlregex: _arg(a, 2))));
    Future<String> browser(SourceBrowserRequest r) async => await SourceUi.openBrowser?.call(r) ?? '';
    on('startBrowser', (a) => browser(SourceBrowserRequest(url: _arg(a, 0), title: _arg(a, 1), headers: SourceHttp.headersOf(_arg(a, 2)), source: source)));
    on('startBrowserWithShouldOverrideUrlLoading', (a) => browser(SourceBrowserRequest(
          url: _arg(a, 0),
          title: _arg(a, 1),
          headers: SourceHttp.headersOf(_arg(a, 2)),
          source: source,
          overrideUrlLoading: true,
        )));
    on('startBrowserDpWithShouldOverrideUrlLoading', (a) async {
      await browser(SourceBrowserRequest(
        url: _arg(a, 0),
        title: _arg(a, 1),
        headers: SourceHttp.headersOf(_arg(a, 2)),
        source: source,
        overrideUrlLoading: true,
        half: true,
      ));
      return null;
    });
    on('startBrowserDp', (a) async {
      await browser(SourceBrowserRequest(url: _arg(a, 0), title: _arg(a, 1), source: source, half: true));
      return null;
    });
    on('startBrowserDpwithHtml', (a) async {
      await browser(SourceBrowserRequest(url: source.bookSourceUrl, html: _arg(a, 0), title: _arg(a, 1), source: source, half: true));
      return null;
    });
    on('openurl', (a) async {
      final url = _arg(a, 0);
      final f = SourceUi.openUrl;
      if (f != null) return f(url, _arg(a, 1));
      final u = Uri.tryParse(url);
      if (u == null) return false;
      try {
        return await launchUrl(u, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    });
    on('base64encode', (a) => base64Encode(utf8.encode(_arg(a, 0))));
    on('base64decode', (a) {
      try {
        return utf8.decode(base64Decode(base64.normalize(_arg(a, 0).trim())), allowMalformed: true);
      } catch (_) {
        return '';
      }
    });
    on('getLoginUser', (a) => UserSession.username);
    on('htmlToText', (a) => HtmlFormatter.stripTags(_arg(a, 0)));
    on('getVerificationCode', (a) async => await SourceUi.verificationCode?.call(_arg(a, 0), SourceHttp.headersOf(_arg(a, 1))) ?? '');
    on('utf8ToGbkUrlEncoded', (a) => utf8ToGbkUrlEncoded(_arg(a, 0)));
  }
}

/// Fired by the page's `refreshExplore` (0xea822c, static hook 0x1ea4): the discovery page of that source reloads its entries.
abstract class ExploreRefresh {
  static final StreamController<String> _c = StreamController<String>.broadcast();
  static Stream<String> get stream => _c.stream;
  static void notify(String sourceUrl) => _c.add(sourceUrl);
}

abstract class Baswebview {
  static const Uuid _uuid = Uuid();

  late SourceJsEngine controller;
  late BaseSource source;
  late String sid;

  /// The page's `isCookieJar` (CookieJar handler); the instance `http` handler sends/keeps cookies only when it is true.
  bool isCookieJar = true;

  /// The page reported `CookieJar` (ready to run functions).
  bool ready = false;

  /// The runner was disposed (`页面已销毁`).
  bool destroyed = false;

  /// Debug sinks of the source debugger (fields 0x97 / 0x9f of the original): `log` lines and `text` html of type 0..3.
  void Function(String line)? debugLog;
  void Function(int type, String html)? debugText;

  final Map<String, Completer<Object?>> _calls = {};

  /// Storage key of the cached explore entries of the source (`"ExploreUrl" + bookSourceUrl`, 0xfb9864 / 0xea822c).
  static String exploreKey(String sourceUrl) => 'ExploreUrl$sourceUrl';

  /// Called when the page asks to refresh the discovery entries.
  Future<void> onRefreshExplore();

  /// 0xe8ad88: the runner's own handlers, then the shared set.
  void registerHandlers() {
    final c = controller;
    // TODO(asm 0xea8320): `setHtml` (editor debugging hook) is accepted and ignored.
    c.addJavaScriptHandler('setHtml', (a) => null);
    c.addJavaScriptHandler('refreshExplore', (a) async {
      await onRefreshExplore();
      return '';
    });
    c.addJavaScriptHandler('call', (a) {
      final id = _arg(a, 0);
      final done = _calls.remove(id);
      if (done != null && !done.isCompleted) done.complete(a.length > 1 ? a[1] : null);
      return null;
    });
    c.addJavaScriptHandler('CookieJar', (a) {
      isCookieJar = a.isEmpty ? true : _boolArg(a, 0, true);
      debugPrint('${source.bookSourceName}:$isCookieJar');
      ready = true;
      return null;
    });
    c.addJavaScriptHandler('log', (a) {
      final msg = _arg(a, 0);
      debugPrint('${source.bookSourceName},log:$msg');
      debugLog?.call(msg);
      Toast.log.add('${source.bookSourceName}:$msg');
      return true;
    });
    c.addJavaScriptHandler('text', (a) {
      final type = int.tryParse(_arg(a, 0)) ?? 0;
      debugText?.call(type, _arg(a, 1));
      return true;
    });
    c.addJavaScriptHandler('http', (a) async => (await SourceHttp.request(
          method: _arg(a, 0),
          url: _arg(a, 1),
          body: _arg(a, 2),
          headers: _arg(a, 3),
          followRedirects: a.length > 4 ? a[4] : true,
          contentType: _arg(a, 5),
          isCookieJar: isCookieJar,
        ))
            .toJson());
    SourceHandlers.register(c, source);
  }

  /// 0xd5dd8: the code that runs [expr] in the page and posts its value back through the `call` handler.
  static String wrapCall(String id, String expr) => '''
          (async function() {
          var id="$id";
            try {
              const result = await $expr;
               window.flutter_inappwebview.callHandler('call', id,result);
            } catch (error) {
              window.flutter_inappwebview.callHandler('call', id,"");
              window.flutter_inappwebview.callHandler('log',error.message);
            }
          })()
        ''';

  /// 0xd5e58 / 0xd5924 / 0xe092cc: runs [expr] (a call of a page function) and waits for its value (`等待函数执行超时`).
  Future<Object?> evalCall(String expr, Duration timeout) async {
    if (destroyed) throw StateError('页面已销毁');
    final id = _uuid.v4();
    final done = Completer<Object?>();
    _calls[id] = done;
    try {
      await controller.evaluateJavascript(wrapCall(id, expr));
    } catch (e) {
      debugPrint('evaluateJavascript: $e');
    }
    try {
      return await done.future.timeout(timeout, onTimeout: () => throw TimeoutException('等待函数执行超时', timeout));
    } finally {
      _calls.remove(id);
    }
  }

  /// Fails every pending call (the page went away).
  void failPending(Object error) {
    for (final c in _calls.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _calls.clear();
  }
}
