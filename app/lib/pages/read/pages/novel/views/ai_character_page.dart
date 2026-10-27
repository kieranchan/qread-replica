// pages/read/pages/novel/views/ai_character_page.dart — "角色库" of a book (original `_AiCharacterPageState`: 角色库 · 角色库还是空的 ·
// 在聊天中点「提取角色」让 AI 自动整理 · 暂无个性描述 · 确定删除「…」吗？ · 编辑角色 · 新建角色 · 性别 · 男 · 女 · 未知 · 编辑 · 删除). The
// characters (`AiCharacter`) are stored per book by `Setting.getAiCharacters` / `saveAiCharacters`; the TTS multi-role engine reads them.
import 'package:flutter/material.dart';

import '../../../../../models/ai_character.dart';
import '../../../../../storage/setting.dart';

String genderLabel(int g) => switch (g) { 1 => '男', 2 => '女', _ => '未知' };

class AiCharacterPage extends StatefulWidget {
  final String bookKey;
  const AiCharacterPage({super.key, required this.bookKey});

  @override
  State<AiCharacterPage> createState() => _AiCharacterPageState();
}

class _AiCharacterPageState extends State<AiCharacterPage> {
  late List<AiCharacter> _list = Setting.getAiCharacters(widget.bookKey);

  Future<void> _save() async {
    await Setting.saveAiCharacters(widget.bookKey, _list);
    setState(() => _list = Setting.getAiCharacters(widget.bookKey));
  }

  Future<void> _edit([AiCharacter? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final desc = TextEditingController(text: c?.personality ?? '');
    var gender = c?.gender ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c == null ? '新建角色' : '编辑角色'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
            Row(children: [
              const Text('性别'),
              const Spacer(),
              for (final g in const [1, 2, 0])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(label: Text(genderLabel(g)), selected: gender == g, onSelected: (_) => set(() => gender = g)),
                ),
            ]),
            TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: '个性描述')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      ),
    );
    final n = name.text.trim();
    final p = desc.text.trim();
    if (ok != true || n.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (c == null) {
      _list.add(AiCharacter(id: '$now', name: n, gender: gender, personality: p, updatedAt: now));
    } else {
      c
        ..name = n
        ..gender = gender
        ..personality = p
        ..updatedAt = now;
    }
    await _save();
  }

  Future<void> _delete(AiCharacter c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('确定删除「${c.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    _list.removeWhere((e) => e.id == c.id);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('角色库'), actions: [IconButton(tooltip: '新建角色', icon: const Icon(Icons.add), onPressed: _edit)]),
      body: _list.isEmpty
          ? const Center(child: Text('角色库还是空的\n在聊天中点「提取角色」让 AI 自动整理', textAlign: TextAlign.center))
          : ListView.separated(
              itemCount: _list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = _list[i];
                return ListTile(
                  title: Text('${c.name}（${genderLabel(c.gender)}）'),
                  subtitle: Text(c.personality.isEmpty ? '暂无个性描述' : c.personality),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? _edit(c) : _delete(c),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
