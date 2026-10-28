// ai/openai_client.dart — OpenAI-compatible chat client for the models the user configured (`AiModelConfig`: full
// `…/chat/completions` url, key, model). Request shape of the original (role analysis 0xf07800, model check 0x109208c): headers
// `Content-Type: application/json`, `Authorization: Bearer <key>` and `api-key: <key>`; body `{model, messages, temperature, top_p,
// max_tokens, enable_thinking:false, thinking:{type:"disabled"}}` (thinking switched off unless asked for). The chat agent streams
// (SSE `data:` lines, `[DONE]`), with tool calls assembled from `delta.tool_calls[index]`. Reply text is `choices[0].message.content`;
// `reasoning_content` is ignored. Errors: `error.message` of the reply, else `请求失败` / the HTTP status.
// Keys never leave the device except to the configured url; nothing is bundled.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/ai_model_config.dart';

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}

/// One tool call requested by the model.
class AiToolCallReq {
  final String id;
  final String name;
  final String arguments;
  const AiToolCallReq(this.id, this.name, this.arguments);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments},
      };

  Map<String, dynamic> get args {
    try {
      final v = jsonDecode(arguments.isEmpty ? '{}' : arguments);
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }
}

/// A chat message in the wire format.
class AiMessage {
  final String role;
  final String content;
  final List<AiToolCallReq> toolCalls;
  final String? toolCallId;
  final String? name;
  const AiMessage(this.role, this.content, {this.toolCalls = const [], this.toolCallId, this.name});

  const AiMessage.system(String content) : this('system', content);
  const AiMessage.user(String content) : this('user', content);
  const AiMessage.assistant(String content, {List<AiToolCallReq> toolCalls = const []}) : this('assistant', content, toolCalls: toolCalls);
  const AiMessage.tool(String id, String name, String content) : this('tool', content, toolCallId: id, name: name);

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (toolCalls.isNotEmpty) 'tool_calls': [for (final t in toolCalls) t.toJson()],
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (name != null && role == 'tool') 'name': name,
      };
}

/// A function the model may call.
class AiTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  const AiTool(this.name, this.description, this.parameters);

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {'name': name, 'description': description, 'parameters': parameters},
      };
}

/// Result of a (possibly streamed) completion.
class AiReply {
  final String content;
  final List<AiToolCallReq> toolCalls;
  final String finishReason;
  const AiReply(this.content, {this.toolCalls = const [], this.finishReason = ''});
}

/// Streamed piece: text delta or the final reply.
class AiDelta {
  final String text;
  final AiReply? done;
  const AiDelta(this.text, [this.done]);
}

class OpenAiClient {
  final AiModelConfig config;
  final Dio dio;

  OpenAiClient(this.config, {Dio? dio, Duration connectTimeout = const Duration(seconds: 30), Duration receiveTimeout = const Duration(seconds: 200)})
      : dio = dio ??
            Dio(BaseOptions(connectTimeout: connectTimeout, receiveTimeout: receiveTimeout, sendTimeout: const Duration(seconds: 200)));

  /// The url must be the full completions endpoint (`接口地址必须以 completions 结尾`).
  static bool validUrl(String url) => url.trim().endsWith('completions');

  bool get configured => config.url.trim().isNotEmpty && config.key.trim().isNotEmpty && config.model.trim().isNotEmpty;

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.key}',
        'api-key': config.key,
      };

  Map<String, dynamic> body(List<AiMessage> messages,
      {List<AiTool> tools = const [], double? temperature, double? topP, int? maxTokens, bool thinking = false, bool stream = false}) {
    return {
      'model': config.model,
      'messages': [for (final m in messages) m.toJson()],
      'temperature': ?temperature,
      'top_p': ?topP,
      'max_tokens': ?maxTokens,
      if (tools.isNotEmpty) 'tools': [for (final t in tools) t.toJson()],
      if (stream) 'stream': true,
      'enable_thinking': thinking,
      if (!thinking) 'thinking': {'type': 'disabled'},
    };
  }

  static String _errorText(Object? data, int? status) {
    try {
      final v = data is String ? jsonDecode(data) : data;
      if (v is Map) {
        final e = v['error'];
        if (e is Map && e['message'] != null) return '${e['message']}';
        if (e is String) return e;
        if (v['message'] != null) return '${v['message']}';
      }
    } catch (_) {}
    return status == null ? '请求失败' : '请求失败 ($status)';
  }

  /// One non-streamed completion.
  Future<AiReply> chat(List<AiMessage> messages,
      {List<AiTool> tools = const [], double? temperature, double? topP, int? maxTokens, bool thinking = false, Duration? timeout}) async {
    if (!configured) throw const AiException('请先填写完整的接口地址、密钥和模型');
    Response<dynamic> r;
    try {
      r = await dio.post<dynamic>(
        config.url,
        data: jsonEncode(body(messages, tools: tools, temperature: temperature, topP: topP, maxTokens: maxTokens, thinking: thinking)),
        options: Options(headers: headers, responseType: ResponseType.plain, validateStatus: (_) => true, receiveTimeout: timeout, sendTimeout: timeout),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.sendTimeout) {
        throw const AiException('检验超时，请检查网络或重试');
      }
      throw AiException('API call failed: ${e.message ?? e.type.name}');
    }
    final status = r.statusCode ?? 0;
    if (status >= 400) throw AiException(_errorText(r.data, status));
    Map<String, dynamic> j;
    try {
      j = Map<String, dynamic>.from(jsonDecode(r.data as String) as Map);
    } catch (_) {
      throw const AiException('Invalid response format');
    }
    if (j['error'] != null) throw AiException(_errorText(j, status));
    final choices = j['choices'];
    if (choices is! List || choices.isEmpty) throw const AiException('Invalid response format');
    final c0 = Map<String, dynamic>.from(choices.first as Map);
    final msg = c0['message'] is Map ? Map<String, dynamic>.from(c0['message'] as Map) : <String, dynamic>{};
    final calls = <AiToolCallReq>[];
    for (final t in (msg['tool_calls'] as List? ?? const [])) {
      if (t is! Map) continue;
      final f = t['function'] is Map ? t['function'] as Map : const {};
      calls.add(AiToolCallReq('${t['id'] ?? ''}', '${f['name'] ?? ''}', '${f['arguments'] ?? ''}'));
    }
    return AiReply('${msg['content'] ?? ''}', toolCalls: calls, finishReason: '${c0['finish_reason'] ?? ''}');
  }

  /// Streamed completion (SSE). Emits text deltas, then one [AiDelta] with the assembled [AiReply]. [idleTimeout] = no data for that
  /// long fails with `响应超时（60 秒无数据）` (chat agent).
  Stream<AiDelta> chatStream(List<AiMessage> messages,
      {List<AiTool> tools = const [], double? temperature, bool thinking = false, Duration idleTimeout = const Duration(seconds: 60), CancelToken? cancel}) async* {
    if (!configured) throw const AiException('请先在模型管理中添加模型');
    Response<ResponseBody> r;
    try {
      r = await dio.post<ResponseBody>(
        config.url,
        data: jsonEncode(body(messages, tools: tools, temperature: temperature, thinking: thinking, stream: true)),
        cancelToken: cancel,
        options: Options(headers: {...headers, 'Accept': 'text/event-stream'}, responseType: ResponseType.stream, validateStatus: (_) => true),
      );
    } on DioException catch (e) {
      throw AiException('API call failed: ${e.message ?? e.type.name}');
    }
    final status = r.statusCode ?? 0;
    final stream = r.data!.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    if (status >= 400) {
      final text = await stream.join('\n');
      throw AiException(_errorText(text, status));
    }
    final content = StringBuffer();
    final calls = <int, List<String>>{}; // index -> [id, name, args]
    var finish = '';
    await for (final line in stream.timeout(idleTimeout, onTimeout: (sink) => sink.addError(const AiException('响应超时（60 秒无数据）')))) {
      final l = line.trim();
      if (!l.startsWith('data:')) continue;
      final data = l.substring(5).trim();
      if (data == '[DONE]') break;
      Map<String, dynamic> j;
      try {
        j = Map<String, dynamic>.from(jsonDecode(data) as Map);
      } catch (_) {
        continue;
      }
      if (j['error'] != null) throw AiException(_errorText(j, status));
      final choices = j['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final c0 = choices.first as Map;
      if (c0['finish_reason'] != null) finish = '${c0['finish_reason']}';
      final delta = c0['delta'] is Map ? c0['delta'] as Map : const {};
      final t = delta['content'];
      if (t is String && t.isNotEmpty) {
        content.write(t);
        yield AiDelta(t);
      }
      for (final tc in (delta['tool_calls'] as List? ?? const [])) {
        if (tc is! Map) continue;
        final idx = tc['index'] is int ? tc['index'] as int : calls.length;
        final slot = calls.putIfAbsent(idx, () => ['', '', '']);
        if (tc['id'] != null) slot[0] = '${tc['id']}';
        final f = tc['function'] is Map ? tc['function'] as Map : const {};
        if (f['name'] != null) slot[1] += '${f['name']}';
        if (f['arguments'] != null) slot[2] += '${f['arguments']}';
      }
    }
    final keys = calls.keys.toList()..sort();
    yield AiDelta('', AiReply(content.toString(),
        toolCalls: [for (final k in keys) AiToolCallReq(calls[k]![0].isEmpty ? 'call_$k' : calls[k]![0], calls[k]![1], calls[k]![2])],
        finishReason: finish));
  }

  /// 检验 (0x109208c): a tiny request; returns null on success, else the message to show.
  static Future<String?> testModel(AiModelConfig config, {Dio? dio, Duration timeout = const Duration(seconds: 30)}) async {
    final c = OpenAiClient(config, dio: dio);
    if (!c.configured) return '请先填写完整的接口地址、密钥和模型';
    try {
      // 0x109208c: one user message `test`, temperature 0.01, top_p 0.01, max_tokens 8192 (Smi 0x4000), thinking off, 30 s.
      await c.chat(const [AiMessage.user('test')], temperature: 0.01, topP: 0.01, maxTokens: 8192, timeout: timeout);
      return null;
    } on AiException catch (e) {
      if (e.message.startsWith('检验超时')) return e.message;
      return '检验失败: ${e.message}';
    }
  }

  /// Text inside a ```json fenced block (or any fence), else the outermost `[...]`, else the text itself.
  static String extractJson(String text) {
    final m1 = RegExp(r'```json\s*(.*?)\s*```', dotAll: true).firstMatch(text);
    if (m1 != null) return m1.group(1)!;
    final m2 = RegExp(r'```\s*(.*?)\s*```', dotAll: true).firstMatch(text);
    if (m2 != null) return m2.group(1)!;
    final a = text.indexOf('[');
    final b = text.lastIndexOf(']');
    if (a >= 0 && b > a) return text.substring(a, b + 1);
    return text;
  }
}
