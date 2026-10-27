// pages/setting/choose_svg.dart — 选择气泡 (`ChooseSvgPage`, 35 functions): the paragraph-comment bubbles (data/svg.dart, items {id, svg}).
// Tap selects (prefs `svg` = id, 0x102a218). The list is `Svg.available` (0x2273b0: the stored bubbles for members, the four
// built-in `desvgs` otherwise). Editing, exporting and importing are member-only: `仅会员可编辑` / `仅会员可导出` / `仅会员可导入`.
// Delete asks `确定要删除这个气泡吗？` and keeps at least one (`至少保留一个气泡`, 0x1093994). The editor (添加气泡 / 编辑气泡, 0x1094270:
// a new bubble gets the current time as id, preview colour `#FF0000`, preview text `1`) has SVG代码 (`$color` / `$displayText`
// placeholders), 颜色, 显示内容 and 预览 (0x1093800: `SvgPicture.string` 120×120, `预览失败: ` on error); `ID和SVG代码不能为空`.
// Rows (0x7fb968): rounded card, 60×60 preview in `#FF0000` with text `1`, the first 100 characters of the code, a menu button.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture;
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

  /// 0x1093800: the preview of one bubble, [size]×[size] (120 in the editor), `预览失败: <e>` when the code does not parse.
  static Widget preview(BuildContext context, String svg, {String color = '#FF0000', String text = '1', double size = 120}) {
    final filled = render(svg, color: color, text: text);
    try {
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: SvgPicture.string(
            filled,
            width: size,
            height: size,
            errorBuilder: (ctx, e, _) => _failed(ctx, e),
          ),
        ),
      );
    } catch (e) {
      return _failed(context, e);
    }
  }

  static Widget _failed(BuildContext context, Object e) =>
      Center(child: Text('预览失败: $e', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)));

  /// 0x1028d98: the selected bubble as a 20×20 icon (white text on dark themes, black otherwise, `99` as content), for the
  /// setting rows that show the current choice. [id] defaults to the stored selection.
  static Widget current(BuildContext context, {String? id}) {
    final s = Svg.selected(id ?? Storage.getString(selectedKey));
    if (s == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return preview(context, s.svg, color: dark ? '#ffffff' : '#000000', text: '99', size: 20);
  }

  @override
  State<ChooseSvgPage> createState() => _ChooseSvgPageState();
}

class _ChooseSvgPageState extends State<ChooseSvgPage> {
  String _selected = Storage.getString(ChooseSvgPage.selectedKey);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      await Svg.load();
    } catch (e) {
      Toast.show('加载SVG失败: $e', iserror: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit([Svgimage? old]) async {
    if (!Vip.require('仅会员可编辑')) return;
    final id = TextEditingController(text: old?.id ?? '${DateTime.now().millisecondsSinceEpoch}');
    final code = TextEditingController(text: old?.svg ?? '');
    final color = TextEditingController(text: '#FF0000');
    final text = TextEditingController(text: '1');
    final saved = await showDialog<Svgimage>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(old == null ? '添加气泡' : '编辑气泡'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  key: const Key('svg_code'),
                  controller: code,
                  minLines: 3,
                  maxLines: 8,
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(
                    labelText: 'SVG代码',
                    helperText: '使用 \$color 替换为文字颜色\n使用 \$displayText 替换为气泡内容',
                    hintText: r'输入SVG代码，使用$color和$displayText占位符',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: color,
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(
                    labelText: '颜色',
                    helperText: '用于替换 \$color 占位符为文字颜色 , 当前颜色仅展示实际以阅读页文字颜色为准，如需要保持颜色请勿使用占位符',
                    helperMaxLines: 3,
                    hintText: '预览颜色，如#FF0000',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: text,
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(
                    labelText: '显示内容',
                    helperText: '用于替换 \$displayText 占位符为气泡内容，当前仅为展示，实际以书本内容为准',
                    helperMaxLines: 3,
                    hintText: '气泡中显示的文字',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('预览', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: code.text.isEmpty
                      ? const Center(child: Text('输入SVG代码后显示预览'))
                      : ChooseSvgPage.preview(ctx, code.text, color: color.text, text: text.text),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(
              key: const Key('svg_save'),
              onPressed: () {
                if (id.text.isEmpty || code.text.isEmpty) {
                  ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(content: Text('ID和SVG代码不能为空')));
                  Toast.show('ID和SVG代码不能为空', iserror: true);
                  return;
                }
                Navigator.of(ctx).pop(Svgimage(id: id.text, svg: code.text));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await Svg.put(saved.id, saved.svg);
    await _reload();
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

  Widget _item(Svgimage s) {
    final cs = Theme.of(context).colorScheme;
    final on = _selected == s.id;
    final snippet = s.svg.substring(0, math.min(100, s.svg.length));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('svg_item_${s.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Storage.setString(ChooseSvgPage.selectedKey, s.id);
            setState(() => _selected = s.id);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: on ? cs.primary.withValues(alpha: 0.1) : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? cs.primary : cs.outline.withValues(alpha: 0.2), width: on ? 2 : 1),
            ),
            child: Row(children: [
              SizedBox(width: 60, height: 60, child: ChooseSvgPage.preview(context, s.svg, size: 60)),
              const SizedBox(width: 16),
              Expanded(
                child: Text('$snippet...', maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) { 'edit' => _edit(s), 'export' => _export(s), _ => _delete(s) },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'export', child: Text('导出')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = Svg.available;
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
              for (final s in list) _item(s),
            ]),
    );
  }
}
