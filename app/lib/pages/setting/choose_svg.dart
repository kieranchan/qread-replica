// pages/setting/choose_svg.dart — 选择气泡 (`ChooseSvgPage`, 35 functions): the paragraph-comment bubbles (data/svg.dart, items {id, svg}).
// Tap selects (prefs `svg` = id, 0x102a218). Editing, exporting and importing are member-only: `仅会员可编辑` / `仅会员可导出` /
// `仅会员可导入`. Delete asks `确定要删除这个气泡吗？` and keeps at least one (`至少保留一个气泡`). The editor (添加气泡 / 编辑气泡) has
// SVG代码 (`$color` / `$displayText` placeholders), 颜色 (`预览颜色，如#FF0000`), 显示内容 and 预览; `ID和SVG代码不能为空`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../common/app_dirs.dart';
import '../../data/svg.dart';
import '../../models/svgimage.dart';
import '../../storage/storage.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';

class ChooseSvgPage extends StatefulWidget {
  const ChooseSvgPage({super.key});

  static const String selectedKey = 'svg';

  /// The SVG text with its placeholders filled (what the reader renders): `$color` (default `#ffffff`) and `$displayText` (`99`).
  static String render(String svg, {String color = '#ffffff', String text = '99'}) =>
      svg.replaceAll(r'$color', color).replaceAll(r'$displayText', text);

  @override
  State<ChooseSvgPage> createState() => _ChooseSvgPageState();
}

class _ChooseSvgPageState extends State<ChooseSvgPage> {
  String _selected = Storage.getString(ChooseSvgPage.selectedKey);

  @override
  void initState() {
    super.initState();
    Svg.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _edit([Svgimage? old]) async {
    if (!Vip.require('仅会员可编辑')) return;
    final id = TextEditingController(text: old?.id ?? '');
    final code = TextEditingController(text: old?.svg ?? '');
    final color = TextEditingController(text: '#FF0000');
    final text = TextEditingController(text: '99');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(old == null ? '添加气泡' : '编辑气泡'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: id, readOnly: old != null, decoration: const InputDecoration(labelText: 'ID')),
                TextField(
                  controller: code,
                  minLines: 3,
                  maxLines: 8,
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(labelText: 'SVG代码', hintText: r'输入SVG代码，使用$color和$displayText占位符'),
                ),
                TextField(controller: color, onChanged: (_) => setS(() {}), decoration: const InputDecoration(labelText: '颜色', hintText: '预览颜色，如#FF0000')),
                TextField(controller: text, onChanged: (_) => setS(() {}), decoration: const InputDecoration(labelText: '显示内容', hintText: '气泡中显示的文字')),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text('预览', style: Theme.of(ctx).textTheme.labelLarge)),
                const SizedBox(height: 4),
                // TODO(asm 0x1028d98): the original renders the SVG (flutter_svg); the replica has no SVG renderer and shows the filled text.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  child: Text(
                    code.text.isEmpty ? '输入SVG代码后显示预览' : ChooseSvgPage.render(code.text, color: color.text, text: text.text),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (id.text.trim().isEmpty || code.text.trim().isEmpty) return Toast.show('ID和SVG代码不能为空', iserror: true);
    await Svg.put(id.text.trim(), code.text);
    if (mounted) setState(() {});
  }

  Future<void> _delete(Svgimage s) async {
    if (!Vip.require('仅会员可编辑')) return;
    if (Svg.svgs.length <= 1) return Toast.show('至少保留一个气泡', iserror: true);
    if (!await Dialogs.confirm(context, '删除确认', '确定要删除这个气泡吗？', danger: true)) return;
    await Svg.delete(s.id);
    if (_selected == s.id) {
      _selected = '';
      await Storage.remove(ChooseSvgPage.selectedKey);
    }
    if (mounted) setState(() {});
  }

  Future<void> _export(Svgimage s) async {
    if (!Vip.require('仅会员可导出')) return;
    try {
      final d = await AppDirs.ensure('cache');
      final f = File(p.join(d.path, 'svg_${s.id}.json'));
      await f.writeAsString(jsonEncode([s.toJson()]));
      await DeviceIo.shareFile(f);
    } catch (e) {
      Toast.show('导出SVG失败: $e', iserror: true);
    }
  }

  Future<void> _import() async {
    if (!Vip.require('仅会员可导入')) return;
    try {
      final f = await DeviceIo.pickFile(extensions: const ['json', 'txt', 'svg']);
      if (f == null) return;
      final text = await f.readAsString();
      if (f.path.toLowerCase().endsWith('.svg')) {
        await Svg.put(p.basenameWithoutExtension(f.path), text);
      } else {
        final v = jsonDecode(text);
        for (final e in v is List ? v : [v]) {
          if (e is Map && '${e['id'] ?? ''}'.isNotEmpty && '${e['svg'] ?? ''}'.isNotEmpty) await Svg.put('${e['id']}', '${e['svg']}');
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      Toast.show('导入SVG失败: $e', iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = Svg.svgs;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('选择气泡'), actions: [
        IconButton(key: const Key('svg_import'), tooltip: '导入', icon: const Icon(Icons.file_open_outlined), onPressed: _import),
        IconButton(key: const Key('svg_add'), tooltip: '添加气泡', icon: const Icon(Icons.add), onPressed: () => _edit()),
      ]),
      body: list.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('暂无气泡'),
                Text('点击右上角+号添加气泡', style: TextStyle(color: cs.outline)),
              ]),
            )
          : ListView(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('气泡列表', style: TextStyle(color: cs.primary))),
              for (final s in list)
                ListTile(
                  leading: Icon(_selected == s.id ? Icons.radio_button_checked : Icons.radio_button_off, color: cs.primary),
                  title: Text(s.id),
                  subtitle: Text(s.svg, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  onTap: () async {
                    await Storage.setString(ChooseSvgPage.selectedKey, s.id);
                    setState(() => _selected = s.id);
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => switch (v) { 'edit' => _edit(s), 'export' => _export(s), _ => _delete(s) },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'export', child: Text('导出')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ),
            ]),
    );
  }
}
