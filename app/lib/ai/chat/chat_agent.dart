// ai/chat/chat_agent.dart — 时光 AI 助手 (the reader's AI chat; original ai/chat/chat_agent.dart on langchain + openai_dart). A run streams
// the model's answer, executes the tool calls it asks for and feeds the results back, at most [maxRounds] = 10 rounds
// (`工具调用轮数超过上限（10 轮）`), each round failing after 60 s without data (`响应超时（60 秒无数据）`) and each tool after its own
// timeout (`执行超时`). Deep-thinking sessions prefix the user turn with `当前为深度思考模式，请深入全面地分析。`. When the model rejects
// tools, the agent retries once without them and with the current chapter inlined (`当前模型不支持工具调用，已内联当前章节（此时无法修改参数）`).
// Member-only like the original sheet: `当前功能仅对会员开放`.
//
// Tools are plugged in as [ChatTool]s. This file provides the web tools (web_search on Bing / Baidu result pages, web_fetch with the
// noise tags removed and `网页内容过长已截断`) and `get_chat_history`; the reader area adds the book tools (chapter text, digest,
// characters, settings) through [ChatContext].
// TODO(asm 0x71158): the original system prompt is assembled from several pool strings; the replica writes its own short persona.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

import '../../data/user.dart';
import '../../models/ai_model_config.dart';
import '../openai_client.dart';

/// What the reader exposes to the agent (all optional).
class ChatContext {
  final String bookName;
  final int chapterCount;
  final String chapterTitle;

  /// Current chapter text (inlined when the model has no tool support).
  final Future<String> Function()? chapterText;
  const ChatContext({this.bookName = '', this.chapterCount = 0, this.chapterTitle = '', this.chapterText});
}

class ChatTool {
  final AiTool spec;
  final Future<String> Function(Map<String, dynamic> args) run;
  final Duration timeout;
  const ChatTool(this.spec, this.run, {this.timeout = const Duration(seconds: 30)});
}

sealed class ChatEvent {
  const ChatEvent();
}

class ChatText extends ChatEvent {
  final String text;
  const ChatText(this.text);
}

class ChatToolStart extends ChatEvent {
  final AiToolCallReq call;
  const ChatToolStart(this.call);
}

class ChatToolResult extends ChatEvent {
  final AiToolCallReq call;
  final String result;
  const ChatToolResult(this.call, this.result);
}

class ChatNotice extends ChatEvent {
  final String message;
  const ChatNotice(this.message);
}

/// The final assistant text plus every message of the run (to store in the session).
class ChatDone extends ChatEvent {
  final String content;
  final List<AiMessage> messages;
  const ChatDone(this.content, this.messages);
}

class ChatAgent {
  static const int maxRounds = 10;
  static const String deepPrefix = '当前为深度思考模式，请深入全面地分析。\n';
  static const String memberOnly = '当前功能仅对会员开放';

  final AiModelConfig model;
  final List<ChatTool> tools;
  final ChatContext context;
  final bool deepThinking;
  final Dio? dio;
  final Duration idleTimeout;

  ChatAgent(this.model, {this.tools = const [], this.context = const ChatContext(), this.deepThinking = false, this.dio, this.idleTimeout = const Duration(seconds: 60)});

  String get systemPrompt {
    final b = StringBuffer('你是「时光」，轻悦时光阅读应用里的 AI 阅读助手，用简洁的中文回答。');
    if (context.bookName.isNotEmpty) b.write('用户正在阅读《${context.bookName}》');
    if (context.chapterCount > 0) b.write('（共 ${context.chapterCount} 章）');
    if (context.chapterTitle.isNotEmpty) b.write('，当前章节：${context.chapterTitle}');
    b.write('。需要书中内容或网络信息时调用工具；最多调用 $maxRounds 轮工具，请在达到上限前完成所有必要调用并整理最终回复。');
    return b.toString();
  }

  /// Runs one user turn after [history] (earlier user / assistant / tool messages).
  Stream<ChatEvent> run(List<AiMessage> history, String userText, {CancelToken? cancel}) async* {
    if (!UserSession.isvip) throw const AiException(memberOnly);
    final client = OpenAiClient(model, dio: dio);
    final msgs = <AiMessage>[
      AiMessage.system(systemPrompt),
      ...history,
      AiMessage.user(deepThinking ? '$deepPrefix$userText' : userText),
    ];
    final added = <AiMessage>[msgs.last];
    var useTools = tools.isNotEmpty;
    for (var round = 0; round <= maxRounds; round++) {
      if (round == maxRounds) throw const AiException('工具调用轮数超过上限（10 轮）');
      AiReply? reply;
      try {
        await for (final d in client.chatStream(msgs,
            tools: useTools ? [for (final t in tools) t.spec] : const [], thinking: deepThinking, idleTimeout: idleTimeout, cancel: cancel)) {
          if (d.done != null) {
            reply = d.done;
          } else {
            yield ChatText(d.text);
          }
        }
      } on AiException catch (e) {
        if (useTools && round == 0 && _noToolSupport(e.message)) {
          useTools = false;
          final chapter = context.chapterText == null ? '' : await context.chapterText!();
          yield const ChatNotice('当前模型不支持工具调用，已内联当前章节（此时无法修改参数）');
          if (chapter.isNotEmpty) {
            msgs.insert(1, AiMessage.system('当前章节内容：\n$chapter'));
          }
          round--;
          continue;
        }
        rethrow;
      }
      final r = reply ?? const AiReply('');
      final assistant = AiMessage.assistant(r.content, toolCalls: r.toolCalls);
      msgs.add(assistant);
      added.add(assistant);
      if (r.toolCalls.isEmpty) {
        yield ChatDone(r.content, added);
        return;
      }
      for (final call in r.toolCalls) {
        yield ChatToolStart(call);
        final result = await _runTool(call);
        final m = AiMessage.tool(call.id, call.name, result);
        msgs.add(m);
        added.add(m);
        yield ChatToolResult(call, result);
      }
    }
  }

  static bool _noToolSupport(String message) {
    final m = message.toLowerCase();
    return m.contains('tool') && (m.contains('support') || m.contains('not') || m.contains('invalid') || m.contains('不支持'));
  }

  Future<String> _runTool(AiToolCallReq call) async {
    final t = tools.where((e) => e.spec.name == call.name).firstOrNull;
    if (t == null) return '未知工具: ${call.name}';
    try {
      return await t.run(call.args).timeout(t.timeout, onTimeout: () => '执行超时');
    } catch (e) {
      return '工具执行失败: $e';
    }
  }
}

/// The web tools of ai/chat/web_tools.dart.
abstract class WebTools {
  static const int maxChars = 8000;

  static ChatTool search({Dio? dio}) => ChatTool(
        const AiTool('web_search', '搜索网络，返回结果标题、链接与摘要', {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': '搜索词'},
            'engine': {'type': 'string', 'enum': ['bing', 'baidu']},
          },
          'required': ['query'],
        }),
        (a) => webSearch('${a['query'] ?? ''}', engine: '${a['engine'] ?? 'bing'}', dio: dio),
      );

  static ChatTool fetch({Dio? dio}) => ChatTool(
        const AiTool('web_fetch', '读取网页正文', {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
          },
          'required': ['url'],
        }),
        (a) => webFetch('${a['url'] ?? ''}', dio: dio),
      );

  static ChatTool history(List<AiMessage> Function() messages) => ChatTool(
        const AiTool('get_chat_history', '获取本会话之前的聊天记录', {'type': 'object', 'properties': {}}),
        (_) async => jsonEncode([
          for (final m in messages())
            if (m.role == 'user' || m.role == 'assistant') {'role': m.role, 'content': m.content},
        ]),
      );

  static Future<String> _get(String url, Dio? dio) async {
    final d = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 20)));
    final r = await d.get<String>(url,
        options: Options(responseType: ResponseType.plain, headers: {'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15'}));
    return r.data ?? '';
  }

  static Future<String> webSearch(String query, {String engine = 'bing', Dio? dio}) async {
    if (query.trim().isEmpty) return '[]';
    final baidu = engine == 'baidu';
    final url = baidu
        ? 'https://www.baidu.com/s?wd=${Uri.encodeComponent(query)}'
        : 'https://cn.bing.com/search?q=${Uri.encodeComponent(query)}&mkt=zh-CN';
    final doc = html.parse(await _get(url, dio));
    final out = <Map<String, String>>[];
    for (final e in doc.querySelectorAll(baidu ? 'div.c-result.result, div.result' : 'li.b_algo')) {
      final a = e.querySelector(baidu ? '[data-module="title"] a, h3 a' : 'h2 a');
      if (a == null) continue;
      final snippet = e.querySelector(baidu ? '.c-abstract, [data-module="abstract"]' : '.b_caption p, .b_lineclamp2')?.text.trim() ?? '';
      out.add({'title': a.text.trim(), 'url': a.attributes['href'] ?? '', 'snippet': snippet});
      if (out.length >= 8) break;
    }
    return jsonEncode(out);
  }

  static Future<String> webFetch(String url, {Dio? dio}) async {
    if (!url.startsWith('http')) return '无效的网址';
    final doc = html.parse(await _get(url, dio));
    for (final e in doc.querySelectorAll('script,style,noscript,header,footer,nav,aside')) {
      e.remove();
    }
    final text = (doc.body?.text ?? '').replaceAll(RegExp(r'\s*\n\s*'), '\n').replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    return text.length > maxChars ? '${text.substring(0, maxChars)}\n（网页内容过长已截断）' : text;
  }
}
