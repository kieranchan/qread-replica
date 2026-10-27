// pages/theme/edit_page_style_page.dart — edits one page style of a theme (`EditPageStylePage`, 30 functions): 背景图片 (选择背景图片,
// stored under `<root>/themes`), 背景颜色, 表格透明度 (0..100, buttons 减 / 加), 阴影开关, with a small preview of a card ("第 n 区 / 行").
// Returns the edited [PageStyle] (null when closed without saving).
import 'package:flutter/material.dart';

import '../../models/theme.dart';
import '../../theme/theme_provider.dart';
import '../../theme/widgets.dart';
import 'theme_package.dart';

class EditPageStylePage extends StatefulWidget {
  final PageStyle style;
  final String title;
  const EditPageStylePage({super.key, required this.style, this.title = '编辑'});

  @override
  State<EditPageStylePage> createState() => _EditPageStylePageState();
}

class _EditPageStylePageState extends State<EditPageStylePage> {
  late final PageStyle s = PageStyle.fromJson(widget.style.toJson());

  Future<void> _pickImage() async {
    final f = await DeviceIo.pickFile(image: true);
    if (f == null) return;
    final path = await ThemePackage.storeImage(f, 'themes');
    setState(() => s.backgroundImage = path);
  }

  Future<void> _pickColor() async {
    final c = await pickColor(context, initial: ThemeColors.of(s.backgroundColor), title: '背景颜色');
    if (c == null) return;
    setState(() => s.backgroundColor = c.cleared ? null : (c.color == null ? null : ThemeColors.toInt(c.color!)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = ThemeFiles.image(s.backgroundImage);
    final bg = ThemeColors.of(s.backgroundColor);
    final card = cs.surfaceContainerLow.withValues(alpha: (100 - s.tableOpacity.clamp(0, 100)) / 100);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        TextButton(key: const Key('style_save'), onPressed: () => Navigator.of(context).pop(s), child: const Text('保存')),
      ]),
      body: ListView(children: [
        Container(
          height: 180,
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg ?? cs.surface,
            borderRadius: BorderRadius.circular(12),
            image: img == null ? null : DecorationImage(image: img, fit: BoxFit.cover),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            for (var i = 1; i <= 2; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: s.showboxShadow ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)] : null,
                ),
                child: Row(children: [Text('第 $i 区'), const Spacer(), const Text('行')]),
              ),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: const Text('背景图片'),
          subtitle: Text(s.backgroundImage.isEmpty ? '选择背景图片' : s.backgroundImage, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: s.backgroundImage.isEmpty
              ? const Icon(Icons.chevron_right)
              : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => s.backgroundImage = '')),
          onTap: _pickImage,
        ),
        ListTile(
          leading: const Icon(Icons.format_color_fill),
          title: const Text('背景颜色'),
          trailing: Container(width: 28, height: 28, decoration: BoxDecoration(color: bg, border: Border.all(color: cs.outline), shape: BoxShape.circle)),
          onTap: _pickColor,
        ),
        ListTile(
          leading: const Icon(Icons.opacity),
          title: const Text('表格透明度'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: '减', icon: const Icon(Icons.remove), onPressed: () => setState(() => s.tableOpacity = (s.tableOpacity - 5).clamp(0, 100))),
            Text('${s.tableOpacity}'),
            IconButton(tooltip: '加', icon: const Icon(Icons.add), onPressed: () => setState(() => s.tableOpacity = (s.tableOpacity + 5).clamp(0, 100))),
          ]),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.blur_on),
          title: const Text('阴影开关'),
          value: s.showboxShadow,
          onChanged: (v) => setState(() => s.showboxShadow = v),
        ),
      ]),
    );
  }
}
