// util/source/run.dart — `SourceRun` (class 1237): one running 时光源. The page (the source's `html`: code, or fetched from its URL)
// is loaded into a web view (one per source, kept in [SourceRun.sourcerun] — `SourceApi.sourcerun` 0x3b20 in the original — and
// reused); the app waits for the page's `CookieJar` call, then runs the page's functions and parses what they return.
//
// Original control flow:
//   * page (0xe88cd8): a `http(s)` html is downloaded (`获取html` … `完成获取html`; on failure the last copy, `html 加载失败 使用缓存`,
//     else `获取在线书源失败`); `@aes…` pages are decrypted (0xe8a4c0); jQuery CDN links are rewritten to the app's mirrors.
//   * ready (0xe097d8): poll every 10 ms until the page called `CookieJar`; 60 s -> `等待页面就绪超时`, disposed -> `页面已销毁`.
//   * call (0xd5e58 id, 0xd5dd8 wrapper, 0xd5924 evaluate, 0xe092cc wait): `await fn(args)` inside an async IIFE that posts the
//     value through the `call` handler; arguments are JSON-encoded (0xe07fe4) except numbers; the value is normalised (0xd576c).
//   * entry points and timeouts: search(key,page,env) 0xf85c7c 120 s, info(bookurl) 0xe68ec4 120 s, chapter(tocUrl,bookurl)
//     0xeda378 400 s, content(url,bookurl,index) 0xf12700 120 s, getfinds() 0xfb9ed4 120 s, find(url,page) 0xfc2dfc 120 s,
//     getloginurl() 0xe61ae0, pay(bookurl,url) 0x10e7268 120 s, imagedecrypt(url,image) 0xeb5dc8 60 s, gethelp() 0xf8dae0 20 s,
//     filter() 0xfdb268 / findfilter(url) 0x1058fa4 / getinfo 0xfcf350 120 s, callbackjs(event,book) 0xe085bc.
//   * results: book lists 0xf8635c, one book 0xe694ec (both rewrite `wordCount` as 「n万字」), chapters 0xedaa54 (index = position,
//     🔒 in front of VIP chapter names); the debugger logs `︾开始解析搜索页` / `︾开始解析详情页` / `︾开始解析目录页` / `︾开始解析正文页`.
//   * idle runners are dropped after 5 minutes (0x8e7c0c, `300000` ms since the last call).
//
// Replica differences: the page runs in a HeadlessInAppWebView instead of QuickJS (see js_engine.dart); jQuery links are left as
// the page wrote them (the original's iOS mirror is on qread.xyz, which the replica never calls); `@aes` pages are refused because
// the decryption key is a constant of the original binary (TODO(asm 0xe8a4c0)); the original's extra `X-Requested-With` header
// with its own package name is not sent when the page is downloaded (0xe8a944).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../common/common.dart';
import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../storage/storage.dart';
import '../http.dart';
import '../toast.dart';
import '../webbook/model/book_source.dart' show ExploreKind;
import 'baswebview.dart';
import 'inapp_engine.dart';
import 'js_engine.dart';
import 'source.dart';

/// Turns what the page functions return into app models (the original's `_parse*Isolate` functions).
abstract class SourceParse {
  /// 0xd58e0: JSON text (or an already decoded value) -> value; a JSON string holding JSON is decoded twice.
  static Object? decode(Object? v) {
    Object? d = v;
    for (var i = 0; i < 2 && d is String; i++) {
      final t = d.trim();
      if (t.isEmpty) return null;
      try {
        d = jsonDecode(t);
      } catch (_) {
        return i == 0 ? null : d;
      }
    }
    return d;
  }

  static final RegExp _number = RegExp(r'(\d+\.?\d*)');

  /// 0xe694ec: the word count as the original shows it — the number in the text (×10000 with 万, ×1000 with 千, rounded) divided
  /// by 10000, `n万字` when whole, else with two decimals (an empty or numberless text gives 0万字).
  static String formatWordCount(String text) {
    final t = text.trim();
    var n = 0;
    if (t.isNotEmpty) {
      final m = _number.firstMatch(t);
      final d = m == null ? null : double.tryParse(m.group(1)!);
      if (d != null) {
        if (t.contains('万')) {
          n = d.round() * 10000;
        } else if (t.contains('千')) {
          n = d.round() * 1000;
        } else {
          n = d.round();
        }
      }
    }
    final w = n / 10000;
    if (w == w.roundToDouble()) return '${w.round()}万字';
    return '${w.toStringAsFixed(2)}万字';
  }

  static Book _book(Map<String, dynamic> m) {
    final b = Book.fromJson(m);
    b.wordCount = formatWordCount(b.wordCount);
    return b;
  }

  /// 0xf8635c: a JSON array of books.
  static List<Book> books(Object? json) {
    final d = decode(json);
    if (d is! List) return [];
    return [for (final e in d) if (e is Map) _book(Map<String, dynamic>.from(e))];
  }

  /// 0xe694ec: one book (a JSON object); anything else is an error.
  static Book book(Object? json) {
    final d = decode(json);
    if (d is! Map) throw const FormatException('详情页解析失败');
    return _book(Map<String, dynamic>.from(d));
  }

  /// 0xedaa54: the table of contents; index = position, VIP chapters get 🔒 in front of the name.
  static List<BookChapter> chapters(Object? json) {
    final d = decode(json);
    if (d is! List) return [];
    final out = <BookChapter>[];
    for (final e in d) {
      if (e is! Map) continue;
      final c = BookChapter.fromJson(Map<String, dynamic>.from(e));
      c.index = out.length;
      if (c.isVip && !c.name.contains('🔒')) c.name = '🔒${c.name}';
      out.add(c);
    }
    return out;
  }

  /// The `getfinds()` entries in the engine's explore model. 时光源 kinds (template pp+0x53108): 0 a list (`url` -> find(), only
  /// `js` -> a button running it, neither -> a full-width title), 1 the url opened in the web view, 2 a drop-down (`chars`,
  /// `default`, `action`), 3 an input box, 4 a button running `action`.
  static List<ExploreKind> explores(Object? json) {
    final d = decode(json);
    if (d is! List) return [];
    final out = <ExploreKind>[];
    for (final e in d) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final k = ExploreKind.fromJson({...m, 'type': 0});
      final url = (k.url ?? '').trim();
      final type = m['type'] is num ? (m['type'] as num).toInt() : int.tryParse('${m['type'] ?? 0}') ?? 0;
      switch (type) {
        case 1:
          k.type = ExploreKind.typeWeb;
        case 2:
          k.type = ExploreKind.typeSelect;
        case 3:
          k.type = ExploreKind.typeText;
        case 4:
          k.type = ExploreKind.typeButton;
        default:
          if (url.isNotEmpty) {
            k.type = ExploreKind.typeUrl;
          } else if (k.js.trim().isNotEmpty) {
            k.type = ExploreKind.typeButton;
            k.action = k.js;
          } else {
            k.type = ExploreKind.typeTitle;
            k.width = 3;
          }
      }
      out.add(k);
    }
    return out;
  }
}

class SourceRun extends Baswebview {
  /// Running sources by `bookSourceUrl`.
  static final Map<String, SourceRun> sourcerun = {};
  static final Map<String, Future<SourceRun>> _starting = {};
  static Timer? _sweeper;

  static Duration idle = const Duration(minutes: 5);
  static Duration readyTimeout = const Duration(seconds: 60);
  static const Duration searchTimeout = Duration(seconds: 120);
  static const Duration infoTimeout = Duration(seconds: 120);
  static const Duration chapterTimeout = Duration(seconds: 400);
  static const Duration contentTimeout = Duration(seconds: 120);
  static const Duration findTimeout = Duration(seconds: 120);
  static const Duration payTimeout = Duration(seconds: 120);
  static const Duration imageTimeout = Duration(seconds: 60);
  static const Duration helpTimeout = Duration(seconds: 20);
  static const Duration loginTimeout = Duration(seconds: 120);

  /// Milliseconds of the last use (field 263 of the original).
  int lastUse = DateTime.now().millisecondsSinceEpoch;

  SourceRun._(BaseSource s) {
    source = s;
  }

  /// The running page of [s], started when needed; a changed `html` restarts it.
  static Future<SourceRun> of(BaseSource s) {
    final url = s.bookSourceUrl;
    final cur = sourcerun[url];
    if (cur != null && !cur.destroyed && cur.source.html == s.html) {
      cur.touch();
      return Future.value(cur);
    }
    final pending = _starting[url];
    if (pending != null) return pending;
    final f = () async {
      if (cur != null) await remove(url);
      final r = SourceRun._(s);
      try {
        await r._start();
      } catch (e) {
        await r.dispose();
        Toast.log.add('书源创建函数报错:$e');
        rethrow;
      }
      sourcerun[url] = r;
      _sweeper ??= Timer.periodic(const Duration(minutes: 1), (_) => sweep());
      return r;
    }();
    _starting[url] = f;
    return f.whenComplete(() => _starting.remove(url));
  }

  /// 重载书源线程 (0xe77e8c): drops the runner of [url]; the next call starts the page again.
  static Future<void> remove(String url) async {
    final r = sourcerun.remove(url);
    if (r != null) await r.dispose();
  }

  static Future<void> clear() async {
    for (final url in sourcerun.keys.toList()) {
      await remove(url);
    }
    _sweeper?.cancel();
    _sweeper = null;
  }

  /// 0x8e7c0c: drops runners not used for [idle].
  static void sweep() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in sourcerun.entries.toList()) {
      if (now - e.value.lastUse > idle.inMilliseconds && e.value._busy == 0) remove(e.key);
    }
  }

  int _busy = 0;

  void touch() => lastUse = DateTime.now().millisecondsSinceEpoch;

  /// Storage key of the last downloaded copy of an html URL (used when the download fails).
  static String htmlCacheKey(String url) => 'sourcehtml_$url';

  /// 0xe88cd8: the page text and the address it is loaded under.
  static Future<({String html, String baseUrl})> loadPage(BaseSource s, {void Function(String line)? log}) async {
    var html = s.html.trim();
    var base = s.bookSourceUrl.toLowerCase().startsWith('http') ? s.bookSourceUrl : 'http://localhost/';
    if (s.htmlIsUrl) {
      final url = html;
      log?.call('获取html');
      try {
        final res = await AppHttp.send(HttpRequest(url: url, headers: {'deviceid': Common.appid}, timeout: const Duration(seconds: 30)));
        if (!res.isSuccessful) throw Exception('HTTP ${res.statusCode} ${res.statusMessage}');
        html = AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType).trim();
        if (html.isEmpty) throw const FormatException('html 为空');
        await Storage.write(htmlCacheKey(url), html);
        log?.call('完成获取html');
      } catch (e) {
        final cached = (await Storage.read(htmlCacheKey(url))).trim();
        if (cached.isEmpty) throw Exception('获取在线书源失败:$e');
        log?.call('html 加载失败 使用缓存:$e');
        html = cached;
      }
      base = url;
    }
    if (html.startsWith('@aes')) throw Exception('解密失败: 不支持加密书源');
    return (html: html, baseUrl: base);
  }

  Future<void> _start() async {
    sid = const Uuid().v4();
    controller = SourceJsEngine.create(const SourceJsEngineOptions());
    controller.onConsole = (m) => debugPrint('${source.bookSourceName} console: $m');
    controller.onLoadStop = (url) async {
      if ((SourceRuntime.webViewUA ?? '').isNotEmpty) return;
      try {
        final ua = jsArg(await controller.evaluateJavascript('navigator.userAgent'));
        if (ua.isNotEmpty) SourceRuntime.webViewUA = ua;
      } catch (_) {}
    };
    registerHandlers();
    final page = await loadPage(source, log: (l) => debugPrint('${source.bookSourceName}: $l'));
    await WebCookies.push(page.baseUrl);
    await controller.loadData(page.html, baseUrl: page.baseUrl);
  }

  Future<void> dispose() async {
    if (destroyed) return;
    destroyed = true;
    failPending(StateError('页面已销毁'));
    try {
      await controller.dispose();
    } catch (_) {}
  }

  /// 0xe097d8: waits for the page's `CookieJar` call.
  Future<void> waitReady() async {
    final deadline = DateTime.now().add(readyTimeout);
    while (!ready) {
      if (destroyed) throw StateError('页面已销毁');
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('等待页面就绪超时', readyTimeout);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Runs `expr` (a call of a page function) and returns its value normalised to text.
  Future<String> call(String expr, Duration timeout, {void Function(String line)? log, String? step}) async {
    _busy++;
    try {
      if (!ready) {
        log?.call('等待书源 html 加载完成');
        await waitReady();
        log?.call('书源已加载完成');
      }
      touch();
      if (step != null) log?.call(step);
      final v = await evalCall(expr, timeout);
      touch();
      return jsArg(v);
    } finally {
      _busy--;
    }
  }

  /// Runs [action] with the debugger sinks pointed at [log] / [text].
  Future<T> _debugged<T>(void Function(String line)? log, void Function(int type, String html)? text, Future<T> Function() action) async {
    if (log == null && text == null) return action();
    final oldLog = debugLog, oldText = debugText;
    debugLog = log ?? oldLog;
    debugText = text ?? oldText;
    try {
      return await action();
    } finally {
      debugLog = oldLog;
      debugText = oldText;
    }
  }

  static String _q(Object? v) => jsonEncode(v);

  Future<List<Book>> search(String key, int page, {String env = 'search', void Function(String)? log, void Function(int, String)? text}) =>
      _debugged(log, text, () async => SourceParse.books(await call('search(${_q(key)},$page,${_q(env)})', searchTimeout, log: log, step: '︾开始解析搜索页')));

  Future<Book> info(String bookUrl, {void Function(String)? log, void Function(int, String)? text}) =>
      _debugged(log, text, () async => SourceParse.book(await call('info(${_q(bookUrl)})', infoTimeout, log: log, step: '︾开始解析详情页')));

  Future<List<BookChapter>> chapter(String tocUrl, String bookUrl, {void Function(String)? log, void Function(int, String)? text}) => _debugged(
      log, text, () async => SourceParse.chapters(await call('chapter(${_q(tocUrl)},${_q(bookUrl)})', chapterTimeout, log: log, step: '︾开始解析目录页')));

  Future<String> content(String url, String bookUrl, int index, {void Function(String)? log, void Function(int, String)? text}) =>
      _debugged(log, text, () => call('content(${_q(url)},${_q(bookUrl)},$index)', contentTimeout, log: log, step: '︾开始解析正文页'));

  Future<String> getfinds() => call('getfinds()', findTimeout);

  Future<List<Book>> find(String url, int page, {void Function(String)? log, void Function(int, String)? text}) =>
      _debugged(log, text, () async => SourceParse.books(await call('find(${_q(url)},$page)', findTimeout, log: log, step: '︾开始解析发现页')));

  Future<String> getloginurl() => call('getloginurl()', loginTimeout);

  Future<String> login() => call('login()', loginTimeout);

  Future<String> pay(String bookUrl, String url) => call('pay(${_q(bookUrl)},${_q(url)})', payTimeout);

  Future<String> gethelp() => call('gethelp()', helpTimeout);

  Future<String> filter() => call('filter()', findTimeout);

  Future<String> findfilter(String url) => call('findfilter(${_q(url)})', findTimeout);

  /// 0xe085bc: event callbacks (`clickBookName`, `addBookShelf`, …); true = the page consumed the event.
  Future<bool> callbackjs(String event, String bookJson) async {
    final v = await call('callbackjs(${_q(event)},${_q(bookJson)})', findTimeout);
    return v == 'true';
  }

  /// `shouldOverrideUrlLoading(url)` of the page (startBrowserWithShouldOverrideUrlLoading); anything but `false` allows.
  Future<bool> shouldOverrideUrlLoading(String url) async {
    try {
      return await call('shouldOverrideUrlLoading(${_q(url)})', const Duration(seconds: 30)) != 'false';
    } catch (e) {
      debugPrint('shouldOverrideUrlLoading: $e');
      return true;
    }
  }

  /// 0xeb5dc8: `imagedecrypt(url, base64 image)` must return the bytes (an array of numbers); an empty answer keeps [bytes].
  Future<Uint8List> imagedecrypt(String url, Uint8List bytes) async {
    _busy++;
    try {
      await waitReady();
      touch();
      final v = SourceParse.decode(await evalCall('imagedecrypt(${_q(url)},${_q(base64Encode(bytes))})', imageTimeout));
      if (v is List && v.isNotEmpty) return Uint8List.fromList([for (final e in v) e is num ? e.toInt() & 0xff : int.tryParse('$e') ?? 0]);
      return bytes;
    } finally {
      _busy--;
    }
  }

  /// Runs a piece of page JavaScript (explore actions, login buttons, `@onclick:` buttons) and returns its value as text.
  Future<String> runJs(String code) => call('(async function(){ return await eval(${_q(code)}); })()', findTimeout);

  @override
  void reloadRunner() => unawaited(SourceRun.remove(source.bookSourceUrl));

  @override
  Future<void> onRefreshExplore() async {
    await Storage.delete(Baswebview.exploreKey(source.bookSourceUrl));
    ExploreRefresh.notify(source.bookSourceUrl);
  }
}

