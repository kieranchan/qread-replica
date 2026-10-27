// util/webbook/analyze_rule/analyze_url.dart - `url,{json options}` parsing and the HTTP request it describes (Legado `AnalyzeUrl`).
// Option keys (rule_engine.txt section 4): method type headers body charset webView useWebView webJs js sourceRegex retry proxy
// click usePhone escape hasLoginHeader headerMapF ruleData. `{{page}}`, `{{key}}`, `{{ js }}`, `<a,b,c>` page lists, `@js:`/`<js>`.
import 'dart:convert';
import 'dart:typed_data';

import '../../format.dart';
import '../../http.dart';
import '../../json.dart';
import '../../legado/js_bindable_compat.dart';
import '../../legado/js_runtime.dart';
import '../model/base_source.dart';
import '../model/book.dart';
import '../model/book_chapter.dart';
import '../util/client_app.dart';
import '../util/network_utils.dart';
import '../util/str_response.dart';
import 'concurrent_rate_limiter.dart';
import 'js_encode_utils.dart';
import 'js_extensions.dart';
import 'rule_analyzer.dart';
import 'rule_data.dart';

enum RequestMethod { get, post, head }

/// The `{json}` part of a url rule.
class UrlOption {
  String? method;
  String? charset;
  Object? headers;
  Object? body;
  int retry = 0;
  String? type;
  bool webView = false;
  String? webJs;
  String? sourceRegex;
  String? js;
  String? proxy;

  UrlOption();

  factory UrlOption.fromJson(Map<String, dynamic> j) {
    final o = UrlOption();
    o.method = jsonutil.optString(j['method']);
    o.charset = jsonutil.optString(j['charset']);
    o.headers = j['headers'];
    o.body = j['body'];
    o.retry = jsonutil.asInt(j['retry']);
    o.type = jsonutil.optString(j['type']);
    o.webView = jsonutil.asBool(j['webView']) || jsonutil.asBool(j['useWebView']);
    o.webJs = jsonutil.optString(j['webJs']);
    o.sourceRegex = jsonutil.optString(j['sourceRegex']);
    o.js = jsonutil.optString(j['js']);
    o.proxy = jsonutil.optString(j['proxy']);
    return o;
  }
}

class AnalyzeUrl extends JsExtensions {
  static final RegExp paramPattern = NetworkUtils.paramPattern;
  static final RegExp _pagePattern = RegExp(r'<(.*?)>');
  static final RegExp _jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);

  final String mUrl;
  final String? key;
  final int? page;
  final String? speakText;
  final int? speakSpeed;
  String baseUrl;
  final BaseSource? source;
  final RuleDataInterface? ruleData;
  final BookChapter? chapter;
  final Duration? readTimeout;
  Map<String, String>? headerMapF;
  final bool hasLoginHeader;

  late String ruleUrl;
  late String url;
  String? body;
  String? type;
  final Map<String, String> headerMap = {};
  String urlNoQuery = '';
  String? queryStr;
  final Map<String, String> fieldMap = {};
  String? charset;
  RequestMethod method = RequestMethod.get;
  int retry = 0;
  bool useWebView = false;
  String? webJs;
  String? sourceRegex;

  late final ConcurrentRateLimiter _limiter;

  AnalyzeUrl._(
    this.mUrl, {
    this.key,
    this.page,
    this.speakText,
    this.speakSpeed,
    this.baseUrl = '',
    this.source,
    this.ruleData,
    this.chapter,
    this.readTimeout,
    this.headerMapF,
    this.hasLoginHeader = true,
  });

  /// Builds the analyzer and runs the url rule (JS, templates, options). [method]/[bodyOverride] force a request type for
  /// `java.post()` / `java.head()`.
  static Future<AnalyzeUrl> create(
    String mUrl, {
    String? key,
    int? page,
    String? speakText,
    int? speakSpeed,
    String baseUrl = '',
    BaseSource? source,
    RuleDataInterface? ruleData,
    BookChapter? chapter,
    Duration? readTimeout,
    Map<String, String>? headerMapF,
    bool hasLoginHeader = true,
    String? method,
    String? bodyOverride,
  }) async {
    final a = AnalyzeUrl._(mUrl,
        key: key,
        page: page,
        speakText: speakText,
        speakSpeed: speakSpeed,
        baseUrl: baseUrl,
        source: source,
        ruleData: ruleData,
        chapter: chapter,
        readTimeout: readTimeout,
        headerMapF: headerMapF,
        hasLoginHeader: hasLoginHeader);
    a._limiter = ConcurrentRateLimiter(source?.getKey() ?? '', source?.concurrentRate);
    final m = paramPattern.firstMatch(a.baseUrl);
    if (m != null) a.baseUrl = a.baseUrl.substring(0, m.start);
    final hf = a.headerMapF;
    if (hf != null) a.headerMap.addAll(hf);
    await a.initUrl();
    final mm = method?.toUpperCase();
    if (mm == 'POST') {
      a.method = RequestMethod.post;
      if (bodyOverride != null) {
        a.body = bodyOverride;
        a.fieldMap.clear();
        if (!jsonutil.isJson(bodyOverride) && !NetworkUtils.isXmlType(bodyOverride) && !_hasHeader(a.headerMap, 'Content-Type')) {
          a._analyzeFields(bodyOverride);
        }
      }
    } else if (mm == 'HEAD') {
      a.method = RequestMethod.head;
    }
    return a;
  }

  static bool _hasHeader(Map<String, String> h, String name) => h.keys.any((k) => k.toLowerCase() == name.toLowerCase()) && (h[h.keys.firstWhere((k) => k.toLowerCase() == name.toLowerCase())] ?? '').isNotEmpty;

  BaseBook? get _book => ruleData is BaseBook ? ruleData as BaseBook : null;

  @override
  BaseSource? getSource() => source;
  @override
  RuleDataInterface? get ruleDataForJs => ruleData;
  @override
  BookChapter? get chapterForJs => chapter;
  @override
  BaseBook? get bookForJs => _book;

  Future<void> initUrl() async {
    ruleUrl = mUrl;
    await _analyzeJs();
    await _replaceKeyPageJs();
    await _analyzeUrl();
  }

  Future<void> _analyzeJs() async {
    var start = 0;
    final original = ruleUrl;
    for (final m in _jsPattern.allMatches(original)) {
      if (m.start > start) {
        final tmp = original.substring(start, m.start).trim();
        if (tmp.isNotEmpty) ruleUrl = tmp.replaceAll('@result', ruleUrl);
      }
      final r = await evalJS(m.group(2) ?? m.group(1) ?? '', ruleUrl);
      ruleUrl = jsToRuleString(r);
      start = m.end;
    }
    if (ruleUrl.length > start) {
      final tmp = ruleUrl.substring(start).trim();
      if (tmp.isNotEmpty) ruleUrl = tmp.replaceAll('@result', ruleUrl);
    }
  }

  /// Fast path for the overwhelmingly common templates (`key`, `page`, `page-1`, `(page-1)*20`) so that plain sources need no JS engine.
  String? _simpleTemplate(String expr) {
    final e = expr.trim();
    if (e == 'key') return key ?? '';
    if (e == 'page' && page != null) return '$page';
    if (page != null && RegExp(r'^[\d\s+\-*/%().page]+$').hasMatch(e) && e.contains('page') && !e.replaceAll('page', '').contains(RegExp('[a-zA-Z]'))) {
      final v = _arith(e.replaceAll('page', '$page'));
      if (v != null) return v;
    }
    return null;
  }

  static String? _arith(String e) {
    try {
      final p = _Arith(e);
      final v = p.parse();
      return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _replaceKeyPageJs() async {
    if (ruleUrl.contains('{{') && ruleUrl.contains('}}')) {
      final analyze = RuleAnalyzer(ruleUrl);
      final out = await analyze.innerRuleAsync('{{', '}}', (expr) async {
        final simple = _simpleTemplate(expr);
        if (simple != null) return simple;
        final jsEval = await evalJS(expr);
        if (jsEval == null) return '';
        if (jsEval is String) return jsEval;
        if (jsEval is double && jsEval % 1.0 == 0.0) return jsEval.toInt().toString();
        return jsToRuleString(jsEval);
      });
      if (out.isNotEmpty) ruleUrl = out;
    }
    final p = page;
    if (p != null) {
      final original = ruleUrl;
      for (final m in _pagePattern.allMatches(original)) {
        final pages = m.group(1)!.split(',');
        final idx = p < pages.length ? p - 1 : pages.length - 1;
        ruleUrl = ruleUrl.replaceAll(m.group(0)!, pages[idx < 0 ? 0 : idx].trim());
      }
    }
  }

  Future<void> _analyzeUrl() async {
    final urlMatcher = paramPattern.firstMatch(ruleUrl);
    final urlNoOption = urlMatcher != null ? ruleUrl.substring(0, urlMatcher.start) : ruleUrl;
    url = NetworkUtils.getAbsoluteURL(baseUrl, urlNoOption);
    final b = NetworkUtils.getBaseUrl(url);
    if (b != null) baseUrl = b;
    if (urlMatcher != null) {
      final optionStr = ruleUrl.substring(urlMatcher.end);
      final d = jsonutil.tryDecodeLenient(optionStr);
      if (d is Map) {
        final option = UrlOption.fromJson(Map<String, dynamic>.from(d));
        if ((option.method ?? '').toUpperCase() == 'POST') method = RequestMethod.post;
        final headers = option.headers;
        if (headers is Map) {
          headers.forEach((k, v) => headerMap['$k'] = '$v');
        } else if (headers is String) {
          final hm = jsonutil.tryDecodeLenient(headers);
          if (hm is Map) hm.forEach((k, v) => headerMap['$k'] = '$v');
        }
        final ob = option.body;
        if (ob != null) body = ob is String ? ob : jsonEncode(ob);
        type = option.type;
        charset = option.charset;
        retry = option.retry;
        useWebView = option.webView;
        webJs = option.webJs;
        sourceRegex = option.sourceRegex;
        if (option.proxy != null && option.proxy!.isNotEmpty) {
          // TODO(asm 0x174cb0): per-request proxy ("proxy" option / header) is not wired into the Dio adapter.
        }
        final js = option.js;
        if (js != null && js.isNotEmpty) {
          final r = await evalJS(js, url);
          if (r != null) url = jsToRuleString(r);
        }
      }
    }
    final hasUa = headerMap.keys.any((k) => k.toLowerCase() == 'user-agent');
    if (!hasUa) headerMap['User-Agent'] = AppHttp.userAgent;
    urlNoQuery = url;
    switch (method) {
      case RequestMethod.get:
      case RequestMethod.head:
        if (!useWebView) {
          final pos = url.indexOf('?');
          if (pos != -1) {
            _analyzeFields(url.substring(pos + 1));
            urlNoQuery = url.substring(0, pos);
          }
        }
        break;
      case RequestMethod.post:
        final bd = body;
        if (bd != null) {
          if (!jsonutil.isJson(bd) && !NetworkUtils.isXmlType(bd) && !_hasHeader(headerMap, 'Content-Type')) {
            _analyzeFields(bd);
          }
        }
        break;
    }
  }

  /// `k=v&k2=v2` -> [fieldMap] with every value URL-encoded in [charset] (already encoded values are kept).
  void _analyzeFields(String fieldsTxt) {
    queryStr = fieldsTxt;
    for (final query in fieldsTxt.split('&').where((e) => e.trim().isNotEmpty)) {
      final eq = query.indexOf('=');
      final k = eq < 0 ? query : query.substring(0, eq);
      final v = eq < 0 ? '' : query.substring(eq + 1);
      if (k.trim().isEmpty) continue;
      final cs = charset;
      if (cs == null || cs.isEmpty) {
        fieldMap[k] = NetworkUtils.hasUrlEncoded(v) ? v : NetworkUtils.urlEncodeUtf8(v);
      } else if (cs == 'escape') {
        fieldMap[k] = JsEncodeUtils.escape(v);
      } else {
        fieldMap[k] = NetworkUtils.encodeBytes(AppHttp.encodeWith(v, cs));
      }
    }
  }

  // ------------------------------------------------------------------------------------------------------------------------------
  // JS
  // ------------------------------------------------------------------------------------------------------------------------------
  @override
  void fillBindings(JsBindings b) {
    b.values['baseUrl'] = baseUrl;
    b.values['page'] = page;
    b.values['key'] = key;
    b.values['speakText'] = speakText;
    b.values['speakSpeed'] = speakSpeed;
    b.values['title'] = chapter?.title;
  }

  Future<Object?> evalJS(String jsStr, [Object? result]) => runJs(jsStr, values: {'result': result});

  @override
  Iterable<String> get jsMethods => [...super.jsMethods, 'put', 'get'];

  // ------------------------------------------------------------------------------------------------------------------------------
  // request
  // ------------------------------------------------------------------------------------------------------------------------------
  /// The URL actually requested (GET: [urlNoQuery] plus the encoded fields).
  String get requestUrl {
    if (method == RequestMethod.post || fieldMap.isEmpty) return method == RequestMethod.post ? urlNoQuery : url;
    return '$urlNoQuery?${fieldMap.entries.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  String? get requestBody {
    if (method != RequestMethod.post) return null;
    if (fieldMap.isNotEmpty || (body ?? '').trim().isEmpty) {
      return fieldMap.entries.map((e) => '${e.key}=${e.value}').join('&');
    }
    return body;
  }

  Duration get _timeout => readTimeout ?? const Duration(seconds: 30);

  Future<HttpResponse> _send() async {
    await _limiter.acquire();
    final headers = Map<String, String>.from(headerMap);
    final src = source;
    return AppHttp.send(HttpRequest(
      url: requestUrl,
      method: method == RequestMethod.post ? 'POST' : (method == RequestMethod.head ? 'HEAD' : 'GET'),
      headers: headers,
      body: requestBody,
      timeout: _timeout,
      useCookieJar: src?.enabledCookieJar ?? true,
      retry: retry,
    ));
  }

  /// The decoded response (or, with the `type` option, the hex dump of the bytes like Legado's `byteToHexString`).
  ///
  /// [jsStr] / [sourceRegex] (the content rule's `webJs` / `sourceRegex`) turn the request into a WebView load when the host provides
  /// [LegadoPlatform.webView]; without a WebView host the plain HTTP request is used.
  Future<StrResponse> getStrResponse({String? jsStr, String? sourceRegex, bool useWebView = true}) async {
    final wantWeb = (useWebView && this.useWebView) || (jsStr != null && jsStr.isNotEmpty) || (sourceRegex != null && sourceRegex.isNotEmpty);
    if (wantWeb) {
      final wv = LegadoPlatform.webView;
      if (wv != null) {
        final html = await wv(url: url, js: jsStr ?? webJs, sourceRegex: sourceRegex ?? this.sourceRegex, headers: headerMap);
        return StrResponse(url, html ?? '');
      }
      // No WebView host installed: fall back to a plain request (works for most pages that only need cookies).
    }
    final res = await _send();
    if (type != null) {
      return StrResponse(res.url, JsEncodeUtils.hexEncodeBytes(res.bodyBytes), code: res.statusCode, message: res.statusMessage, headers: res.headers, bodyBytes: res.bodyBytes);
    }
    return StrResponse.fromHttp(res, charset: charset);
  }

  Future<Uint8List> getByteArray() async => (await _send()).bodyBytes;

  /// Convenience: the page text only.
  Future<String> getBody() async => (await getStrResponse()).body ?? '';

  /// Keep [Format] linked for callers that import this library for number helpers.
  static bool isTrue(String? s) => Format.isTrue(s);
}

/// Tiny arithmetic evaluator for `{{(page-1)*20}}` style templates (`+ - * / %`, parentheses, unary minus).
class _Arith {
  final String s;
  int i = 0;
  _Arith(this.s);

  double parse() {
    final v = _expr();
    _ws();
    if (i < s.length) throw const FormatException('trailing input');
    return v;
  }

  void _ws() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  double _expr() {
    var v = _term();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final op = s[i++];
        final r = _term();
        v = op == '+' ? v + r : v - r;
      } else {
        return v;
      }
    }
  }

  double _term() {
    var v = _unary();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '*' || s[i] == '/' || s[i] == '%')) {
        final op = s[i++];
        final r = _unary();
        v = op == '*' ? v * r : (op == '/' ? v / r : v % r);
      } else {
        return v;
      }
    }
  }

  double _unary() {
    _ws();
    if (i < s.length && s[i] == '-') {
      i++;
      return -_unary();
    }
    if (i < s.length && s[i] == '(') {
      i++;
      final v = _expr();
      _ws();
      if (i >= s.length || s[i] != ')') throw const FormatException('missing )');
      i++;
      return v;
    }
    final start = i;
    while (i < s.length && (RegExp(r'[\d.]').hasMatch(s[i]))) {
      i++;
    }
    if (start == i) throw const FormatException('number expected');
    return double.parse(s.substring(start, i));
  }
}
