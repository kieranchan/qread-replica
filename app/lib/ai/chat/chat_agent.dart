// ai/chat/chat_agent.dart — 时光 AI 助手 (the reader's AI chat; original ai/chat/chat_agent.dart on langchain + openai_dart). A run streams
// the model's answer, executes the tool calls it asks for and feeds the results back, at most [maxRounds] = 10 rounds
// (`工具调用轮数超过上限（10 轮）`), each round failing after 60 s without data (`响应超时（60 秒无数据）`) and each tool after its own
// timeout (`执行超时`). The system prompt is the original's (0x7e19f8, pool 0x71140..0x71180): the deep-thinking line
// `当前为深度思考模式，请深入全面地分析。` first when on, then the 时光 persona with book name, current chapter and the tool workflow
// (web_search ≥ 2 queries, web_fetch, no get_book_digest for whole-book summaries, characters from the library, get_chat_history,
// at most 10 rounds). When the model rejects
// tools, the agent retries once without them and with the current chapter inlined (`当前模型不支持工具调用，已内联当前章节（此时无法修改参数）`).
// Member-only like the original sheet: `当前功能仅对会员开放`.
//
// Tools are plugged in as [ChatTool]s. This file provides the web tools (web_search on Bing / Baidu result pages, web_fetch with the
// noise tags removed and `网页内容过长已截断`) and `get_chat_history`; the reader area adds the book tools (chapter text, digest,
// characters, settings) through [ChatContext] / [ChatAgent.tools]; [ChatAgent.chatWithTools] serves callers that hold plain
// `{role, content}` maps (the reader's `ReaderAiTools`), [ChatAgent.onToolCall] reports every executed call.
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

  /// The chapter the user is on, as shown (`用户当前在第 N 章`); 0 = unknown.
  final int chapterNumber;

  /// Current chapter text (inlined when the model has no tool support).
  final Future<String> Function()? chapterText;
  const ChatContext({this.bookName = '', this.chapterCount = 0, this.chapterTitle = '', this.chapterText, this.chapterNumber = 0});
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

  /// Replaces [systemPrompt] (a caller that builds its own, e.g. the reader's sheet).
  final String? systemOverride;

  /// Called after every executed tool call with its result (progress display, logging, settings refresh).
  final void Function(AiToolCallReq call, String result)? onToolCall;

  ChatAgent(this.model,
      {this.tools = const [],
      this.context = const ChatContext(),
      this.deepThinking = false,
      this.dio,
      this.idleTimeout = const Duration(seconds: 60),
      this.systemOverride,
      this.onToolCall});

  /// The original's system prompt (0x7e19f8).
  String get systemPrompt {
    final book = context.bookName;
    final chapter = context.chapterNumber > 0 ? '${context.chapterNumber}' : (context.chapterTitle.isNotEmpty ? context.chapterTitle : '1');
    return '${deepThinking ? deepPrefix : ''}你叫时光，是《$book》的阅读助手，用户当前在第 $chapter 章。回复时以「时光」自称。需要正文或章节信息时调用内容工具，'
        '不要凭记忆编造内容；用户要求调整阅读参数时调用参数工具，改后用一句话说明改了什么；当用户要求总结全书、了解整本书剧情或结局时，按以下流程操作：'
        '①至少调用 web_search 两次以上，使用不同关键词（如「$book 小说 简介」「$book 剧情介绍」「$book 大结局/结局」）；②从结果中挑 1~3 个最相关链接，'
        '用 web_fetch 读取正文获取详细剧情；③综合搜索摘要与网页内容，按「作品概况、核心主线、核心角色、作品特色」等结构输出完整总结；禁止调用 get_book_digest，'
        '禁止仅凭一次搜索或只看搜索摘要就回答"找不到信息"；只有在更换 3 个以上关键词且相关链接均无法打开后，才可告知未找到资料；涉及人物的信息一律以角色库为'
        '权威来源，发现新角色时通过 extract_characters 自动入库；默认只提供最近几轮对话，需要更早的对话内容时调用 get_chat_history 获取。你最多只能调用 '
        '$maxRounds 轮工具。请在达到上限前完成所有必要调用并整理最终回复；如果你发现工具调用轮数即将达到 $maxRounds 轮，必须立即总结当前已掌握的信息并给出'
        '最终回答，不要继续调用工具，否则会因超轮而被迫中断。请用中文简洁回答。';
  }

  /// For callers with plain `{role, content}` maps: the leading system message (if any) replaces the prompt, the last user message
  /// is the question, the rest is history. Streams the answer text (tool rounds included); notices are streamed as text too.
  static Stream<String> chatWithTools(AiModelConfig model, List<Map<String, String>> messages, List<ChatTool> tools,
      {bool deep = false, ChatContext context = const ChatContext(), void Function(AiToolCallReq call, String result)? onToolCall, Dio? dio}) async* {
    var list = [...messages];
    String? system;
    if (list.isNotEmpty && list.first['role'] == 'system') {
      system = list.first['content'];
      list = list.sublist(1);
    }
    var question = '';
    if (list.isNotEmpty && list.last['role'] == 'user') {
      question = list.last['content'] ?? '';
      list = list.sublist(0, list.length - 1);
    }
    final history = [for (final m in list) AiMessage(m['role'] ?? 'user', m['content'] ?? '')];
    final agent = ChatAgent(model,
        tools: tools,
        deepThinking: deep,
        context: context,
        dio: dio,
        systemOverride: system == null ? null : '${deep ? deepPrefix : ''}$system',
        onToolCall: onToolCall);
    await for (final e in agent.run(history, question)) {
      switch (e) {
        case ChatText(:final text):
          yield text;
        case ChatNotice(:final message):
          yield '\n$message\n';
        default:
          break;
      }
    }
  }

  /// Runs one user turn after [history] (earlier user / assistant / tool messages).
  Stream<ChatEvent> run(List<AiMessage> history, String userText, {CancelToken? cancel}) async* {
    if (!UserSession.isvip) throw const AiException(memberOnly);
    final client = OpenAiClient(model, dio: dio);
    final msgs = <AiMessage>[
      AiMessage.system(systemOverride ?? systemPrompt),
      ...history,
      AiMessage.user(userText),
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
        onToolCall?.call(call, result);
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
