// pages/theme/tab_icon_page.dart — 标签栏图标 of a theme (`TabIconPage`, state fields `_unselectedIcons` / `_selectedIcons` /
// `_showTitleWhenSelected` / `_showTitleWhenUnselected` / `_tabBarColor` / `_tabBarSelectedColor`): per bottom tab an unselected and
// a selected icon (选择图标 dialog: `当前已选择图标` / `未选择图标`, actions select / clear; images copied to `<root>/tab_icons`,
// hint `建议使用 75px 图片`), the two title switches and the colours 底部状态栏 / 底栏选中颜色 (`选择颜色`, `清除颜色`).
// Returns the edited theme fields as a [TabIconResult].
import 'package:flutter/material.dart';

import '../../theme/theme_provider.dart';
import '../../theme/widgets.dart';
import 'theme_package.dart';

class TabIconResult {
  final List<String> unselected;
  final List<String> selected;
  final bool showTitleWhenSelected;
  final bool showTitleWhenUnselected;
  final int tabBarColor;
  final int tabBarSelectedColor;
  const TabIconResult(this.unselected, this.selected, this.showTitleWhenSelected, this.showTitleWhenUnselected, this.tabBarColor,
      this.tabBarSelectedColor);
}

class TabIconPage extends StatefulWidget {
  final List<String> unselected;
  final List<String> selected;
  final bool showTitleWhenSelected;
  final bool showTitleWhenUnselected;
  final int tabBarColor;
  final int tabBarSelectedColor;
  const TabIconPage({
    super.key,
    this.unselected = const [],
    this.selected = const [],
    this.showTitleWhenSelected = true,
    this.showTitleWhenUnselected = true,
    this.tabBarColor = 0,
    this.tabBarSelectedColor = 0,
  });

  @override
  State<TabIconPage> createState() => _TabIconPageState();
}

class _TabIconPageState extends State<TabIconPage> {
  static final int _n = ThemeProvider.tabNames.length;
  late final List<String> _unselectedIcons = List<String>.generate(_n, (i) => i < widget.unselected.length ? widget.unselected[i] : '');
  late final List<String> _selectedIcons = List<String>.generate(_n, (i) => i < widget.selected.length ? widget.selected[i] : '');
  late bool _showTitleWhenSelected = widget.showTitleWhenSelected;
  late bool _showTitleWhenUnselected = widget.showTitleWhenUnselected;
  late int _tabBarColor = widget.tabBarColor;
  late int _tabBarSelectedColor = widget.tabBarSelectedColor;

  /// 0x103a198: `select` picks and stores an image, `clear` empties the slot.
  Future<void> _choose(List<String> list, int i) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final img = ThemeFiles.image(list[i]);
        return AlertDialog(
          title: const Text('选择图标'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(img == null ? '未选择图标' : '当前已选择图标'),
            const SizedBox(height: 8),
            if (img != null) Image(image: img, width: 48, height: 48, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
            const SizedBox(height: 8),
            Text('建议使用 75px 图片', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop('clear'), child: const Text('清除')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop('select'), child: const Text('选择')),
          ],
        );
      },
    );
    if (action == 'clear') setState(() => list[i] = '');
    if (action == 'select') {
      final f = await DeviceIo.pickFile(image: true);
      if (f == null) return;
      final path = await ThemePackage.storeImage(f, 'tab_icons');
      setState(() => list[i] = path);
    }
  }

  Future<void> _color(bool selected) async {
    final current = selected ? _tabBarSelectedColor : _tabBarColor;
    final c = await pickColor(context, initial: ThemeColors.of(current), title: selected ? '底栏选中颜色' : '底部状态栏');
    if (c == null) return;
    final v = c.cleared || c.color == null ? 0 : ThemeColors.toInt(c.color!);
    setState(() => selected ? _tabBarSelectedColor = v : _tabBarColor = v);
  }

  Widget _iconCell(List<String> list, int i) {
    final img = ThemeFiles.image(list[i]);
    return GestureDetector(
      onTap: () => _choose(list, i),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
        child: img == null ? const Icon(Icons.add, size: 20) : Image(image: img, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('标签栏图标'), actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(TabIconResult(_unselectedIcons, _selectedIcons, _showTitleWhenSelected,
              _showTitleWhenUnselected, _tabBarColor, _tabBarSelectedColor)),
          child: const Text('保存'),
        ),
      ]),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            const SizedBox(width: 56),
            Expanded(child: Center(child: Text('未选中图标', style: TextStyle(color: cs.outline)))),
            Expanded(child: Center(child: Text('选中图标', style: TextStyle(color: cs.outline)))),
          ]),
        ),
        for (var i = 0; i < _n; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              SizedBox(width: 56, child: Text(ThemeProvider.tabNames[i])),
              Expanded(child: Center(child: _iconCell(_unselectedIcons, i))),
              Expanded(child: Center(child: _iconCell(_selectedIcons, i))),
            ]),
          ),
        const Divider(),
        SwitchListTile(title: const Text('选中时显示标题'), value: _showTitleWhenSelected, onChanged: (v) => setState(() => _showTitleWhenSelected = v)),
        SwitchListTile(title: const Text('未选中时显示标题'), value: _showTitleWhenUnselected, onChanged: (v) => setState(() => _showTitleWhenUnselected = v)),
        ListTile(
          title: const Text('底部状态栏'),
          trailing: _swatch(_tabBarColor),
          onTap: () => _color(false),
        ),
        ListTile(
          title: const Text('底栏选中颜色'),
          trailing: _swatch(_tabBarSelectedColor),
          onTap: () => _color(true),
        ),
      ]),
    );
  }

  Widget _swatch(int v) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: ThemeColors.of(v), shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.outline)),
      );
}
