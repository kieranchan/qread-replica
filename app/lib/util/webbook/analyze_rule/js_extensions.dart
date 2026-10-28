// util/webbook/analyze_rule/js_extensions.dart - the `java.*` object of rule JavaScript (upstream Legado's `JsExtensions`). AnalyzeRule and
// AnalyzeUrl extend it (so `java` *is* the rule analyzer, as in Legado: `java.getString(..)`, `java.put(..)`, `java.ajax(..)` live
// side by side). Native names follow rule_engine.txt section 3; crypto/encoding is implemented in Dart (js_encode_utils.dart).
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../chinese_utils.dart';
import '../../format.dart';
import '../../html/entities.dart';
import '../../http.dart';
import '../../legado/cookie_jar.dart';
import '../../legado/html_formatter.dart';
import '../../legado/js_bindable.dart';
import '../../legado/js_bindable_compat.dart';
import '../../legado/js_engines.dart';
import '../../legado/js_runtime.dart';
import '../model/base_source.dart';
import '../model/book.dart';
import '../model/book_chapter.dart';
import '../model/shared_js_scope.dart';
import '../util/cache_manager.dart';
import '../util/client_app.dart';
import '../util/network_utils.dart';
import '../util/str_response.dart';
import 'analyze_url.dart';
import 'js_encode_utils.dart';
import 'js_files.dart';
import 'query_ttf.dart';
import 'rule_data.dart';

abstract class JsExtensions extends JsBindable {
  BaseSource? getSource();

  /// The variable store written by `java.put` (chapter first, then book, then the plain rule data).
  RuleDataInterface? get ruleDataForJs => null;
  BookChapter? get chapterForJs => null;
  BaseBook? get bookForJs => null;

  /// Extra script bindings (`result`, `baseUrl`, `page` ...) added by subclasses on top of the common ones.
  void fillBindings(JsBindings b) {}

  /// Runs [js] with the standard bindings (`java cookie cache source book chapter`) plus [values].
  Future<Object?> runJs(String js, {Map<String, Object?>? values}) async {
    JsEngines.install();
    final b = JsBindings(objects: {'java': this, 'cookie': CookieBinding.instance, 'cache': CacheBinding.instance});
    final src = getSource();
    if (src != null) b.objects['source'] = src;
    final book = bookForJs;
    if (book != null) b.objects['book'] = book;
    final ch = chapterForJs;
    if (ch != null) b.objects['chapter'] = ch;
    fillBindings(b);
    if (values != null) b.values.addAll(values);
    final lib = await SharedJsScope.jsLibOf(src);
    return JsScriptRunner.run(js, b, jsLib: lib);
  }

  // variables used by AnalyzeRule/AnalyzeUrl ----------------------------------------------------------------------------------------
  String putVar(String key, String value) {
    final ch = chapterForJs;
    if (ch != null) {
      ch.putVariable(key, value);
    } else {
      final book = bookForJs;
      if (book != null) {
        book.putVariable(key, value);
      } else {
        ruleDataForJs?.putVariable(key, value);
      }
    }
    return value;
  }

  String getVar(String key) {
    final book = bookForJs;
    final ch = chapterForJs;
    if (key == 'bookName' && book != null) return book.name;
    if (key == 'title' && ch != null) return ch.title;
    return ch?.variableMap[key] ?? book?.variableMap[key] ?? ruleDataForJs?.variableMap[key] ?? '';
  }

  // network helpers --------------------------------------------------------------------------------------------------------------
  Future<StrResponse> _connect(String urlStr, Map<String, String>? header) async {
    final src = getSource();
    final headers = <String, String>{...(await src?.getHeaderMap(true) ?? <String, String>{}), ...?header};
    final au = await AnalyzeUrl.create(urlStr, source: src, ruleData: ruleDataForJs, headerMapF: headers, chapter: chapterForJs);
    return au.getStrResponse();
  }

  Map<String, String>? _headerArg(Object? v) {
    if (v is Map) return v.map((k, val) => MapEntry('$k', '$val'));
    if (v is String && v.trim().startsWith('{')) {
      final d = jsonDecode(v);
      if (d is Map) return d.map((k, val) => MapEntry('$k', '$val'));
    }
    return null;
  }

  Object? _await(String key, Future<Object?> Function() loader) => jsAwait(key, loader);

  // crypto helpers ---------------------------------------------------------------------------------------------------------------
  List<int> _bytesOf(Object? v) => jsToBytes(v);

  Uint8List _symAny(String transformation, Object? key, Object? iv, List<int> data, bool encrypt) => JsEncodeUtils.symmetric(
        transformation: transformation,
        key: _bytesOf(key),
        iv: iv == null || (iv is String && iv.isEmpty) ? null : _bytesOf(iv),
        data: data,
        encrypt: encrypt,
      );

  static const List<String> _methods = [
    'ajax', 'ajaxAll', 'connect', 'get', 'post', 'head', 'put', 'log', 'logType', 'toast', 'longToast', 'getCookie', 'base64Decode',
    'base64DecodeToByteArray', 'base64DecodeToString', 'base64Encode', 'base64EncodeToString', 'base64UrlEncode', 'base64UrlDecode',
    'hexDecodeToString', 'hexDecodeToByteArray', 'hexEncodeToString', 'md5Encode', 'md5Encode16', 'md5Encode32', 'sha1Encode',
    'sha256Encode', 'sha512Encode', 'digestHex', 'digestBase64Str', 'HMacHex', 'HMacBase64', 'urlEncode', 'urlDecode', 'encodeURI',
    'encodeURIComponent', 'decodeURI', 'decodeURIComponent', 'escape', 'unescape', 'htmlEncode', 'htmlDecode', 'htmlFormat', 't2s',
    's2t', 'timeFormat', 'timeFormatUTC', 'randomUUID', 'androidId', 'getWebViewUA', 'toNumChapter', 'utf8ToGbk', 'utf8ToGbkUrlEncoded',
    'strToBytes', 'bytesToStr', 'toURL', 'importScript', 'aesDecodeToString', 'aesDecodeToByteArray', 'aesEncodeToString',
    'aesEncodeToByteArray', 'aesBase64DecodeToString', 'aesBase64DecodeToByteArray', 'aesEncodeToBase64String',
    'aesEncodeToBase64ByteArray', 'desDecodeToString', 'desBase64DecodeToString', 'desEncodeToString', 'desEncodeToBase64String',
    'tripleDESDecodeStr', 'tripleDESDecodeArgsBase64Str', 'tripleDESEncodeBase64Str', 'tripleDESEncodeArgsBase64Str',
    'createSymmetricCrypto', 'startBrowser', 'startBrowserAwait', 'openUrl', 'webView', 'webViewGetSource', 'webViewGetOverrideUrl',
    'getVerificationCode', 'copyText', 'reLoginView', 'upLoginData', 'readFile', 'readTxtFile', 'deleteFile', 'unzipFile',
    'getTxtInFolder', 'unArchiveFile', 'cacheFile', 'downloadFile', 'queryTTF', 'queryBase64TTF', 'replaceFont', 'getZipStringContent', 'getZipByteArrayContent',
    'refreshBook', 'refreshContent', 'getString', 'getStringList', 'getElement', 'getElements', 'setContent', 'getSource',
  ];

  @override
  Iterable<String> get jsMethods => _methods;

  @override
  Object? jsGet(String name) => name == 'source' ? getSource() : JsBindable.noMember;

  @override
  Object? jsCall(String name, List<Object?> args) {
    String s(int i) => i < args.length && args[i] != null ? jsToString(args[i]) : '';
    String? so(int i) => i < args.length && args[i] != null ? jsToString(args[i]) : null;
    switch (name) {
      // ---- network ----
      case 'ajax':
        {
          final a = args.isEmpty ? '' : args[0];
          final urlStr = a is List ? (a.isEmpty ? '' : jsToString(a.first)) : jsToString(a);
          final r = _await('ajax:$urlStr', () async {
            try {
              final res = await _connect(urlStr, null);
              return res.body;
            } catch (e) {
              return e.toString();
            }
          });
          return r;
        }
      case 'ajaxAll':
        {
          final urls = args.isNotEmpty && args[0] is List ? (args[0] as List).map(jsToString).toList() : <String>[];
          final r = _await('ajaxAll:${urls.join('\u0001')}', () async {
            final out = <Object?>[];
            for (final u in urls) {
              try {
                out.add((await _connect(u, null)).toPlain());
              } catch (e) {
                out.add(StrResponse(u, e.toString(), code: 0).toPlain());
              }
            }
            return out;
          });
          return r;
        }
      case 'connect':
        {
          final urlStr = s(0);
          final h = args.length > 1 ? _headerArg(args[1]) : null;
          return _await('connect:$urlStr:${jsonEncode(h)}', () async {
            try {
              return (await _connect(urlStr, h)).toPlain();
            } catch (e) {
              return StrResponse(urlStr, e.toString(), code: 0).toPlain();
            }
          });
        }
      case 'get':
        if (args.length == 1) return getVar(s(0));
        {
          final urlStr = s(0);
          final h = _headerArg(args.length > 1 ? args[1] : null);
          return _await('get:$urlStr:${jsonEncode(h)}', () async => (await _connect(urlStr, h)).toPlain());
        }
      case 'head':
        {
          final urlStr = s(0);
          final h = _headerArg(args.length > 1 ? args[1] : null);
          return _await('head:$urlStr:${jsonEncode(h)}', () async {
            final src = getSource();
            final headers = <String, String>{...(await src?.getHeaderMap(true) ?? <String, String>{}), ...?h};
            final au = await AnalyzeUrl.create(urlStr, source: src, ruleData: ruleDataForJs, headerMapF: headers, method: 'HEAD');
            return (await au.getStrResponse()).toPlain();
          });
        }
      case 'post':
        {
          final urlStr = s(0);
          final body = s(1);
          final h = _headerArg(args.length > 2 ? args[2] : null);
          return _await('post:$urlStr:$body:${jsonEncode(h)}', () async {
            final src = getSource();
            final headers = <String, String>{...(await src?.getHeaderMap(true) ?? <String, String>{}), ...?h};
            final au = await AnalyzeUrl.create(urlStr, source: src, ruleData: ruleDataForJs, headerMapF: headers, method: 'POST', bodyOverride: body);
            return (await au.getStrResponse()).toPlain();
          });
        }
      case 'put':
        return putVar(s(0), s(1));
      case 'importScript':
        {
          final path = s(0);
          if (path.startsWith('http://') || path.startsWith('https://')) {
            final key = 'importScript:$path';
            final cached = CacheManager.getString(key);
            if (cached != null) return cached;
            final body = _await(key, () async {
              final r = await _connect(path, null);
              final text = r.body ?? '';
              CacheManager.put(key, text, saveTimeSeconds: 3600);
              return text;
            });
            return body;
          }
          throw JsHostError('importScript: only http(s) scripts are supported ($path)');
        }
      // ---- logging / ui ----
      case 'log':
        JsEvalContext.current?.logs.add(s(0));
        return args.isEmpty ? null : args[0];
      case 'logType':
        return null;
      case 'toast':
        LegadoPlatform.toast?.call(s(0));
        return null;
      case 'longToast':
        (LegadoPlatform.longToast ?? LegadoPlatform.toast)?.call(s(0));
        return null;
      case 'copyText':
        LegadoPlatform.copyText?.call(s(0));
        return null;
      case 'reLoginView':
        LegadoPlatform.reLoginView?.call(getSource()?.getKey() ?? '');
        return null;
      case 'openUrl':
      case 'startBrowser':
        {
          final cb = LegadoPlatform.openBrowser;
          if (cb == null) throw JsHostError('$name is not available on this platform');
          cb(s(0), s(1));
          return null;
        }
      case 'startBrowserAwait':
        {
          final cb = LegadoPlatform.startBrowserAwait;
          if (cb == null) throw JsHostError('startBrowserAwait is not available on this platform');
          final u = s(0), t = s(1);
          final refetch = args.length > 2 && args[2] == true;
          return _await('startBrowserAwait:$u:$t:$refetch', () async => (await cb(u, t, refetch)) ?? '');
        }
      case 'webView':
      case 'webViewGetSource':
      case 'webViewGetOverrideUrl':
        {
          final cb = LegadoPlatform.webView;
          if (cb == null) throw JsHostError('$name is not available on this platform');
          final html = so(0), url = s(1), js = so(2);
          final rx = name == 'webView' ? null : so(3);
          return _await('$name:$html:$url:$js:$rx', () async {
            final r = await cb(
              html: html == 'null' ? null : html,
              url: url,
              js: js,
              sourceRegex: name == 'webViewGetSource' ? rx : null,
              overrideUrlRegex: name == 'webViewGetOverrideUrl' ? rx : null,
            );
            return r;
          });
        }
      case 'getVerificationCode':
        {
          final cb = LegadoPlatform.getVerificationCode;
          if (cb == null) throw JsHostError('getVerificationCode is not available on this platform');
          final u = s(0);
          return _await('getVerificationCode:$u', () async => (await cb(u)) ?? '');
        }
      case 'upLoginData':
        {
          final src = getSource();
          if (src != null && args.isNotEmpty && args[0] is Map) {
            final m = src.getLoginInfoMap();
            (args[0] as Map).forEach((k, v) => m[jsToString(k)] = jsToString(v));
            src.putLoginInfo(m.toJsonString());
          }
          return null;
        }
      // ---- cookies ----
      case 'getCookie':
        if (args.length > 1 && args[1] != null) return CookieStore.getKey(s(0), s(1));
        return CookieStore.getCookie(s(0));
      // ---- encoding / hashing ----
      case 'base64Decode':
      case 'base64DecodeToString':
        return JsEncodeUtils.base64Decode(s(0), args.length > 1 ? s(1) : 'UTF-8');
      case 'base64DecodeToByteArray':
        return JsEncodeUtils.base64DecodeBytes(s(0)).toList();
      case 'base64Encode':
      case 'base64EncodeToString':
        return JsEncodeUtils.base64Encode(s(0));
      case 'base64UrlEncode':
        return JsEncodeUtils.base64UrlEncode(s(0));
      case 'base64UrlDecode':
        return JsEncodeUtils.base64Decode(s(0));
      case 'hexDecodeToString':
        return JsEncodeUtils.hexDecodeToString(s(0));
      case 'hexDecodeToByteArray':
        return JsEncodeUtils.hexDecodeBytes(s(0)).toList();
      case 'hexEncodeToString':
        return args.isNotEmpty && args[0] is List ? JsEncodeUtils.hexEncodeBytes(_bytesOf(args[0])) : JsEncodeUtils.hexEncode(s(0));
      case 'md5Encode':
      case 'md5Encode32':
        return JsEncodeUtils.md5Encode(s(0));
      case 'md5Encode16':
        return JsEncodeUtils.md5Encode16(s(0));
      case 'sha1Encode':
        return JsEncodeUtils.sha1Encode(s(0));
      case 'sha256Encode':
        return JsEncodeUtils.sha256Encode(s(0));
      case 'sha512Encode':
        return JsEncodeUtils.sha512Encode(s(0));
      case 'digestHex':
        return JsEncodeUtils.digestHex(s(0), s(1));
      case 'digestBase64Str':
        return JsEncodeUtils.digestBase64(s(0), s(1));
      case 'HMacHex':
        return JsEncodeUtils.hmacHex(s(0), s(1), s(2));
      case 'HMacBase64':
        return JsEncodeUtils.hmacBase64(s(0), s(1), s(2));
      case 'urlEncode':
        return JsEncodeUtils.urlEncode(s(0), so(1));
      case 'urlDecode':
        return JsEncodeUtils.urlDecode(s(0), so(1));
      case 'encodeURI':
        return args.length > 1 ? JsEncodeUtils.urlEncode(s(0), so(1)) : JsEncodeUtils.encodeURI(s(0));
      case 'encodeURIComponent':
        return JsEncodeUtils.encodeURIComponent(s(0));
      case 'decodeURI':
      case 'decodeURIComponent':
        return Uri.decodeFull(s(0));
      case 'escape':
        return JsEncodeUtils.escape(s(0));
      case 'unescape':
        return JsEncodeUtils.unescape(s(0));
      case 'htmlEncode':
        return htmlEncode(s(0));
      case 'htmlDecode':
        return htmlDecode(s(0));
      case 'htmlFormat':
        return HtmlFormatter.formatKeepImg(s(0));
      case 't2s':
        return ChineseUtils.toSimplified(s(0));
      case 's2t':
        return ChineseUtils.toTraditional(s(0));
      case 'timeFormat':
        {
          final ms = args.isNotEmpty && args[0] is num ? (args[0] as num).toInt() : int.tryParse(s(0)) ?? 0;
          return formatDate(DateTime.fromMillisecondsSinceEpoch(ms), 'yyyy/MM/dd HH:mm');
        }
      case 'timeFormatUTC':
        {
          final ms = args.isNotEmpty && args[0] is num ? (args[0] as num).toInt() : int.tryParse(s(0)) ?? 0;
          final fmt = s(1);
          final sh = args.length > 2 && args[2] is num ? (args[2] as num).toInt() : int.tryParse(s(2)) ?? 0;
          return formatDate(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(Duration(hours: sh)), fmt);
        }
      case 'randomUUID':
        return const Uuid().v4();
      case 'androidId':
        return LegadoPlatform.deviceId;
      case 'getWebViewUA':
        return LegadoPlatform.webViewUserAgent ?? AppHttp.userAgent;
      case 'toNumChapter':
        return Format.toNumChapter(args.isEmpty || args[0] == null ? null : s(0));
      case 'utf8ToGbk':
        return String.fromCharCodes(AppHttp.encodeWith(s(0), 'gbk'));
      case 'utf8ToGbkUrlEncoded':
        return JsEncodeUtils.urlEncode(s(0), 'gbk');
      case 'strToBytes':
        return AppHttp.encodeWith(s(0), so(1) ?? 'utf-8');
      case 'bytesToStr':
        return AppHttp.decodeWith(_bytesOf(args.isEmpty ? const [] : args[0]), so(1) ?? 'utf-8') ?? '';
      case 'toURL':
        return _toUrl(s(0), so(1));
      // ---- symmetric crypto ----
      case 'aesDecodeToString':
        return utf8.decode(_symAny(s(2), args[1], args[3], JsEncodeUtils.decodeHexOrBase64(s(0)), false), allowMalformed: true);
      case 'aesDecodeToByteArray':
        return _symAny(s(2), args[1], args[3], JsEncodeUtils.decodeHexOrBase64(s(0)), false).toList();
      case 'aesBase64DecodeToString':
        return utf8.decode(_symAny(s(2), args[1], args[3], JsEncodeUtils.base64DecodeBytes(s(0)), false), allowMalformed: true);
      case 'aesBase64DecodeToByteArray':
        return _symAny(s(2), args[1], args[3], JsEncodeUtils.base64DecodeBytes(s(0)), false).toList();
      case 'aesEncodeToString':
        return String.fromCharCodes(_symAny(s(2), args[1], args[3], utf8.encode(s(0)), true));
      case 'aesEncodeToByteArray':
        return _symAny(s(2), args[1], args[3], utf8.encode(s(0)), true).toList();
      case 'aesEncodeToBase64String':
        return base64.encode(_symAny(s(2), args[1], args[3], utf8.encode(s(0)), true));
      case 'aesEncodeToBase64ByteArray':
        return base64.encode(_symAny(s(2), args[1], args[3], utf8.encode(s(0)), true)).codeUnits;
      case 'desDecodeToString':
        return utf8.decode(_symAny(s(2), args[1], args[3], JsEncodeUtils.decodeHexOrBase64(s(0)), false), allowMalformed: true);
      case 'desBase64DecodeToString':
        return utf8.decode(_symAny(s(2), args[1], args[3], JsEncodeUtils.base64DecodeBytes(s(0)), false), allowMalformed: true);
      case 'desEncodeToString':
        return String.fromCharCodes(_symAny(s(2), args[1], args[3], utf8.encode(s(0)), true));
      case 'desEncodeToBase64String':
        return base64.encode(_symAny(s(2), args[1], args[3], utf8.encode(s(0)), true));
      case 'tripleDESDecodeStr':
      case 'tripleDESDecodeArgsBase64Str':
        return utf8.decode(
            _symAny('DESede/${s(2)}/${s(3)}', args[1], args.length > 4 ? args[4] : null, JsEncodeUtils.base64DecodeBytes(s(0)), false),
            allowMalformed: true);
      case 'tripleDESEncodeBase64Str':
      case 'tripleDESEncodeArgsBase64Str':
        return base64.encode(_symAny('DESede/${s(2)}/${s(3)}', args[1], args.length > 4 ? args[4] : null, utf8.encode(s(0)), true));
      case 'createSymmetricCrypto':
        return SymmetricCryptoBinding(s(0), args.length > 1 ? args[1] : '', args.length > 2 ? args[2] : null);
      // ---- files (sandboxed like Legado, js_files.dart) / zip / fonts (query_ttf.dart) ----
      case 'readFile':
        return JsFiles.readFile(s(0))?.toList();
      case 'readTxtFile':
        return JsFiles.readTxtFile(s(0), so(1));
      case 'deleteFile':
        return JsFiles.deleteFile(s(0));
      case 'unzipFile':
      case 'unArchiveFile':
        return JsFiles.unzipFile(s(0));
      case 'getTxtInFolder':
        return JsFiles.getTxtInFolder(s(0));
      case 'cacheFile':
        {
          // the original (0x111922c): key md5Encode16(url), cached text or a fresh request stored with saveTime
          final urlStr = s(0);
          final saveTime = args.length > 1 && args[1] is num ? (args[1] as num).toInt() : int.tryParse(s(1)) ?? 0;
          final key = JsEncodeUtils.md5Encode16(urlStr);
          final cached = CacheManager.getString(key);
          if (cached != null && cached.isNotEmpty) return cached;
          return _await('cacheFile:$urlStr', () async {
            final text = (await _connect(urlStr, null)).body ?? '';
            CacheManager.put(key, text, saveTimeSeconds: saveTime);
            return text;
          });
        }
      case 'downloadFile':
        {
          if (args.length > 1) {
            // deprecated Legado form downloadFile(hexContent, url)
            final url = s(1);
            return JsFiles.saveDownload(url, JsEncodeUtils.hexDecodeBytes(s(0)), JsFiles.suffixOf(url));
          }
          final urlStr = s(0);
          return _await('downloadFile:$urlStr', () async {
            final au = await AnalyzeUrl.create(urlStr, source: getSource(), ruleData: ruleDataForJs, chapter: chapterForJs);
            return JsFiles.saveDownload(urlStr, await au.getByteArray(), JsFiles.suffixOf(urlStr, au.type));
          });
        }
      case 'getZipStringContent':
      case 'getZipByteArrayContent':
        {
          final urlStr = s(0), path = s(1);
          final bytes = _bytesFromUrlOrHex(urlStr);
          final entry = JsFiles.zipEntry(bytes, path);
          if (name == 'getZipByteArrayContent') return entry?.toList();
          if (entry == null) return '';
          return AppHttp.decodeBody(entry, charset: so(2));
        }
      case 'queryTTF':
      case 'queryBase64TTF':
        return _queryTTF(args.isEmpty ? null : args[0], args.length < 2 || args[1] != false);
      case 'replaceFont':
        {
          QueryTTF? font(int i) => i < args.length && args[i] is QueryTTF ? args[i] as QueryTTF : null;
          final filter = args.length > 3 && (args[3] == true || s(3) == 'true');
          return QueryTTF.replaceFont(s(0), font(1), font(2), filter: filter);
        }
      case 'refreshBook':
      case 'refreshContent':
        return null;
      case 'getSource':
        return getSource();
    }
    return super.jsCall(name, args);
  }

  /// Bytes of an absolute url (fetched through the source) or of a hex string (Legado `getZipByteArrayContent`).
  List<int> _bytesFromUrlOrHex(String urlStr) {
    if (urlStr.startsWith('http://') || urlStr.startsWith('https://')) {
      final r = _await('bytes:$urlStr', () async {
        final au = await AnalyzeUrl.create(urlStr, source: getSource(), ruleData: ruleDataForJs, chapter: chapterForJs);
        return (await au.getByteArray()).toList();
      });
      return jsToBytes(r);
    }
    return JsEncodeUtils.hexDecodeBytes(urlStr);
  }

  static final Map<String, QueryTTF> _ttfCache = {};

  static List<int>? _sandboxFile(String path) {
    try {
      return JsFiles.readFile(path);
    } catch (_) {
      return null;
    }
  }

  /// Legado `queryTTF(data, useCache)`: [data] is a font url, a `data:` url, a file of the sandbox, base64 text or bytes.
  QueryTTF? _queryTTF(Object? data, bool useCache) {
    if (data == null) return null;
    String key;
    if (data is List) {
      key = JsEncodeUtils.md5Encode16(String.fromCharCodes(jsToBytes(data)));
    } else {
      key = JsEncodeUtils.md5Encode16(jsToString(data));
    }
    if (useCache) {
      final hit = _ttfCache[key];
      if (hit != null) return hit;
    }
    List<int> bytes;
    if (data is List) {
      bytes = jsToBytes(data);
    } else {
      final str = jsToString(data).trim();
      if (str.startsWith('http://') || str.startsWith('https://')) {
        bytes = _bytesFromUrlOrHex(str);
      } else if (str.startsWith('data:')) {
        bytes = base64.decode(base64.normalize(str.substring(str.indexOf(',') + 1)));
      } else if (str.length < 512 && (str.startsWith('/') || str.contains('.')) && _sandboxFile(str) != null) {
        bytes = _sandboxFile(str)!;
      } else {
        bytes = JsEncodeUtils.base64DecodeBytes(str);
      }
    }
    if (bytes.isEmpty) return null;
    final q = QueryTTF(bytes);
    if (useCache) {
      if (_ttfCache.length >= 16) _ttfCache.remove(_ttfCache.keys.first);
      _ttfCache[key] = q;
    }
    return q;
  }

  Map<String, Object?> _toUrl(String url, String? base) {
    final abs = NetworkUtils.getAbsoluteURL(base, url);
    Uri u;
    try {
      u = Uri.parse(abs);
    } on FormatException {
      return {'href': abs};
    }
    final port = u.hasPort ? '${u.port}' : '';
    return {
      'href': abs,
      'origin': u.hasScheme ? '${u.scheme}://${u.host}${port.isEmpty ? '' : ':$port'}' : '',
      'protocol': '${u.scheme}:',
      'host': '${u.host}${port.isEmpty ? '' : ':$port'}',
      'hostname': u.host,
      'port': port,
      'pathname': u.path.isEmpty ? '/' : u.path,
      'search': u.hasQuery ? '?${u.query}' : '',
      'hash': u.hasFragment ? '#${u.fragment}' : '',
      'searchParams': u.queryParameters,
    };
  }
}

/// A JS-extensions instance for a bare source (header JS, login JS, explore JS ...).
class SourceJsExtensions extends JsExtensions {
  final BaseSource source;
  SourceJsExtensions(this.source);

  @override
  BaseSource? getSource() => source;
}

/// `java.createSymmetricCrypto(transformation, key, iv)` (hutool `SymmetricCrypto`).
class SymmetricCryptoBinding extends JsBindable {
  final String transformation;
  final List<int> key;
  final List<int>? iv;

  SymmetricCryptoBinding(this.transformation, Object? key, Object? iv)
      : key = jsToBytes(key),
        iv = iv == null ? null : jsToBytes(iv);

  @override
  Iterable<String> get jsMethods => const ['decrypt', 'decryptStr', 'encrypt', 'encryptBase64', 'encryptHex', 'setIv'];

  List<int> _data(Object? v, {required bool decrypt}) {
    if (v is List) return jsToBytes(v);
    final s = jsToString(v);
    return decrypt ? JsEncodeUtils.decodeHexOrBase64(s) : utf8.encode(s);
  }

  Uint8List _run(Object? v, bool encrypt) =>
      JsEncodeUtils.symmetric(transformation: transformation, key: key, iv: iv, data: _data(v, decrypt: !encrypt), encrypt: encrypt);

  @override
  Object? jsCall(String name, List<Object?> args) {
    final a = args.isEmpty ? null : args[0];
    switch (name) {
      case 'decrypt':
        return _run(a, false).toList();
      case 'decryptStr':
        return utf8.decode(_run(a, false), allowMalformed: true);
      case 'encrypt':
        return _run(a, true).toList();
      case 'encryptBase64':
        return base64.encode(_run(a, true));
      case 'encryptHex':
        return JsEncodeUtils.hexEncodeBytes(_run(a, true));
    }
    return super.jsCall(name, args);
  }
}
