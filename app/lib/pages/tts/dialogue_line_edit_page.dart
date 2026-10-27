// pages/tts/dialogue_line_edit_page.dart — 编辑对话 (`DialogueLineEditPage`, 23 functions): the dialogue lines of one chapter as the role
// analysis split them (ai/read.dart), with 上一章 / 下一章 (`第 n 章`), the speaker of each line editable (说话人; gender from the
// character library: `x 的性别以角色库为准`), `ai分角色中...`, `等 n 个角色`, `本章没有识别到对话`, `已保存` and the refresh action
// (`已清除全部缓存，正在重新分角色`). The reader provides the chapter text through [loadLines] (paragraph id → text).
import 'package:flutter/material.dart';

import '../../ai/read.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';

class DialogueLineEditPage extends StatefulWidget {
  /// Paragraphs of chapter [index] (id → text).
  final Future<Map<String, String>> Function(int index) loadLines;
  final int chapterCount;
  final int initialChapter;

  /// Prefix of the analysis cache key (the book url); the chapter index is appended.
  final String cacheKey;
  const DialogueLineEditPage({super.key, required this.loadLines, required this.chapterCount, this.initialChapter = 0, this.cacheKey = ''});

  @override
  State<DialogueLineEditPage> createState() => _DialogueLineEditPageState();
}

class _DialogueLineEditPageState extends State<DialogueLineEditPage> {
  late int _chapter = widget.initialChapter;
  List<RoleLine>? _lines;
  String _error = '';

  String get _key => '${widget.cacheKey}#$_chapter';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() {
      _lines = null;
      _error = '';
    });
    try {
      if (fresh) {
        final f = AiRead.cacheFile(_key);
        if (f.existsSync()) f.deleteSync();
        Toast.show('已清除全部缓存，正在重新分角色');
      }
      final text = await widget.loadLines(_chapter);
      final r = await AiRead.rolesFor(_key, text);
      if (mounted) setState(() => _lines = r.where((l) => !l.ispb).toList());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _editSpeaker(int i) async {
    final l = _lines![i];
    final name = await Dialogs.input(context, '说话人', initial: l.name);
    if (name == null) return;
    final next = RoleLine(id: l.id, ispb: l.ispb, gender: l.gender, str: l.str, name: name.trim(), personality: l.personality);
    setState(() => _lines![i] = next);
    await AiRead.writeCache(_key, _lines!);
    Toast.show('已保存');
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final names = lines?.map((l) => l.name).where((n) => n.isNotEmpty).toSet() ?? {};
    return Scaffold(
      appBar: AppBar(title: Text('编辑对话 · 第 ${_chapter + 1} 章'), actions: [
        IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: () => _load(fresh: true)),
      ]),
      body: Column(children: [
        if (lines == null && _error.isEmpty) const LinearProgressIndicator(),
        if (lines != null && names.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${names.take(3).join('、')}${names.length > 3 ? ' 等 ${names.length} 个角色' : ''}'),
          ),
        Expanded(
          child: _error.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error)))
              : lines == null
                  ? const Center(child: Text('ai分角色中...'))
                  : lines.isEmpty
                      ? const Center(child: Text('本章没有识别到对话'))
                      : ListView.separated(
                          itemCount: lines.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) => ListTile(
                            title: Text(lines[i].str),
                            subtitle: Text('说话人：${lines[i].name.isEmpty ? '未知' : lines[i].name}'),
                            trailing: const Icon(Icons.edit_outlined, size: 18),
                            onTap: () => _editSpeaker(i),
                          ),
                        ),
        ),
        SafeArea(
          child: Row(children: [
            Expanded(
              child: TextButton(
                onPressed: _chapter > 0
                    ? () {
                        _chapter--;
                        _load();
                      }
                    : null,
                child: const Text('上一章'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: _chapter < widget.chapterCount - 1
                    ? () {
                        _chapter++;
                        _load();
                      }
                    : null,
                child: const Text('下一章'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
