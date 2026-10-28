// util/audio/tts_page.dart — page engines, the original's TTS model: every normal engine (`HttpTts.tp == 0`) is an HTML page whose
// `async function getttsurl(speakText, speechRate, juese, gender)` returns `JSON.stringify({method, url, headers, body})`; the app
// runs the page in a headless web view (flutter_inappwebview, `TtsApi` 0xea3e14 / 0xea3ae0) and dispatches on `method`
// (0xe953c4): `data` (body = base64 audio), `edge`, `volcano`, `mimo`, `mimoclone`, `mimovoicedesign`, `bdtts`, `bdttsclone`, else an
// HTTP request (`get` / `post`, POST bodies as `application/x-www-form-urlencoded` unless the headers say otherwise).
// The built-in engines are created from fixed templates (pp+0x4bf10 page head, pp+0x4bf18.. scripts with `ssssid` / `ssssurl`
// placeholders, reproduced below); the page is `head + <bridge library> + "\n" + script + "\n</html>\n      "`.
//
// Replica: `HttpTts.html` is a Map in the generated model, so a page is kept as `html['page']` (an engine imported from the
// original keeps its page string there too, see data/tts.dart). Pages whose `getttsurl` only returns literals (every built-in
// template) are evaluated in Dart ([TtsPages.literal]); any other page runs in an offstage web view ([WebViewTtsPageHost]) that
// provides `window.flutter_inappwebview.callHandler` and minimal `FlutterJSBridge` / `Http` / `Cache` / `Cookie` classes (a page that
// defines its own classes shadows them). The original's bridge library (static 0x1fcc, it pulls jQuery from a CDN) is not copied.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:webview_flutter/webview_flutter.dart';

import '../../common/common.dart';
import '../../data/user.dart';
import '../../dio/tts_dio_manger.dart';
import '../../storage/storage.dart';
import '../toast.dart';

/// What `getttsurl` returned.
class TtsPageRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final String body;
  const TtsPageRequest(this.method, this.url, this.headers, this.body);

  factory TtsPageRequest.fromJson(Object? v) {
    final m = v is String ? jsonDecode(v) : v;
    if (m is! Map) throw const FormatException('getttsurl 返回格式错误');
    final h = m['headers'];
    final headers = <String, String>{};
    if (h is Map) h.forEach((k, v) => headers['$k'] = '$v');
    if (h is String && h.trim().startsWith('{')) {
      (jsonDecode(h) as Map).forEach((k, v) => headers['$k'] = '$v');
    }
    return TtsPageRequest('${m['method'] ?? 'get'}'.trim().toLowerCase(), '${m['url'] ?? ''}', headers, '${m['body'] ?? ''}');
  }

  Map<String, dynamic> toJson() => {'method': method, 'url': url, 'headers': headers, 'body': body};
}

abstract class TtsPages {
  static const String suffix = '\n</html>\n      ';

  // ---- templates of the original (generated from the string pool) ----
  static const String prefix = '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="UTF-8">\n  <title>默认tts</title>\n</head>\n<body>\n\n</body>\n';
  static const String bdtts = '<script>\n  const flutterBridge = new FlutterJSBridge();\n  const cache = new Cache();\n  const http = new Http();\n  const cookie = new Cookie();\n\n\n  // tts链接返回方式 ，不可缺少参数\n  // 当method 为 data 时我们会直接将body base64解码后的结果作为音频播放\n  //juese参数当用户开启多角色时会传入\n  //gender 参数当用户开启多角色时会传入 male 为男 female 为女 unknown为未知\n  //\n  // 对于 bdtts 本地引擎（sherpa-onnx 离线模型）：\n  //   url     = 本地模型名称（模型包 tts.json 的 name）\n  //   body    = 音色 id（tts.json voices 里的 id）\n  //   不支持调速，语速固定为 1.0\n  async function getttsurl(speakText,speechRate,juese,gender){\n        return JSON.stringify({\n            "method": "bdtts", //请求方式\n            "url": "ssssurl", //本地模型名称\n            "headers": {}, //携带的 header\n            "body": "ssssid" //音色 id\n        });\n    }\n\n\n  //返回http开头的则任务登录链接会跳webview，其他的会按照json解析显示弹窗\n  async function getloginurl(){\n    return baseurl;\n  }\n\n  //如果登录 url 为非 http 开头的弹窗界面，每次修改完弹窗就会执行此函数\n  async function login(){\n\n  }\n</script>\n';
  static const String bdttsclone = '<script>\n  const flutterBridge = new FlutterJSBridge();\n  const cache = new Cache();\n  const http = new Http();\n  const cookie = new Cookie();\n\n\n  // tts链接返回方式 ，不可缺少参数\n  // 当method 为 data 时我们会直接将body base64解码后的结果作为音频播放\n  //juese参数当用户开启多角色时会传入\n  //gender 参数当用户开启多角色时会传入 male 为男 female 为女 unknown为未知\n  //\n  // 对于 bdttsclone 本地克隆引擎（sherpa-onnx zipvoice 离线模型）：\n  //   url             = 本地模型名称（模型包 tts.json 的 name）\n  //   body            = 参考音频 dataURL（data:audio/wav;base64,...，用户上传的克隆音色）\n  //   headers.refText = 参考音频中说的文字\n  //   不支持调速，语速固定为 1.0；克隆模型可建无数个引擎\n  async function getttsurl(speakText,speechRate,juese,gender){\n        return JSON.stringify({\n            "method": "bdttsclone", //请求方式\n            "url": "ssssurl", //本地模型名称\n            "headers": {"refText": "ssssref"}, //参考音频对应的文本\n            "body": "ssssaudio" //参考音频 dataURL\n        });\n    }\n\n\n  //返回http开头的则任务登录链接会跳webview，其他的会按照json解析显示弹窗\n  async function getloginurl(){\n    return baseurl;\n  }\n\n  //如果登录 url 为非 http 开头的弹窗界面，每次修改完弹窗就会执行此函数\n  async function login(){\n\n  }\n</script>\n';
  static const String mimovoicedesign = '<script>\n  const flutterBridge = new FlutterJSBridge();\n  const cache = new Cache();\n  const http = new Http();\n  const cookie = new Cookie();\n\n\n  // tts链接返回方式 ，不可缺少参数\n  // 当method 为 data 时我们会直接将body base64解码后的结果作为音频播放\n  //juese参数当用户开启多角色时会传入\n  //gender 参数当用户开启多角色时会传入 male 为男 female 为女 unknown为未知\n  //\n  // 对于 mimo 文本描述定制音色（Voice Design）：\n  //   body    = 音色的文本描述（自然语言，例："温柔御姐音，语速中等，情感丰富"）\n  //   url     = 自然语言控制指令（空串表示无）\n  async function getttsurl(speakText,speechRate,juese,gender){\n        var _instruction = "ssssurl";\n        var _voiceDesc = "ssssid";\n        return JSON.stringify({\n            "method": "mimovoicedesign", //请求方式\n            "url": _instruction, //自然语言控制指令（空串表示无）\n            "headers": {}, //携带的 header\n            "body": _voiceDesc //音色的文本描述\n        });\n    }\n\n\n  //返回http开头的则任务登录链接会跳webview，其他的会按照json解析显示弹窗\n  async function getloginurl(){\n    return baseurl;\n  }\n\n  //如果登录 url 为非 http 开头的弹窗界面，每次修改完弹窗就会执行此函数\n  async function login(){\n\n  }\n</script>\n';
  static const String mimoclone = '<script>\n  const flutterBridge = new FlutterJSBridge();\n  const cache = new Cache();\n  const http = new Http();\n  const cookie = new Cookie();\n\n\n  // tts链接返回方式 ，不可缺少参数\n  // 当method 为 data 时我们会直接将body base64解码后的结果作为音频播放\n  //juese参数当用户开启多角色时会传入\n  //gender 参数当用户开启多角色时会传入 male 为男 female 为女 unknown为未知\n  async function getttsurl(speakText,speechRate,juese,gender){\n        var _instruction = "ssssurl";\n        var _referenceAudio = "data:MIME_TYPE;base64,BASE64_AUDIO";\n        return JSON.stringify({\n            "method": "mimoclone", //请求方式\n            "url": _instruction, //自然语言控制指令（空串表示无）\n            "headers": {}, //携带的 header\n            "body": _referenceAudio //音色参考音频 dataURL\n        });\n    }\n\n\n  //返回http开头的则任务登录链接会跳webview，其他的会按照json解析显示弹窗\n  async function getloginurl(){\n    return baseurl;\n  }\n\n  //如果登录 url 为非 http 开头的弹窗界面，每次修改完弹窗就会执行此函数\n  async function login(){\n\n  }\n</script>\n';
  static const String mimo = '<script>\n  const flutterBridge = new FlutterJSBridge();\n  const cache = new Cache();\n  const http = new Http();\n  const cookie = new Cookie();\n\n\n  // tts链接返回方式 ，不可缺少参数\n  // 当method 为 data 时我们会直接将body base64解码后的结果作为音频播放\n  //juese参数当用户开启多角色时会传入\n  //gender 参数当用户开启多角色时会传入 male 为男 female 为女 unknown为未知\n  //\n  // 对于 mimo 小米大声朗读：\n  //   body    = 音色名（冰糖 / 茉莉 / 苏打 / 白桦）\n  //   url     = 自然语言控制指令（放 user 消息 content），例：\n  //             "温柔治愈，语速稍慢，哄睡感"\n  //             如不需要控制可留空\n  async function getttsurl(speakText,speechRate,juese,gender){\n        var _instruction = "ssssurl";\n        var _voiceId = "ssssid";\n        return JSON.stringify({\n            "method": "mimo", //请求方式\n            "url": _instruction, //自然语言控制指令（空串表示无）\n            "headers": {}, //携带的 header\n            "body": _voiceId //音色名\n        });\n    }\n\n\n  //返回http开头的则任务登录链接会跳webview，其他的会按照json解析显示弹窗\n  async function getloginurl(){\n    return baseurl;\n  }\n\n  //如果登录 url 为非 http 开头的弹窗界面，每次修改完弹窗就会执行此函数\n  async function login(){\n\n  }\n</script>\n';
  static const String volcano = '<script>\n  const flutterBridge = new FlutterJSBridge();\n  const cache = new Cache();\n  const http = new Http();\n  const cookie = new Cookie();\n\n\n  // tts链接返回方式 ，不可缺少参数\n  // 当method 为 data 时我们会直接将body base64解码后的结果作为音频播放\n  //juese参数当用户开启多角色时会传入\n  //gender 参数当用户开启多角色时会传入 male 为男 female 为女 unknown为未知\n  async function getttsurl(speakText,speechRate,juese,gender){\n        return JSON.stringify({\n            "method": "volcano", //请求方式\n            "url": "", //请求 url\n            "headers": {}, //携带的 header\n            "body": "ssssid" //如果为 post 可以携带 body 参数\n        });\n    }\n\n\n  //返回http开头的则任务登录链接会跳webview，其他的会按照json解析显示弹窗\n  async function getloginurl(){\n    return baseurl;\n  }\n\n  //如果登录 url 为非 http 开头的弹窗界面，每次修改完弹窗就会执行此函数\n  async function login(){\n\n  }\n</script>\n';
  static const String edge = '<script>\n  const flutterBridge = new FlutterJSBridge();\n  const cache = new Cache();\n  const http = new Http();\n  const cookie = new Cookie();\n\n\n  // tts链接返回方式 ，不可缺少参数\n  // 当method 为 data 时我们会直接将body base64解码后的结果作为音频播放\n  //juese参数当用户开启多角色时会传入\n  //gender 参数当用户开启多角色时会传入 male 为男 female 为女 unknown为未知\n  async function getttsurl(speakText,speechRate,juese,gender){\n        return JSON.stringify({\n            "method": "edge", //请求方式\n            "url": "", //请求 url\n            "headers": {}, //携带的 header\n            "body": "ssssid" //如果为 post 可以携带 body 参数\n        });\n    }\n\n\n  //返回http开头的则任务登录链接会跳webview，其他的会按照json解析显示弹窗\n  async function getloginurl(){\n    return baseurl;\n  }\n\n  //如果登录 url 为非 http 开头的弹窗界面，每次修改完弹窗就会执行此函数\n  async function login(){\n\n  }\n</script>\n';
  static const String httpHelp = '  // tts链接返回方式 ，不可缺少参数\n  // 当method 为 data 时我们会直接将body base64解码后的结果作为音频播放\n  //juese参数当用户开启多角色时会传入\n    //gender 参数当用户开启多角色时会传入 male 为男 female 为女 unknown为未知\n  async function getttsurl(speakText,speechRate,juese){\n    return JSON.stringify({\n      "method": "get", //请求方式\n      "url": "", //请求 url\n      "headers": {}, //携带的 header\n      "body": "" //如果为 post 可以携带 body 参数\n    });\n  }\n                  ';

  /// The page of a built-in engine: head + "\n" + script + suffix (the original puts its bridge library between head and "\n").
  static String build(String script) => '$prefix\n$script$suffix';

  /// Escapes [s] for use inside a double-quoted JS string literal.
  static String js(String s) {
    final e = jsonEncode(s);
    return e.substring(1, e.length - 1);
  }

  static String edgePage(String voice) => build(edge.replaceAll('ssssid', js(voice)));
  static String volcanoPage(String voice) => build(volcano.replaceAll('ssssid', js(voice)));
  static String mimoPage(String voice, {String instruction = ''}) => build(mimo.replaceAll('ssssurl', js(instruction)).replaceAll('ssssid', js(voice)));
  static String mimoClonePage(String referenceAudio, {String instruction = ''}) =>
      build(mimoclone.replaceAll('ssssurl', js(instruction)).replaceAll('data:MIME_TYPE;base64,BASE64_AUDIO', js(referenceAudio)));
  static String mimoDesignPage(String description, {String instruction = ''}) =>
      build(mimovoicedesign.replaceAll('ssssurl', js(instruction)).replaceAll('ssssid', js(description)));
  static String localPage(String model, String voiceId) => build(bdtts.replaceAll('ssssurl', js(model)).replaceAll('ssssid', js(voiceId)));
  static String localClonePage(String model, String refText, String referenceAudio) =>
      build(bdttsclone.replaceAll('ssssurl', js(model)).replaceAll('ssssref', js(refText)).replaceAll('ssssaudio', js(referenceAudio)));

  /// A blank page for a user engine (the 普通引擎 editor starts from it).
  static String blank() => build('<script>\n  const flutterBridge = new FlutterJSBridge();\n  const cache = new Cache();\n  const http = new Http();\n'
      '  const cookie = new Cookie();\n\n$httpHelp\n\n  async function getloginurl(){\n    return "";\n  }\n\n  async function login(){\n\n  }\n</script>\n');

  // ---- static evaluation ----

  /// The request of a page whose `getttsurl` only declares string variables and returns a literal object (all built-in
  /// templates); null when the page computes something (then it needs the web view).
  static TtsPageRequest? literal(String page) {
    final i = page.indexOf('function getttsurl');
    if (i < 0) return null;
    final open = page.indexOf('{', i);
    if (open < 0) return null;
    final close = _matchBrace(page, open);
    if (close < 0) return null;
    final body = _stripComments(page.substring(open + 1, close));
    final vars = <String, String>{};
    final decl = RegExp(r'''(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\s*;?''');
    for (final m in decl.allMatches(body)) {
      vars[m.group(1)!] = _unquote(m.group(2)!);
    }
    var rest = body.replaceAll(decl, '').trim();
    final ret = RegExp(r'^return\s+JSON\.stringify\(\s*([\s\S]*)\)\s*;?$').firstMatch(rest);
    if (ret == null) return null;
    final p = _Literal(ret.group(1)!.trim(), vars);
    try {
      final v = p.value();
      p.ws();
      if (!p.done || v is! Map) return null;
      return TtsPageRequest.fromJson(v);
    } on FormatException {
      return null;
    }
  }

  static int _matchBrace(String s, int open) {
    var depth = 0;
    String? q;
    for (var i = open; i < s.length; i++) {
      final c = s[i];
      if (q != null) {
        if (c == '\\') {
          i++;
        } else if (c == q) {
          q = null;
        }
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        q = c;
      } else if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
        final nl = s.indexOf('\n', i);
        i = nl < 0 ? s.length : nl;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static String _stripComments(String s) {
    final b = StringBuffer();
    String? q;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (q != null) {
        b.write(c);
        if (c == '\\' && i + 1 < s.length) {
          b.write(s[++i]);
        } else if (c == q) {
          q = null;
        }
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        q = c;
        b.write(c);
      } else if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
        final nl = s.indexOf('\n', i);
        if (nl < 0) break;
        i = nl - 1;
      } else if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
        final end = s.indexOf('*/', i + 2);
        if (end < 0) break;
        i = end + 1;
      } else {
        b.write(c);
      }
    }
    return b.toString();
  }

  static String _unquote(String lit) {
    final s = lit.substring(1, lit.length - 1);
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c != '\\' || i + 1 >= s.length) {
        b.write(c);
        continue;
      }
      final n = s[++i];
      switch (n) {
        case 'n':
          b.write('\n');
        case 't':
          b.write('\t');
        case 'r':
          b.write('\r');
        case 'b':
          b.write('\b');
        case 'f':
          b.write('\f');
        case 'u':
          if (i + 4 < s.length) {
            b.writeCharCode(int.parse(s.substring(i + 1, i + 5), radix: 16));
            i += 4;
          }
        default:
          b.write(n);
      }
    }
    return b.toString();
  }

  // ---- the generic HTTP branch of 0xe953c4 ----

  /// Dio of the HTTP branch (`TtsDioManger`); tests inject their own.
  static Dio? dio;

  /// Runs a `get` / `post` / `head` request returned by a page; the reply bytes are the audio. Throws `获取失败` on a failed reply.
  static Future<({List<int> bytes, String contentType})> fetch(TtsPageRequest r) async {
    final d = dio ?? TtsDioManger.instance.dio;
    final method = r.method == 'post' ? 'POST' : (r.method == 'head' ? 'HEAD' : 'GET');
    final headers = Map<String, String>.of(r.headers);
    if (method == 'POST' && !headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    final resp = await d.request<List<int>>(
      r.url,
      data: method == 'POST' ? r.body : null,
      options: Options(method: method, headers: headers, responseType: ResponseType.bytes, validateStatus: (_) => true),
    );
    final bytes = resp.data ?? const <int>[];
    final status = resp.statusCode ?? 0;
    if (status >= 400 || bytes.isEmpty) throw Exception('获取失败');
    return (bytes: bytes, contentType: resp.headers.value(Headers.contentTypeHeader) ?? '');
  }

  // ---- web view hosts ----

  static final Map<String, TtsPageHost> _hosts = {};

  /// The request of [page] for [text]: literal pages directly, other pages through a (cached) web view host.
  static Future<TtsPageRequest> request(String page, String text, {int speechRate = 50, String juese = '', String gender = ''}) async {
    final lit = literal(page);
    if (lit != null) return lit;
    final key = '${page.length}:${page.hashCode}';
    final host = _hosts[key] ??= TtsPageHost.create();
    if (_hosts.length > 3) {
      final first = _hosts.keys.first;
      if (first != key) await _hosts.remove(first)?.dispose();
    }
    await host.load(page);
    return host.getttsurl(text, speechRate: speechRate, juese: juese, gender: gender);
  }

  static Future<void> disposeHosts() async {
    for (final h in _hosts.values) {
      await h.dispose();
    }
    _hosts.clear();
  }
}

/// Runs `getttsurl` of a page. [create] is replaceable (tests).
abstract class TtsPageHost {
  static TtsPageHost Function() create = WebViewTtsPageHost.new;

  /// Loads [page] (does nothing when it is already loaded).
  Future<void> load(String page);
  Future<TtsPageRequest> getttsurl(String text, {int speechRate = 50, String juese = '', String gender = ''});
  Future<void> dispose();
}

/// The offstage web view (webview_flutter, never attached to the widget tree) with the original's `callHandler` bridge.
class WebViewTtsPageHost implements TtsPageHost {
  WebViewController? _c;
  String _page = '';
  final Map<String, Completer<Object?>> _results = {};
  int _seq = 0;
  static const Duration timeout = Duration(seconds: 30);

  static const String shim = r'''<script>
(function(){
  var pending = {}, seq = 0;
  window.__qreadReply = function(id, ok, value){ var p = pending[id]; if(!p) return; delete pending[id]; ok ? p.res(value) : p.rej(value); };
  window.flutter_inappwebview = { callHandler: function(name){ var args = Array.prototype.slice.call(arguments, 1);
    return new Promise(function(res, rej){ var id = 'h' + (++seq); pending[id] = {res: res, rej: rej};
      QreadTts.postMessage(JSON.stringify({id: id, name: name, args: args})); }); } };
  var call = function(){ return window.flutter_inappwebview.callHandler.apply(null, arguments).catch(function(){ return null; }); };
  window.FlutterJSBridge = class { constructor(){ this.isReady = true; call('CookieJar', true); }
    log(s){ return call('log', s); } showToast(s){ return call('showToast', s); } showLongToast(s){ return call('showLongToast', s); }
    getDeviceid(){ return call('id'); } getDevice(){ return call('device'); } getLoginUser(){ return call('getLoginUser'); }
    getversion(){ return call('version'); } getbuildNumber(){ return call('buildNumber'); }
    base64encode(s){ return call('base64encode', s); } base64decode(s){ return call('base64decode', s); } };
  window.Http = class { Get(u, h, f){ return call('http', 'get', u, '', JSON.stringify(h || {}), f, ''); }
    Head(u, h, f){ return call('http', 'head', u, '', JSON.stringify(h || {}), f, ''); }
    Post(u, h, b, ct, f){ return call('http', 'post', u, b, JSON.stringify(h || {}), f, ct); } };
  window.Cache = class { get(k){ return call('cache.get', k); } set(k, v){ return call('cache.set', k, v); } remove(k){ return call('cache.remove', k); }
    allget(k){ return call('cache.allget', k); } allset(k, v){ return call('cache.allset', k, v); } allremove(k){ return call('cache.allremove', k); }
    getLoginInfo(){ return this.get('LoginInfo'); } putLoginInfo(i){ return this.set('LoginInfo', i); } };
  window.Cookie = class { get(u){ return call('cookie.get', u); } remove(u){ return call('cookie.remove', u); } set(u, v){ return call('cookie.set', u, v); }
    setCookie(u, k, v){ return call('cookie.setcookie', u, k, v); } getCookie(u, k){ return call('cookie.getCookie', u, k); } };
  window.baseurl = '';
})();
</script>
''';

  /// The page with the shim in front of its first script.
  static String inject(String page) {
    final i = page.indexOf('<head>');
    if (i >= 0) return '${page.substring(0, i + 6)}$shim${page.substring(i + 6)}';
    return '$shim$page';
  }

  @override
  Future<void> load(String page) async {
    if (_c != null && _page == page) return;
    final loaded = Completer<void>();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('QreadTts', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        if (!loaded.isCompleted) loaded.complete();
      }));
    _c = c;
    _page = page;
    await c.loadHtmlString(inject(page), baseUrl: 'https://localhost/');
    await loaded.future.timeout(timeout, onTimeout: () {});
  }

  Future<void> _onMessage(String raw) async {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    final id = '${m['id']}';
    if (id.startsWith('r')) {
      final done = _results.remove(id);
      if (done == null) return;
      m['ok'] == true ? done.complete(m['value']) : done.completeError(Exception('${m['value']}'));
      return;
    }
    Object? value;
    var ok = true;
    try {
      value = await TtsBridge.handle('${m['name']}', (m['args'] as List?) ?? const []);
    } catch (e) {
      ok = false;
      value = '$e';
    }
    await _c?.runJavaScript('window.__qreadReply(${jsonEncode(id)}, $ok, ${jsonEncode(value)});');
  }

  @override
  Future<TtsPageRequest> getttsurl(String text, {int speechRate = 50, String juese = '', String gender = ''}) async {
    final c = _c;
    if (c == null) throw StateError('朗读引擎不存在');
    final id = 'r${++_seq}';
    final done = Completer<Object?>();
    _results[id] = done;
    final args = [jsonEncode(text), jsonEncode('$speechRate'), jsonEncode(juese), jsonEncode(gender)].join(',');
    await c.runJavaScript('(async function(){ try { var r = await getttsurl($args); '
        'QreadTts.postMessage(JSON.stringify({id: ${jsonEncode(id)}, ok: true, value: r})); } catch (e) { '
        'QreadTts.postMessage(JSON.stringify({id: ${jsonEncode(id)}, ok: false, value: String(e)})); } })();');
    final v = await done.future.timeout(timeout, onTimeout: () {
      _results.remove(id);
      throw TimeoutException('获取 tts 链接超时');
    });
    return TtsPageRequest.fromJson(v);
  }

  @override
  Future<void> dispose() async {
    _c = null;
    _page = '';
    for (final r in _results.values) {
      if (!r.isCompleted) r.completeError(StateError('朗读引擎已关闭'));
    }
    _results.clear();
  }
}

/// The `callHandler` names a TTS page may use (the subset of the original's bridge that makes sense for TTS pages).
abstract class TtsBridge {
  static String _cacheKey(String k, {bool all = false}) => all ? 'ttscache_all_$k' : 'ttscache_$k';

  static Future<Object?> handle(String name, List<dynamic> a) async {
    String arg(int i) => i < a.length && a[i] != null ? '${a[i]}' : '';
    switch (name) {
      case 'CookieJar':
        return true;
      case 'log':
        debugPrint('tts: ${arg(0)}');
        return true;
      case 'showToast':
      case 'showLongToast':
        Toast.show(arg(0));
        return true;
      case 'id':
        return Common.appid;
      case 'device':
        return Platform.isIOS ? 'ios' : Platform.operatingSystem;
      case 'getLoginUser':
        return UserSession.username;
      case 'version':
        return '1.0.0';
      case 'buildNumber':
        return 1;
      case 'base64encode':
        return base64Encode(utf8.encode(arg(0)));
      case 'base64decode':
        return utf8.decode(base64Decode(arg(0)), allowMalformed: true);
      case 'cache.get':
      case 'cache.allget':
        final v = Storage.getString(_cacheKey(arg(0), all: name == 'cache.allget'));
        return v.isEmpty ? null : v;
      case 'cache.set':
      case 'cache.allset':
        await Storage.setString(_cacheKey(arg(0), all: name == 'cache.allset'), arg(1));
        return true;
      case 'cache.remove':
      case 'cache.allremove':
        await Storage.remove(_cacheKey(arg(0), all: name == 'cache.allremove'));
        return true;
      case 'http':
        return _http(arg(0), arg(1), arg(2), arg(3), arg(5));
      default:
        return null;
    }
  }

  /// `http` handler: {method, body (base64), headers, statusCode, statusMessage, data}.
  static Future<Map<String, dynamic>> _http(String method, String url, String body, String headersJson, String contentType) async {
    final headers = <String, String>{};
    if (headersJson.trim().startsWith('{')) {
      (jsonDecode(headersJson) as Map).forEach((k, v) => headers['$k'] = '$v');
    }
    if (contentType.isNotEmpty) headers['Content-Type'] = contentType;
    final d = TtsPages.dio ?? TtsDioManger.instance.dio;
    final r = await d.request<List<int>>(url,
        data: method == 'post' ? body : null,
        options: Options(method: method.toUpperCase(), headers: headers, responseType: ResponseType.bytes, validateStatus: (_) => true));
    final bytes = r.data ?? const <int>[];
    return {
      'method': method,
      'body': base64Encode(bytes),
      'headers': r.headers.map,
      'statusCode': r.statusCode,
      'statusMessage': r.statusMessage,
      'data': utf8.decode(bytes, allowMalformed: true),
    };
  }
}

/// A tiny parser for the object literal of `JSON.stringify({...})`: string literals, numbers, nested objects and identifiers that
/// name string variables declared before.
class _Literal {
  final String s;
  final Map<String, String> vars;
  int i = 0;
  _Literal(this.s, this.vars);

  bool get done => i >= s.length;

  void ws() {
    while (i < s.length && ' \t\r\n'.contains(s[i])) {
      i++;
    }
  }

  Object value() {
    ws();
    if (done) throw const FormatException('end');
    final c = s[i];
    if (c == '{') return _object();
    if (c == '"' || c == "'") return _string();
    final m = RegExp(r'[A-Za-z_$][\w$]*|-?\d+(\.\d+)?').matchAsPrefix(s, i);
    if (m == null) throw const FormatException('value');
    i = m.end;
    final t = m.group(0)!;
    if (RegExp(r'^-?\d').hasMatch(t)) return t;
    if (t == 'true' || t == 'false') return t;
    final v = vars[t];
    if (v == null) throw const FormatException('identifier');
    return v;
  }

  String _string() {
    final q = s[i];
    final start = i;
    i++;
    while (i < s.length && s[i] != q) {
      if (s[i] == '\\') i++;
      i++;
    }
    if (i >= s.length) throw const FormatException('string');
    i++;
    return TtsPages._unquote(s.substring(start, i));
  }

  Map<String, Object> _object() {
    i++; // {
    final out = <String, Object>{};
    while (true) {
      ws();
      if (done) throw const FormatException('object');
      if (s[i] == '}') {
        i++;
        return out;
      }
      if (s[i] == ',') {
        i++;
        continue;
      }
      String key;
      if (s[i] == '"' || s[i] == "'") {
        key = _string();
      } else {
        final m = RegExp(r'[A-Za-z_$][\w$]*').matchAsPrefix(s, i);
        if (m == null) throw const FormatException('key');
        key = m.group(0)!;
        i = m.end;
      }
      ws();
      if (done || s[i] != ':') throw const FormatException(':');
      i++;
      out[key] = value();
    }
  }
}
