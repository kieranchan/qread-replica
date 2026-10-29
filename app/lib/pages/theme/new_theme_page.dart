// pages/theme/new_theme_page.dart — create / edit a theme (`NewThemePage`, 166 functions; the biggest theme page). Sections as in the
// original's strings: basic info (标题 / 简介 / 作者 / 联系 / 图标, 模式 白天 / 夜间), fonts (导航字体 / 标题字体 / 常规字体, 选择字体,
// `未设置`), cover (默认封面, 封面应用范围 全部 / 仅加载失败), colours (基础文本颜色, 浅色 / 深色主题配色方案 with 主色调 (Primary) …
// and `提示：此配置将应用于 …模式`, 恢复 = 主题默认颜色), 常规样式 (edit_page_style_page.dart), page styles bound to pages
// (`System.pagenames`, 重命名 / delete) and 标签栏图标 (tab_icon_page.dart). Validation: `标题不能为空`, `图标不能为空`.
// [readOnly] is the 查看 mode of the theme item.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/system.dart';
import '../../data/list_store.dart';
import '../../data/theme.dart';
import '../../models/theme.dart';
import '../../theme/theme_provider.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import 'edit_page_style_page.dart';
import 'tab_icon_page.dart';
import 'theme_package.dart';

class NewThemePage extends StatefulWidget {
  final ThemeModel? theme;
  final bool isLight;
  final bool readOnly;
  const NewThemePage({super.key, this.theme, this.isLight = true, this.readOnly = false});

  @override
  State<NewThemePage> createState() => _NewThemePageState();
}

class _NewThemePageState extends State<NewThemePage> {
  late final ThemeModel t = widget.theme?.copy() ?? (ThemeModel(isLightMode: widget.isLight, version: '1.0.0')..regularStyle = PageStyle().toJson());
  late final TextEditingController _title = TextEditingController(text: t.title);
  late final TextEditingController _desc = TextEditingController(text: t.description);
  late final TextEditingController _author = TextEditingController(text: t.author);
  late final TextEditingController _contact = TextEditingController(text: t.contact);
  late ColorSchemeConfig _scheme = t.schemeConfig;
  late List<PageStyle2> _styles = t.styleList;
  late PageStyle _regular = t.regular;

  bool get ro => widget.readOnly;

  static const List<(String, String)> _roles = [
    ('seedColor', '主题默认颜色'),
    ('primary', '主色调 (Primary)'),
    ('onPrimary', '主色调文本 (OnPrimary)'),
    ('secondary', '次要强调色 (Secondary)'),
    ('onSecondary', 'OnSecondary'),
    ('primaryContainer', 'PrimaryContainer'),
    ('onPrimaryContainer', 'OnPrimaryContainer'),
    ('secondaryContainer', 'SecondaryContainer'),
    ('onSecondaryContainer', 'OnSecondaryContainer'),
    ('tertiary', 'Tertiary'),
    ('onTertiary', 'OnTertiary'),
    ('tertiaryContainer', 'TertiaryContainer'),
    ('onTertiaryContainer', 'OnTertiaryContainer'),
    ('surface', 'Surface'),
    ('onSurface', 'OnSurface'),
    ('onSurfaceVariant', 'OnSurfaceVariant'),
    ('surfaceContainerLow', 'SurfaceContainerLow'),
    ('surfaceContainerHighest', 'SurfaceContainerHighest'),
    ('outline', 'Outline'),
    ('outlineVariant', 'OutlineVariant'),
    ('error', 'Error'),
    ('onError', 'OnError'),
    ('errorContainer', 'ErrorContainer'),
    ('onErrorContainer', 'OnErrorContainer'),
    ('shadow', 'Shadow'),
    ('dialogBackground', 'DialogBackground'),
    ('popupMenuBackground', 'PopupMenuBackground'),
    ('tagBackground', 'TagBackground'),
    ('tagText', 'TagText'),
  ];

  /// page id -> display name of every page a style can be bound to (`System.pagenames`, 0x1036e20).
  Map<String, String> get _pages => System.pageTitles;

  @override
  void dispose() {
    for (final c in [_title, _desc, _author, _contact]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return Toast.show('标题不能为空', iserror: true);
    if (t.icon.isEmpty) return Toast.show('图标不能为空', iserror: true);
    t
      ..title = _title.text.trim()
      ..description = _desc.text.trim()
      ..author = _author.text.trim()
      ..contact = _contact.text.trim()
      ..colorScheme = _encodeScheme()
      ..regularStyle = _regular.toJson()
      ..styles = [for (final s in _styles) s.toJson()]
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (t.id.isEmpty) {
      t
        ..id = newId()
        ..createdAt = DateTime.now().millisecondsSinceEpoch;
    }
    await ThemeManager.install(ThemeModel.fromJson(t.normalizedJson()));
    ThemeProvider.instance.refresh();
    Toast.show('保存成功');
    Get.back();
  }

  /// 恢复默认颜色 (0x6b7b70): asks `确定要将白天/夜间主题的所有颜色恢复为默认值吗？` before the scheme goes back to the defaults.
  Future<void> _resetColors() async {
    final mode = t.isLightMode ? '白天' : '夜间';
    if (!await Dialogs.confirm(context, '恢复默认颜色', '确定要将$mode主题的所有颜色恢复为默认值吗？')) return;
    setState(() => _scheme = ColorSchemeConfig());
  }

  String _encodeScheme() {
    final j = _scheme.toJson()..removeWhere((_, v) => v == null);
    return j.isEmpty ? '' : jsonEncode(j);
  }

  Future<void> _pickIcon() async {
    final f = await DeviceIo.pickFile(image: true);
    if (f == null) return;
    final path = await ThemePackage.storeImage(f, 'themes');
    setState(() => t.icon = path);
  }

  Future<void> _pickCover() async {
    final f = await DeviceIo.pickFile(image: true);
    if (f == null) return;
    final path = await ThemePackage.storeImage(f, 'themes');
    setState(() => t.defaultCover = path);
  }

  Future<void> _pickFont(String label, String current, void Function(String) set) async {
    final names = ['未设置', ...AppFonts.all()];
    final i = await Dialogs.choose(context, '选择字体', names, selected: current.isEmpty ? 0 : names.indexOf(current));
    if (i == null) return;
    setState(() => set(i == 0 ? '' : names[i]));
  }

  Future<void> _pickRole(String key, String label) async {
    final j = _scheme.toJson();
    final c = await pickColor(context, initial: ThemeColors.of(j[key]), title: label);
    if (c == null) return;
    j[key] = c.cleared || c.color == null ? null : ThemeColors.toInt(c.color!);
    setState(() => _scheme = ColorSchemeConfig.fromJson(j));
  }

  Future<void> _editRegular() async {
    final r = await Get.to<PageStyle>(() => EditPageStylePage(style: _regular, title: '常规样式'));
    if (r != null) setState(() => _regular = r);
  }

  Future<void> _editStyle(int i) async {
    final s = _styles[i];
    final r = await Get.to<PageStyle>(() => EditPageStylePage(
        style: PageStyle(backgroundImage: s.backgroundImage, backgroundColor: s.backgroundColor, tableOpacity: s.tableOpacity, showboxShadow: s.showboxShadow),
        title: s.name));
    if (r == null) return;
    setState(() {
      s
        ..backgroundImage = r.backgroundImage
        ..backgroundColor = r.backgroundColor
        ..tableOpacity = r.tableOpacity
        ..showboxShadow = r.showboxShadow;
    });
  }

  Future<void> _bindPages(PageStyle2 s) async {
    final pages = _pages;
    final chosen = {for (final e in s.types) '$e'};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(s.name),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final e in pages.entries)
                CheckboxListTile(
                  title: Text(e.value),
                  value: chosen.contains(e.key),
                  onChanged: (v) => setS(() => v == true ? chosen.add(e.key) : chosen.remove(e.key)),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('确定'))],
        ),
      ),
    );
    setState(() => s.types = chosen.toList());
  }

  Future<void> _tabIcons() async {
    final r = await Get.to<TabIconResult>(() => TabIconPage(
          unselected: t.unselectedIcons,
          selected: t.selectedIcons,
          showTitleWhenSelected: t.showTitleWhenSelected,
          showTitleWhenUnselected: t.showTitleWhenUnselected,
          tabBarColor: t.tabBarColor,
          tabBarSelectedColor: t.tabBarSelectedColor,
        ));
    if (r == null) return;
    setState(() {
      t
        ..unselectedTabIcons = r.unselected
        ..selectedTabIcons = r.selected
        ..showTitleWhenSelected = r.showTitleWhenSelected
        ..showTitleWhenUnselected = r.showTitleWhenUnselected
        ..tabBarColor = r.tabBarColor
        ..tabBarSelectedColor = r.tabBarSelectedColor;
    });
  }

  Widget _field(TextEditingController c, String label, String hint, {int maxLines = 1, Key? key}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          key: key,
          controller: c,
          readOnly: ro,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  Widget _swatch(Object? v) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: ThemeColors.of(v), shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.outline)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mode = t.isLightMode ? '白天' : '夜间';
    final schemeJson = _scheme.toJson();
    final icon = ThemeFiles.image(t.icon);
    final cover = ThemeFiles.image(t.defaultCover);
    return Scaffold(
      appBar: AppBar(
        title: Text(ro ? (t.title.isEmpty ? '主题' : t.title) : (widget.theme == null ? '创建主题' : '编辑')),
        actions: [if (!ro) TextButton(key: const Key('theme_save'), onPressed: _save, child: const Text('保存'))],
      ),
      body: AbsorbPointer(
        absorbing: ro,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          SectionCard(title: '常规', children: [
            _field(_title, '标题', '请输入标题', key: const Key('theme_title')),
            _field(_desc, '简介', '请输入简介', maxLines: 2),
            _field(_author, '作者', '请输入作者'),
            _field(_contact, '联系', '请输入联系'),
            ListTile(
              title: const Text('图标'),
              trailing: icon == null ? const Text('未设置') : Image(image: icon, width: 36, height: 36, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
              onTap: _pickIcon,
            ),
            ListTile(
              title: const Text('模式'),
              trailing: SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('白天')), ButtonSegment(value: false, label: Text('夜间'))],
                selected: {t.isLightMode},
                onSelectionChanged: (v) => setState(() => t.isLightMode = v.first),
              ),
            ),
          ]),
          SectionCard(title: '字体', children: [
            ListTile(title: const Text('导航字体'), trailing: Text(t.navFont.isEmpty ? '未设置' : t.navFont), onTap: () => _pickFont('导航字体', t.navFont, (v) => t.navFont = v)),
            ListTile(title: const Text('标题字体'), trailing: Text(t.titleFont.isEmpty ? '未设置' : t.titleFont), onTap: () => _pickFont('标题字体', t.titleFont, (v) => t.titleFont = v)),
            ListTile(title: const Text('常规字体'), trailing: Text(t.regularFont.isEmpty ? '未设置' : t.regularFont), onTap: () => _pickFont('常规字体', t.regularFont, (v) => t.regularFont = v)),
          ]),
          SectionCard(title: '封面', children: [
            ListTile(
              title: const Text('默认封面'),
              trailing: cover == null ? const Text('未设置') : Image(image: cover, width: 30, height: 42, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
              onTap: _pickCover,
              onLongPress: () => setState(() => t.defaultCover = ''),
            ),
            ListTile(
              title: const Text('封面应用范围'),
              trailing: SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('全部')), ButtonSegment(value: false, label: Text('仅加载失败'))],
                selected: {t.useDefaultCoverForAll},
                onSelectionChanged: (v) => setState(() => t.useDefaultCoverForAll = v.first),
              ),
            ),
          ]),
          SectionCard(title: t.isLightMode ? '浅色主题配色方案' : '深色主题配色方案', children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('提示：此配置将应用于 $mode模式', style: TextStyle(fontSize: 12, color: cs.outline)),
            ),
            ListTile(title: const Text('基础文本颜色'), trailing: _swatch(t.textColor), onTap: () async {
              final c = await pickColor(context, initial: ThemeColors.of(t.textColor), title: '基础文本颜色');
              if (c != null) setState(() => t.textColor = c.cleared || c.color == null ? 0 : ThemeColors.toInt(c.color!));
            }),
            ExpansionTile(title: const Text('主要颜色'), children: [
              for (final r in _roles) ListTile(dense: true, title: Text(r.$2), trailing: _swatch(schemeJson[r.$1]), onTap: () => _pickRole(r.$1, r.$2)),
              TextButton(onPressed: _resetColors, child: const Text('恢复默认颜色')),
            ]),
          ]),
          SectionCard(title: '页面样式', children: [
            ListTile(title: const Text('常规样式'), trailing: const Icon(Icons.chevron_right), onTap: _editRegular),
            for (var i = 0; i < _styles.length; i++)
              ListTile(
                title: Text(_styles[i].name.isEmpty ? '样式 ${i + 1}' : _styles[i].name),
                subtitle: Text(_styles[i].types.isEmpty
                    ? '未绑定页面'
                    : _styles[i].types.map((e) => _pages['$e'] ?? '$e').join('、')),
                onTap: () => _editStyle(i),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'bind') return _bindPages(_styles[i]);
                    if (v == 'rename') {
                      final name = await Dialogs.input(context, '重命名', initial: _styles[i].name);
                      if (name != null && name.trim().isNotEmpty) setState(() => _styles[i].name = name.trim());
                    }
                    if (v == 'delete') setState(() => _styles = [..._styles]..removeAt(i));
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'bind', child: Text('绑定页面')),
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _styles = [..._styles, PageStyle2(name: '样式 ${_styles.length + 1}')]),
              icon: const Icon(Icons.add),
              label: const Text('新增'),
            ),
          ]),
          SectionCard(title: '图标', children: [
            ListTile(title: const Text('标签栏图标'), trailing: const Icon(Icons.chevron_right), onTap: _tabIcons),
          ]),
        ]),
      ),
    );
  }
}
