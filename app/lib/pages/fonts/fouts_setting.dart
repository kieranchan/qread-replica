// pages/fonts/fouts_setting.dart — 字体管理 (`FontsSetting`, state `_FontsSettingState`, 33 functions): the imported fonts
// (data/fonts.dart) with a preview line in each font, 添加字体 (pick a TTF/OTF file — `请选择字体文件`, `已选择文件: …` — then
// 字体名称 `请输入字体名称`; `字体名称不能只包含特殊符号`; a duplicate name fails with `名称重复：…`), multi-select (全选 (n) / 反选) and
// delete (`确定要删除这些字体吗？`; fonts used by an installed theme are kept: `部分字体被主题应用`). Empty: `还没有添加字体` /
// `点击右上角添加字体开始使用`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/fonts.dart';
import '../../data/theme.dart';
import '../../theme/theme_provider.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';

class FontsSetting extends StatefulWidget {
  const FontsSetting({super.key});

  @override
  State<FontsSetting> createState() => _FontsSettingState();
}

class _FontsSettingState extends State<FontsSetting> {
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    FontsData.load().then((_) async {
      for (final f in FontsData.fonts) {
        await AppFonts.ensureLoaded(f.family);
      }
      if (mounted) setState(() {});
    });
  }

  /// Letters, digits or CJK must remain after removing symbols.
  static bool validName(String name) => RegExp(r'[A-Za-z0-9一-龥]').hasMatch(name);

  Future<void> _add() async {
    File? file;
    try {
      file = await DeviceIo.pickFile(extensions: const ['ttf', 'otf']);
    } catch (e) {
      Toast.show('选择文件失败:$e', iserror: true);
      return;
    }
    if (file == null) return;
    if (!mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: p.basenameWithoutExtension(file!.path));
        return AlertDialog(
          title: const Text('添加字体'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('已选择文件: ${p.basename(file.path)}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(key: const Key('font_name'), controller: c, decoration: const InputDecoration(labelText: '字体名称', hintText: '请输入字体名称')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: const Text('确定')),
          ],
        );
      },
    );
    if (name == null) return;
    if (name.isEmpty) return Toast.show('请输入字体名称', iserror: true);
    if (!validName(name)) return Toast.show('字体名称不能只包含特殊符号', iserror: true);
    try {
      await Fonts.importFile(name, file);
      await AppFonts.ensureLoaded(name);
      Toast.show('添加成功');
    } catch (e) {
      Toast.show(e is StateError ? e.message : '$e', iserror: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    if (_selected.isEmpty) return;
    if (!await Dialogs.confirm(context, '删除确认', '确定要删除这些字体吗？', danger: true)) return;
    final used = <String>{
      for (final t in ThemeManager.themes) ...[t.navFont, t.titleFont, t.regularFont],
    };
    var kept = false;
    for (final f in _selected.toList()) {
      if (used.contains(f)) {
        kept = true;
        continue;
      }
      try {
        await Fonts.remove(f);
      } catch (e) {
        Toast.show('删除失败: $e', iserror: true);
      }
    }
    if (kept) Toast.show('部分字体被主题应用');
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fonts = FontsData.fonts;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('字体管理'),
        actions: [
          if (_selecting) ...[
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == fonts.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(fonts.map((f) => f.family));
                }
              }),
              child: Text('全选 (${_selected.length})'),
            ),
            TextButton(
              onPressed: () => setState(() {
                final all = fonts.map((f) => f.family).toSet();
                final inv = all.difference(_selected);
                _selected
                  ..clear()
                  ..addAll(inv);
              }),
              child: const Text('反选'),
            ),
            IconButton(tooltip: '删除', icon: const Icon(Icons.delete_outline), onPressed: _delete),
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selecting = false)),
          ] else
            IconButton(key: const Key('font_add'), tooltip: '添加字体', icon: const Icon(Icons.add), onPressed: _add),
        ],
      ),
      body: fonts.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.font_download_outlined, size: 56, color: cs.outline),
                const SizedBox(height: 12),
                const Text('还没有添加字体'),
                const SizedBox(height: 4),
                Text('点击右上角添加字体开始使用', style: TextStyle(color: cs.outline)),
              ]),
            )
          : ListView.separated(
              itemCount: fonts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final f = fonts[i];
                return ListTile(
                  title: Text(f.family),
                  subtitle: Text('轻悦时光 Aa 123', style: TextStyle(fontFamily: f.family, fontSize: 18)),
                  leading: _selecting
                      ? Checkbox(
                          value: _selected.contains(f.family),
                          onChanged: (v) => setState(() => v == true ? _selected.add(f.family) : _selected.remove(f.family)))
                      : const Icon(Icons.text_fields),
                  onLongPress: () => setState(() {
                    _selecting = true;
                    _selected.add(f.family);
                  }),
                  onTap: _selecting
                      ? () => setState(() => _selected.contains(f.family) ? _selected.remove(f.family) : _selected.add(f.family))
                      : null,
                );
              },
            ),
    );
  }
}
