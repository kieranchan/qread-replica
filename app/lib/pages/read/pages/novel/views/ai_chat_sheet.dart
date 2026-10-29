// pages/read/pages/novel/views/ai_chat_sheet.dart — "时光 AI 助手": a chat about the book being read (original `_AiChatSheetState`).
// Member feature (`当前功能仅对会员开放`). Strings of the original: 时光 AI 助手 · 新会话 · 默认 · 深度 · 服务说明 ·
// AI 能力由您配置的第三方模型提供，本应用不提供合成生成服务 · 未配置模型 · 请先在模型管理中添加模型 · [已停止] · 确定删除会话「…」吗？ · 删除 · 关闭 ·
// 更多. Sessions are stored per book (`Setting.getAiChatSessions`), the last model in prefs `aiChatLastModel`. The model is reached
// through [ReaderAi]. "提取角色" asks the model for the characters of the chapter and stores them in the character library
// (`ai_character_page.dart`).
// With an adapter that implements [ReaderAiTools] and the reader's live [ReadSetting], the model can read and change the reading
// settings through the tools of read_setting_tools.dart (the reader re-lays out on the change, like the original's 0x57606c).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../../common/nav.dart';
import '../../../../../models/ai_character.dart';
import '../../../../../models/ai_chat_session.dart';
import '../../../../../models/book.dart';
import '../../../../../read/api/read_file_store.dart';
import '../../../../../read/setting/read_setting.dart';
import '../../../../../storage/setting.dart';
import '../../../../../storage/storage.dart';
import '../../../../../util/toast.dart';
import '../../../../../util/vip.dart';
import '../../../reader_ai.dart';
import 'ai_character_page.dart';
import 'read_setting_tools.dart';

/// Per-book key of the chat sessions and the character library.
String aiBookKey(Book book) => ReadFileStore.md5Hex(book.bookUrl);

/// Opens the sheet after the member check (`当前功能仅对会员开放`).
Future<void> showAiChatSheet(BuildContext context,
    {required Book book, String chapterTitle = '', String chapterText = '', ReadSetting? setting, List<String> fonts = const []}) async {
  if (!Vip.require('当前功能仅对会员开放')) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: AiChatSheet(book: book, chapterTitle: chapterTitle, chapterText: chapterText, setting: setting, fonts: fonts),
    ),
  );
}

class AiChatSheet extends StatefulWidget {
  final Book book;
  final String chapterTitle;
  final String chapterText;

  /// The reader's live settings (enables the reading-settings tools).
  final ReadSetting? setting;
  final List<String> fonts;

  const AiChatSheet({super.key, required this.book, this.chapterTitle = '', this.chapterText = '', this.setting, this.fonts = const []});

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  late List<AiChatSession> _sessions;
  AiChatSession? _cur;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<String>? _sub;
  bool _sending = false;
  String _modelId = Storage.getString('aiChatLastModel');

  String get _key => aiBookKey(widget.book);
  ReaderAi? get _ai => ReaderAi.instance;

  @override
  void initState() {
    super.initState();
    _sessions = Setting.getAiChatSessions(_key);
    _cur = _sessions.isEmpty ? null : _sessions.first;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<AiChatMessage> get _messages =>
      [for (final m in _cur?.messages ?? const []) if (m is Map) AiChatMessage.fromJson(Map<String, dynamic>.from(m))];

  Future<void> _persist() => Setting.saveAiChatSessions(_key, _sessions);

  AiChatSession _newSession() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = AiChatSession(id: '$now', title: '新会话', modelId: _modelId, createdAt: now, updatedAt: now);
    _sessions.insert(0, s);
    return s;
  }

  String get _systemPrompt {
    final text = widget.chapterText.length > 4000 ? widget.chapterText.substring(0, 4000) : widget.chapterText;
    return '你是阅读助手。用户正在阅读《${widget.book.name}》（作者：${widget.book.author}），当前章节：${widget.chapterTitle}。\n'
        '当前章节正文（节选）：\n$text';
  }

  Future<void> _send([String? preset]) async {
    final ai = _ai;
    if (ai == null) {
      Toast.show('未配置模型');
      return;
    }
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    final s = _cur ?? _newSession();
    _cur = s;
    final now = DateTime.now().millisecondsSinceEpoch;
    s.messages.add(AiChatMessage(role: 'user', content: text, timestamp: now).toJson());
    if (s.title == '新会话') s.title = text.length > 16 ? text.substring(0, 16) : text;
    final reply = AiChatMessage(role: 'assistant', content: '', timestamp: now);
    s.messages.add(reply.toJson());
    s.modelId = _modelId;
    setState(() => _sending = true);
    final history = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt},
      for (final m in _messages.take(_messages.length - 1)) {'role': m.role, 'content': m.content},
    ];
    final buf = StringBuffer();
    final done = Completer<void>();
    final setting = widget.setting;
    final stream = ai is ReaderAiTools && setting != null
        ? (ai as ReaderAiTools).chatWithTools(history, ReadSettingApplier(setting, fonts: widget.fonts).tools(),
            modelId: _modelId.isEmpty ? null : _modelId, deep: s.deepThinking)
        : ai.chat(history, modelId: _modelId.isEmpty ? null : _modelId, deep: s.deepThinking);
    _sub = stream.listen(
      (chunk) {
        buf.write(chunk);
        s.messages[s.messages.length - 1] = AiChatMessage(role: 'assistant', content: buf.toString(), timestamp: now).toJson();
        if (mounted) setState(() {});
        _toEnd();
      },
      onError: (Object e) {
        buf.write('\n$e');
        s.messages[s.messages.length - 1] = AiChatMessage(role: 'assistant', content: buf.toString(), timestamp: now).toJson();
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
    await _finish(s);
  }

  Future<void> _finish(AiChatSession s) async {
    _sub = null;
    s.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _persist();
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _stop() async {
    final s = _cur;
    await _sub?.cancel();
    if (s != null && s.messages.isNotEmpty) {
      final last = AiChatMessage.fromJson(Map<String, dynamic>.from(s.messages.last as Map));
      s.messages[s.messages.length - 1] = AiChatMessage(role: last.role, content: '${last.content}[已停止]', timestamp: last.timestamp).toJson();
      await _finish(s);
    }
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// "提取角色": asks the model for a JSON list of characters and merges it into the library.
  Future<void> _extractCharacters() async {
    final ai = _ai;
    if (ai == null) {
      Toast.show('未配置模型');
      return;
    }
    final prompt = '请从当前章节中提取出场角色，只输出 JSON 数组，每项包含 name、gender（0未知 1男 2女）、personality（个性描述）。';
    final buf = StringBuffer();
    try {
      await for (final c in ai.chat([
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': prompt},
      ], modelId: _modelId.isEmpty ? null : _modelId)) {
        buf.write(c);
      }
      final added = mergeCharacters(_key, buf.toString());
      Toast.show(added == 0 ? '未识别到角色名' : '已添加 $added 个角色');
    } catch (e) {
      Toast.show('获取角色名失败：$e');
    }
  }

  Future<void> _deleteSession(AiChatSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('确定删除会话「${s.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    _sessions.removeWhere((e) => e.id == s.id);
    if (_cur?.id == s.id) _cur = _sessions.isEmpty ? null : _sessions.first;
    await _persist();
    if (mounted) setState(() {});
  }

  void _about() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('服务说明'),
          content: const Text('AI 能力由您配置的第三方模型提供，本应用不提供合成生成服务'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      );

  Widget _notConfigured() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('未配置模型'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Nav.openNamed(context, 'ai_model_page'), child: const Text('请先在模型管理中添加模型')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ai = _ai;
    final models = ai?.models ?? const <ReaderAiModel>[];
    final msgs = _messages;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          title: const Text('时光 AI 助手'),
          subtitle: models.isEmpty
              ? null
              : DropdownButton<String>(
                  isDense: true,
                  underline: const SizedBox(),
                  value: models.any((m) => m.id == _modelId) ? _modelId : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('默认')),
                    for (final m in models) DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (v) {
                    setState(() => _modelId = v ?? '');
                    Storage.setString('aiChatLastModel', _modelId);
                  },
                ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_cur != null)
              FilterChip(
                label: const Text('深度'),
                selected: _cur!.deepThinking,
                onSelected: (v) => setState(() => _cur!.deepThinking = v),
              ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) async {
                switch (v) {
                  case 'new':
                    setState(() => _cur = _newSession());
                    await _persist();
                  case 'roles':
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiCharacterPage(bookKey: _key)));
                  case 'extract':
                    await _extractCharacters();
                  case 'about':
                    _about();
                  case 'close':
                    Navigator.pop(context);
                  default:
                    final s = _sessions.where((e) => e.id == v).firstOrNull;
                    if (s != null) setState(() => _cur = s);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'new', child: Text('新会话')),
                const PopupMenuItem(value: 'extract', child: Text('提取角色')),
                const PopupMenuItem(value: 'roles', child: Text('角色库')),
                const PopupMenuItem(value: 'about', child: Text('服务说明')),
                for (final s in _sessions.take(10))
                  PopupMenuItem(
                    value: s.id,
                    child: Row(children: [
                      Expanded(child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteSession(s);
                        },
                      ),
                    ]),
                  ),
                const PopupMenuItem(value: 'close', child: Text('关闭')),
              ],
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ai == null
              ? _notConfigured()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    final me = m.role == 'user';
                    return Align(
                      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxWidth: 560),
                        decoration: BoxDecoration(
                          color: me ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SelectableText(m.content.isEmpty ? '…' : m.content),
                      ),
                    );
                  },
                ),
        ),
        // 0x7e9428: while the answer is on its way
        if (_sending)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Row(children: [
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('思考中…', style: TextStyle(fontSize: 12, color: scheme.outline)),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(left: 12, right: 8, bottom: MediaQuery.viewInsetsOf(context).bottom + 8, top: 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: ai != null,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '问点什么…'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                icon: Icon(_sending ? Icons.stop_circle_outlined : Icons.send),
                onPressed: ai == null ? null : (_sending ? _stop : _send),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Parses the model's JSON answer (a list of `{name, gender, personality}`; text around the JSON is ignored) and adds the characters
/// that are not in the library yet. Returns how many were added.
int mergeCharacters(String bookKey, String answer) {
  final start = answer.indexOf('[');
  final end = answer.lastIndexOf(']');
  if (start < 0 || end <= start) return 0;
  final List<dynamic> list;
  try {
    list = jsonDecode(answer.substring(start, end + 1)) as List;
  } catch (_) {
    return 0;
  }
  final lib = Setting.getAiCharacters(bookKey);
  var added = 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final e in list) {
    if (e is! Map) continue;
    final name = '${e['name'] ?? ''}'.trim();
    if (name.isEmpty || lib.any((c) => c.name == name)) continue;
    lib.add(AiCharacter(
      id: '${now}_$added',
      name: name,
      gender: int.tryParse('${e['gender'] ?? 0}') ?? 0,
      personality: '${e['personality'] ?? ''}',
      updatedAt: now,
    ));
    added++;
  }
  if (added > 0) Setting.saveAiCharacters(bookKey, lib);
  return added;
}
