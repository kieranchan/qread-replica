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

/// The colour roles grouped and named as the original editor (0x6b324c); `seedColor` (主题默认颜色) stands above the groups.
const List<(String, List<(String, String)>)> themeColorGroups = [
  ('主要颜色', [
    ('primary', '主色调 (Primary)'),
    ('onPrimary', '主色调文本 (OnPrimary)'),
    ('secondary', '次要强调色 (Secondary)'),
    ('onSecondary', '次要强调色文本 (OnSecondary)'),
    ('secondaryContainer', '次要容器 (SecondaryContainer)'),
    ('onSecondaryContainer', '次要容器文本 (OnSecondaryContainer)'),
  ]),
  ('表面和容器颜色', [
    ('surface', '表面颜色 (Surface)'),
    ('onSurface', '表面文本 (OnSurface)'),
    ('onSurfaceVariant', '变体表面文本 (OnSurfaceVariant)'),
    ('surfaceContainerLow', '低层级容器 (SurfaceContainerLow)'),
    ('surfaceContainerHighest', '最高层级容器 (SurfaceContainerHighest)'),
    ('primaryContainer', '主容器 (PrimaryContainer)'),
    ('onPrimaryContainer', '主容器文本 (OnPrimaryContainer)'),
  ]),
  ('边框和轮廓', [
    ('outline', '边框 (Outline)'),
    ('outlineVariant', '变体边框 (OutlineVariant)'),
  ]),
  ('功能颜色', [
    ('error', '错误颜色 (Error)'),
    ('errorContainer', '错误容器 (ErrorContainer)'),
    ('onError', '错误文本 (OnError)'),
    ('onErrorContainer', '错误容器文本 (OnErrorContainer)'),
    ('shadow', '阴影颜色 (Shadow)'),
  ]),
  ('弹窗和菜单背景', [
    ('dialogBackground', '对话框背景 (Dialog)'),
    ('popupMenuBackground', '弹出菜单背景 (PopupMenu)'),
  ]),
  ('详情页标签和按钮颜色', [
    ('tagBackground', '标签背景 (TagBackground)'),
    ('tagText', '标签文字 (TagText)'),
  ]),
  ('补充颜色（可选）', [
    ('tertiary', '第三色调 (Tertiary)'),
    ('onTertiary', '第三色调文本 (OnTertiary)'),
    ('tertiaryContainer', '第三色调容器 (TertiaryContainer)'),
    ('onTertiaryContainer', '第三色调容器文本 (OnTertiaryContainer)'),
  ]),
];

const (String, String) themeSeedRole = ('seedColor', '主题默认颜色');

/// Every role, flat (seed first).
List<(String, String)> get themeColorRoles => [themeSeedRole, for (final g in themeColorGroups) ...g.$2];

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

  /// 0x6b9dc0: `已绑定: …` / `未绑定页面 · 透明度 x · 阴影开`.
  String _styleSummary(PageStyle2 s) {
    final pages = s.types.isEmpty ? '未绑定页面' : '已绑定: ${s.types.map((e) => _pages['$e'] ?? '$e').join('、')}';
    return '$pages · 透明度 ${s.tableOpacity}${s.showboxShadow ? ' · 阴影开' : ''}';
  }

  /// 0x6be614: the page picker (`选择要绑定的页面（可多选）`) with its search box (`搜索页面…`, `无匹配页面`); null when cancelled.
  Future<Set<String>?> _choosePages(String title, Set<String> initial) async {
    final pages = _pages;
    final chosen = {...initial};
    var query = '';
    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final hits = pages.entries.where((e) => query.isEmpty || e.value.contains(query) || e.key.contains(query)).toList();
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Align(alignment: Alignment.centerLeft, child: Text('选择要绑定的页面（可多选）', style: TextStyle(fontSize: 12))),
                TextField(
                  key: const Key('style_page_search'),
                  decoration: const InputDecoration(hintText: '搜索页面…', prefixIcon: Icon(Icons.search), isDense: true),
                  onChanged: (v) => setS(() => query = v.trim()),
                ),
                Flexible(
                  child: hits.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('无匹配页面'))
                      : ListView(shrinkWrap: true, children: [
                          for (final e in hits)
                            CheckboxListTile(
                              dense: true,
                              title: Text(e.value),
                              value: chosen.contains(e.key),
                              onChanged: (v) => setS(() => v == true ? chosen.add(e.key) : chosen.remove(e.key)),
                            ),
                        ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
              TextButton(key: const Key('style_pages_ok'), onPressed: () => Navigator.of(ctx).pop(chosen), child: const Text('确定')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _bindPages(PageStyle2 s) async {
    final r = await _choosePages(s.name.isEmpty ? '绑定页面' : s.name, {for (final e in s.types) '$e'});
    if (r == null) return;
    setState(() => s.types = r.toList());
  }

  /// 添加页面样式 (0x6be614): a new style bound to the chosen pages.
  Future<void> _addStyle() async {
    final r = await _choosePages('添加页面样式', {});
    if (r == null) return;
    setState(() => _styles = [..._styles, PageStyle2(name: '样式 #${_styles.length + 1}', types: r.toList())]);
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
            ListTile(title: Text(themeSeedRole.$2), trailing: _swatch(schemeJson[themeSeedRole.$1]), onTap: () => _pickRole(themeSeedRole.$1, themeSeedRole.$2)),
            for (final g in themeColorGroups)
              ExpansionTile(title: Text(g.$1), children: [
                for (final r in g.$2) ListTile(dense: true, title: Text(r.$2), trailing: _swatch(schemeJson[r.$1]), onTap: () => _pickRole(r.$1, r.$2)),
              ]),
            TextButton(onPressed: _resetColors, child: const Text('恢复默认颜色')),
          ]),
          SectionCard(title: '页面样式设置', children: [
            ListTile(title: const Text('常规样式'), subtitle: const Text('已设置'), trailing: const Icon(Icons.chevron_right), onTap: _editRegular),
            ListTile(
              title: const Text('自定义页面样式'),
              trailing: ro ? null : TextButton.icon(onPressed: _addStyle, icon: const Icon(Icons.add), label: const Text('添加')),
            ),
            if (_styles.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('暂无自定义样式，点击右上角添加', style: TextStyle(fontSize: 12, color: cs.outline)),
              ),
            for (var i = 0; i < _styles.length; i++)
              ListTile(
                title: Text(_styles[i].name.isEmpty ? '样式 #${i + 1}' : _styles[i].name),
                subtitle: Text(_styleSummary(_styles[i])),
                onTap: () => _editStyle(i),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') return _editStyle(i);
                    if (v == 'bind') return _bindPages(_styles[i]);
                    if (v == 'rename') {
                      final name = await Dialogs.input(context, '重命名样式', hint: '请输入样式名称', initial: _styles[i].name);
                      if (name != null && name.trim().isNotEmpty) setState(() => _styles[i].name = name.trim());
                    }
                    if (v == 'delete') setState(() => _styles = [..._styles]..removeAt(i));
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑样式内容')),
                    PopupMenuItem(value: 'bind', child: Text('绑定页面')),
                    PopupMenuItem(value: 'rename', child: Text('重命名样式')),
                    PopupMenuItem(value: 'delete', child: Text('删除样式')),
                  ],
                ),
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
