// pages/source/debug_http_server.dart — `DebugHttpServer`: the 在线调试 HTTP service of the source debugger (fixed port 5858). A
// computer on the same Wi-Fi (browser, curl or an AI agent) can run debug steps, read the source and save it back.
//
// Original (class `DebugHttpServer`, size 0x48): bind 0xfc4108 (`InternetAddress.anyIPv4`), router 0xfc41f4 (OPTIONS / GET / /healthz,
// POST /debug, GET + PUT /source, `接口不存在: …，请 GET / 查看全部接口`, `服务器内部错误: `), CORS 0x5cb058, docs 0x5ca69c (`书源在线调试
// HTTP`), body read 0xfc5228 (`读取请求体失败: `), /debug request parsing 0xfc53d4, PUT validation 0xfc49b0 (in debug_source.dart),
// run with timeout 0xfc5b24 (`[超时]` / `[调试异常]`, reply keys key/timeout/logs/raw{search,book,toc,content}).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../common/lock.dart';

/// A request error with the message the client gets (`DebugHttpException`).
class DebugHttpException implements Exception {
  final String message;
  final int status;
  const DebugHttpException(this.message, [this.status = 400]);
  @override
  String toString() => message;
}

/// Result of one debug run: all log lines and the page sources of each step (empty when the step did not run).
class DebugRunResult {
  final String key;
  final String logs;
  final Map<String, String> raw;
  const DebugRunResult(this.key, this.logs, this.raw);
}

class DebugHttpServer {
  static const int defaultPort = 5858;

  final int port;

  /// Runs the debugger for [key]; must finish (the server applies the timeout).
  final Future<DebugRunResult> Function(String key) runDebug;

  /// Lines collected so far by the running debug (returned on timeout).
  final String Function() partialLogs;

  /// Full JSON of the source being debugged.
  final Map<String, dynamic> Function() getSource;

  /// Validates and stores an edited source (throws [DebugHttpException]); returns the reply `data`.
  final Future<Map<String, dynamic>> Function(Object? body) saveSource;

  /// Shown in the docs (`current`).
  final String Function() currentKeyword;

  HttpServer? _server;
  final Lock _queue = Lock();

  DebugHttpServer({
    this.port = defaultPort,
    required this.runDebug,
    required this.partialLogs,
    required this.getSource,
    required this.saveSource,
    required this.currentKeyword,
  });

  bool get running => _server != null;
  int get boundPort => _server?.port ?? port;

  /// 0xfc4108. [address] defaults to every IPv4 interface (LAN access).
  Future<void> start({InternetAddress? address}) async {
    if (_server != null) return;
    final s = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server = s;
    s.listen(_handle);
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  /// 0x5ca69c: service information and the full interface description.
  Map<String, dynamic> docs(String baseUrl) {
    final src = getSource();
    return {
      'success': true,
      'service': '书源在线调试 HTTP',
      'baseUrl': baseUrl,
      'encoding': 'UTF-8 JSON，POST/PUT 请带请求头 Content-Type: application/json; charset=utf-8',
      'successResponse': '成功: {"success": true, ...}；失败: {"success": false, "error": "原因"}',
      'current': {'bookSourceUrl': src['bookSourceUrl'], 'bookSourceName': src['bookSourceName'], 'checkKeyWord': currentKeyword()},
      'docs': '服务信息与完整接口文档（就是本内容）',
      'endpoints': [
        {'method': 'GET', 'path': '/', 'description': '服务信息与完整接口文档（就是本内容）', 'curl': 'curl $baseUrl/'},
        {'method': 'GET', 'path': '/healthz', 'description': '探活，服务在线返回 {"success":true}', 'curl': 'curl $baseUrl/healthz'},
        {
          'method': 'POST',
          'path': '/debug',
          'description': '运行一次调试（搜索/发现/详情/目录/正文），同一时间只处理一个，并发会排队',
          'bodyExample': {'type': 'search', 'keyword': '我的', 'timeout': 60},
          'responseExample': {
            'success': true,
            'data': {
              'key': '我的',
              'logs': '全部调试日志（文本）',
              'raw': {'search': '搜索页源码，没有为空字符串', 'book': '详情页源码', 'toc': '目录页源码', 'content': '正文页源码'},
            },
          },
          'curl': 'curl -X POST $baseUrl/debug -H \'Content-Type: application/json; charset=utf-8\' -d \'{"type":"search","keyword":"我的"}\'',
        },
        {'method': 'GET', 'path': '/source', 'description': '获取当前正在调试的书源完整 JSON，data.source 可修改后用 PUT 提交', 'curl': 'curl $baseUrl/source'},
        {
          'method': 'PUT',
          'path': '/source',
          'description': '编辑保存当前调试书源【单个】JSON 对象（禁止数组）：bookSourceUrl 必须与当前调试源完全一致，不同直接报错。isqread 只能是 false 或不传。保存后 App 自动重载，无需弹窗确认',
          'bodyExample': {'bookSourceUrl': 'https://example.com', 'bookSourceName': '示例源'},
          'responseExample': {
            'success': true,
            'data': {'action': 'edited', 'bookSourceUrl': 'https://example.com', 'bookSourceName': '示例源'},
          },
          'curl': 'curl -X PUT $baseUrl/source -H \'Content-Type: application/json; charset=utf-8\' -d @source.json',
        },
      ],
    };
  }

  /// 0xfc53d4: the debug key of a POST /debug body.
  static String debugKey(String bodyText) {
    if (bodyText.trim().isEmpty) {
      throw const DebugHttpException('请求体为空，请发送 JSON，例如 {"key":"我的"} 或 {"type":"search","keyword":"我的"}');
    }
    Object? v;
    try {
      v = jsonDecode(bodyText);
    } catch (e) {
      throw DebugHttpException('请求体不是合法 JSON: $e');
    }
    if (v is! Map) throw const DebugHttpException('请求体必须是 JSON 对象 {…}，不能是数组');
    final key = '${v['key'] ?? ''}'.trim();
    if (key.isNotEmpty) return key;
    final type = '${v['type'] ?? ''}'.trim();
    final url = '${v['url'] ?? ''}'.trim();
    bool isHttp(String u) => u.startsWith('http://') || u.startsWith('https://');
    switch (type) {
      case 'search':
        final k = '${v['keyword'] ?? ''}'.trim();
        if (k.isEmpty) throw const DebugHttpException('type=search 时 keyword 不能为空');
        return k;
      case 'explore':
        if (url.isEmpty) throw const DebugHttpException('type=explore 时 url 不能为空');
        final title = '${v['title'] ?? ''}'.trim();
        return '${title.isEmpty ? '发现' : title}::$url';
      case 'book':
        if (!isHttp(url)) throw const DebugHttpException('type=book 时 url 必须是 http(s):// 开头的详情页地址');
        return url;
      case 'toc':
        if (!isHttp(url)) throw const DebugHttpException('type=toc 时 url 必须是 http(s):// 开头的目录页地址');
        return '++$url';
      case 'content':
        if (!isHttp(url)) throw const DebugHttpException('type=content 时 url 必须是 http(s):// 开头的正文页地址');
        return '--$url';
    }
    if (url.isNotEmpty) return url;
    throw const DebugHttpException('无法识别的请求：请传 {"key":"调试指令"} 或 {"type":"search|explore|book|toc|content",...}');
  }

  static int _timeoutOf(String bodyText) {
    try {
      final v = jsonDecode(bodyText);
      if (v is Map) return (int.tryParse('${v['timeout'] ?? ''}') ?? 60).clamp(5, 600);
    } catch (_) {}
    return 60;
  }

  /// 0xfc5b24: one debug at a time; a run that takes longer than the timeout answers with what was collected.
  Future<Map<String, dynamic>> runKey(String key, int timeoutSeconds) => _queue.synchronized(() async {
        final sb = StringBuffer();
        Map<String, String> raw = const {'search': '', 'book': '', 'toc': '', 'content': ''};
        try {
          final r = await runDebug(key).timeout(Duration(seconds: timeoutSeconds));
          sb.write(r.logs);
          raw = {'search': '', 'book': '', 'toc': '', 'content': '', ...r.raw};
        } on TimeoutException {
          sb
            ..write(partialLogs())
            ..write('\n[超时] 调试已超过 $timeoutSeconds 秒，先返回当前收集到的内容（App 端可能仍在继续执行）。');
        } catch (e) {
          sb
            ..write(partialLogs())
            ..write('\n[调试异常] $e');
        }
        return {'key': key, 'timeout': timeoutSeconds, 'logs': sb.toString(), 'raw': raw};
      });

  Future<String> _body(HttpRequest req) async {
    try {
      return await utf8.decoder.bind(req).join();
    } catch (e) {
      throw DebugHttpException('读取请求体失败: $e');
    }
  }

  void _cors(HttpResponse r) {
    r.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');
  }

  Future<void> _json(HttpRequest req, int status, Map<String, dynamic> body) async {
    final r = req.response;
    r.statusCode = status;
    _cors(r);
    r.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    r.add(utf8.encode(const JsonEncoder.withIndent('  ').convert(body)));
    await r.close();
  }

  /// 0xfc41f4.
  Future<void> _handle(HttpRequest req) async {
    final method = req.method.toUpperCase();
    final path = req.uri.path;
    try {
      if (method == 'OPTIONS') {
        _cors(req.response);
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }
      if (method == 'GET' && (path == '/' || path.isEmpty)) {
        final host = req.headers.host ?? '127.0.0.1';
        return _json(req, 200, docs('http://$host:${req.headers.port ?? boundPort}'));
      }
      if (method == 'GET' && path == '/healthz') return _json(req, 200, {'success': true});
      if (method == 'POST' && path == '/debug') {
        final text = await _body(req);
        final key = debugKey(text);
        return _json(req, 200, {'success': true, 'data': await runKey(key, _timeoutOf(text))});
      }
      if (method == 'GET' && path == '/source') return _json(req, 200, {'success': true, 'data': {'source': getSource()}});
      if (method == 'PUT' && path == '/source') {
        final text = await _body(req);
        Object? v;
        if (text.trim().isNotEmpty) {
          try {
            v = jsonDecode(text);
          } catch (e) {
            throw DebugHttpException('请求体不是合法 JSON：$e');
          }
        }
        return _json(req, 200, {'success': true, 'data': await saveSource(v)});
      }
      return _json(req, 404, {'success': false, 'error': '接口不存在: $method $path，请 GET / 查看全部接口'});
    } on DebugHttpException catch (e) {
      try {
        await _json(req, e.status, {'success': false, 'error': e.message});
      } catch (_) {}
    } catch (e) {
      try {
        await _json(req, 500, {'success': false, 'error': '服务器内部错误: $e'});
      } catch (_) {}
    }
  }
}
