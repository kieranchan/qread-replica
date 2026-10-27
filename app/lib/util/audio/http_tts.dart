// util/audio/http_tts.dart — runs an imported HTTP TTS engine (Legado `HttpTTS` JSON kept in `HttpTts.html`, see data/tts.dart):
// the `url` template (`…?text={{java.encodeURI(speakText)}}&rate={{speakSpeed}}`, optionally followed by `,{"method":"POST",
// "body":"…","headers":{…}}`), the `header` JSON and the `contentType` check of the reply (a regex such as `audio/.*`).
//
// `{{…}}` holds a small JavaScript expression. The original evaluates it in its JS engine (and its own engines are HTML pages with
// `getttsurl()`, run in a web view); this build has no JS runtime here, so [TtsTemplate] evaluates the expression subset the engines
// in the wild use: the variables `speakText` / `speakSpeed` / `speakVolume` / `voice`, string and number literals, `+ - * / %`,
// parentheses and the helpers `java.encodeURI`, `encodeURI`, `encodeURIComponent`, `java.base64Encode`, `java.md5Encode`, `String`,
// `Number`, `parseInt`, `Math.round` / `Math.floor` / `Math.ceil`. Anything else fails with `不支持的表达式: …`.
// TODO(asm 0x4bf18): engines whose definition is an HTML page (`getttsurl`) need the web view bridge of the reader area.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';

import '../../dio/tts_dio_manger.dart';

class TtsTemplateException implements Exception {
  final String message;
  const TtsTemplateException(this.message);
  @override
  String toString() => message;
}

/// Evaluates `{{expr}}` blocks.
class TtsTemplate {
  final Map<String, Object> vars;
  TtsTemplate(this.vars);

  static final RegExp _block = RegExp(r'\{\{([\s\S]*?)\}\}');

  String render(String template) => template.replaceAllMapped(_block, (m) => _str(evaluate(m.group(1)!)));

  Object evaluate(String expr) {
    final p = _Parser(expr, vars);
    final v = p.expression();
    p.skipWs();
    if (!p.done) throw TtsTemplateException('不支持的表达式: $expr');
    return v;
  }

  static String _str(Object v) {
    if (v is double) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return '$v';
  }
}

class _Parser {
  final String s;
  final Map<String, Object> vars;
  int i = 0;
  _Parser(this.s, this.vars);

  bool get done => i >= s.length;

  void skipWs() {
    while (i < s.length && ' \t\r\n'.contains(s[i])) {
      i++;
    }
  }

  bool _eat(String c) {
    skipWs();
    if (s.startsWith(c, i)) {
      i += c.length;
      return true;
    }
    return false;
  }

  Never _fail() => throw TtsTemplateException('不支持的表达式: $s');

  Object expression() {
    var v = term();
    while (true) {
      if (_eat('+')) {
        final r = term();
        v = (v is num && r is num) ? v + r : '${TtsTemplate._str(v)}${TtsTemplate._str(r)}';
      } else if (_eat('-')) {
        v = _num(v) - _num(term());
      } else {
        return v;
      }
    }
  }

  Object term() {
    var v = factor();
    while (true) {
      if (_eat('*')) {
        v = _num(v) * _num(factor());
      } else if (_eat('/')) {
        v = _num(v) / _num(factor());
      } else if (_eat('%')) {
        v = _num(v) % _num(factor());
      } else {
        return v;
      }
    }
  }

  num _num(Object v) => v is num ? v : (num.tryParse('$v') ?? _fail());

  Object factor() {
    skipWs();
    if (done) _fail();
    if (_eat('(')) {
      final v = expression();
      if (!_eat(')')) _fail();
      return v;
    }
    if (_eat('-')) return -_num(factor());
    final c = s[i];
    if (c == '"' || c == "'") return _string(c);
    if (RegExp(r'[0-9.]').hasMatch(c)) {
      final m = RegExp(r'[0-9]*\.?[0-9]+').matchAsPrefix(s, i) ?? _fail();
      i = m.end;
      return num.parse(m.group(0)!);
    }
    final m = RegExp(r'[A-Za-z_$][A-Za-z0-9_$.]*').matchAsPrefix(s, i) ?? _fail();
    i = m.end;
    final name = m.group(0)!;
    if (_eat('(')) {
      final args = <Object>[];
      if (!_eat(')')) {
        do {
          args.add(expression());
        } while (_eat(','));
        if (!_eat(')')) _fail();
      }
      return _call(name, args);
    }
    final v = vars[name];
    if (v == null) _fail();
    return v;
  }

  Object _string(String q) {
    i++;
    final b = StringBuffer();
    while (i < s.length && s[i] != q) {
      if (s[i] == '\\' && i + 1 < s.length) {
        i++;
        b.write(switch (s[i]) { 'n' => '\n', 't' => '\t', _ => s[i] });
      } else {
        b.write(s[i]);
      }
      i++;
    }
    if (i >= s.length) _fail();
    i++;
    return b.toString();
  }

  Object _call(String name, List<Object> a) {
    String arg0() => a.isEmpty ? '' : TtsTemplate._str(a[0]);
    switch (name) {
      case 'java.encodeURI':
      case 'encodeURIComponent':
        return Uri.encodeComponent(arg0());
      case 'encodeURI':
        return Uri.encodeFull(arg0());
      case 'java.base64Encode':
        return base64Encode(utf8.encode(arg0()));
      case 'java.md5Encode':
        return crypto.md5.convert(utf8.encode(arg0())).toString();
      case 'String':
        return arg0();
      case 'Number':
      case 'parseFloat':
        return num.tryParse(arg0()) ?? 0;
      case 'parseInt':
        return num.tryParse(arg0())?.toInt() ?? 0;
      case 'Math.round':
        return _num(a.first).round();
      case 'Math.floor':
        return _num(a.first).floor();
      case 'Math.ceil':
        return _num(a.first).ceil();
      default:
        _fail();
    }
  }
}

/// The audio a request produced.
class TtsAudio {
  final Uint8List bytes;
  final String contentType;
  const TtsAudio(this.bytes, this.contentType);

  /// File extension guessed from the content type (`mp3` default).
  String get ext {
    final c = contentType.toLowerCase();
    if (c.contains('wav')) return 'wav';
    if (c.contains('ogg') || c.contains('opus')) return 'ogg';
    if (c.contains('aac') || c.contains('mp4') || c.contains('m4a')) return 'm4a';
    return 'mp3';
  }
}

/// One prepared request of an engine.
class TtsRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
  const TtsRequest(this.method, this.url, this.headers, this.body);
}

abstract class HttpTtsRunner {
  /// The Dio used for the calls (`TtsDioManger`); tests inject their own.
  static Dio? dio;

  /// Builds the request of [engine] (the `html` map of an `HttpTts`) for [text] at [speed].
  static TtsRequest build(Map<String, dynamic> engine, String text, {int speed = 10, int volume = 100, String voice = ''}) {
    final tpl = TtsTemplate({'speakText': text, 'speakSpeed': speed, 'speakVolume': volume, 'voice': voice});
    final raw = '${engine['url'] ?? ''}'.trim();
    if (raw.isEmpty) throw const TtsTemplateException('朗读引擎地址为空');
    if (raw.startsWith('<') || raw.contains('getttsurl')) throw const TtsTemplateException('当前版本不支持网页朗读引擎');
    var urlPart = raw;
    Map<String, dynamic> opt = {};
    final comma = _optionComma(raw);
    if (comma > 0) {
      urlPart = raw.substring(0, comma).trim();
      try {
        opt = Map<String, dynamic>.from(jsonDecode(raw.substring(comma + 1)) as Map);
      } catch (_) {
        throw TtsTemplateException('url 参数格式错误: ${raw.substring(comma + 1)}');
      }
    }
    final headers = <String, String>{};
    void addHeaders(Object? h) {
      if (h is String && h.trim().isNotEmpty) {
        try {
          h = jsonDecode(h);
        } catch (_) {
          return;
        }
      }
      if (h is Map) {
        h.forEach((k, v) => headers['$k'] = tpl.render('$v'));
      }
    }

    addHeaders(engine['header']);
    addHeaders(opt['headers']);
    final method = '${opt['method'] ?? 'GET'}'.toUpperCase();
    final body = opt['body'] == null ? null : tpl.render(opt['body'] is String ? opt['body'] as String : jsonEncode(opt['body']));
    return TtsRequest(method, tpl.render(urlPart), headers, body);
  }

  /// Index of the comma that starts the Legado option object (`url,{…}`), -1 when none.
  static int _optionComma(String raw) {
    var depth = 0;
    for (var i = 0; i < raw.length - 1; i++) {
      if (raw.startsWith('{{', i)) {
        depth++;
        i++;
      } else if (raw.startsWith('}}', i)) {
        depth--;
        i++;
      } else if (depth == 0 && raw[i] == ',' && raw.substring(i + 1).trimLeft().startsWith('{')) {
        return i;
      }
    }
    return -1;
  }

  /// Executes the request; checks the reply's content type against the engine's `contentType` regex.
  static Future<TtsAudio> synthesize(Map<String, dynamic> engine, String text, {int speed = 10, int volume = 100, String voice = ''}) async {
    final req = build(engine, text, speed: speed, volume: volume, voice: voice);
    final d = dio ?? TtsDioManger.instance.dio;
    final r = await d.request<List<int>>(
      req.url,
      data: req.body,
      options: Options(method: req.method, headers: req.headers, responseType: ResponseType.bytes, validateStatus: (_) => true),
    );
    final bytes = Uint8List.fromList(r.data ?? const []);
    final ct = r.headers.value(Headers.contentTypeHeader) ?? '';
    final status = r.statusCode ?? 0;
    final want = '${engine['contentType'] ?? ''}'.trim();
    final typeOk = want.isEmpty ? !ct.toLowerCase().contains('text') && !ct.toLowerCase().contains('json') : RegExp(want).hasMatch(ct);
    if (status >= 400 || !typeOk || bytes.isEmpty) {
      final msg = utf8.decode(bytes.length > 300 ? bytes.sublist(0, 300) : bytes, allowMalformed: true);
      throw TtsTemplateException('朗读失败($status $ct): $msg');
    }
    return TtsAudio(bytes, ct);
  }
}
