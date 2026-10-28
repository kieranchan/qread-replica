// pages/theme/theme_item_widget.dart — one installed theme in the theme manager (`ThemeItemWidget`, state 0x6cdcb0 build): preview,
// title / author, 使用中 badge and the actions 应用 / 取消应用 / 查看 / 编辑 / 拷贝 (副本) / 导出 / 删除. Applying, editing,
// copying and exporting are member-only (`主题为会员功能！`); deleting asks `确定要删除主题 "x" 吗？`.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/list_store.dart';
import '../../data/theme.dart';
import '../../models/theme.dart';
import '../../theme/theme_provider.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';
import 'new_theme_page.dart';
import 'theme_package.dart';

class ThemeItemWidget extends StatefulWidget {
  final ThemeModel theme;
  final VoidCallback? onChanged;
  const ThemeItemWidget({super.key, required this.theme, this.onChanged});

  @override
  State<ThemeItemWidget> createState() => _ThemeItemWidgetState();
}

class _ThemeItemWidgetState extends State<ThemeItemWidget> {
  ThemeModel get t => widget.theme;

  static const String _vipText = '主题为会员功能！';

  Future<void> _toggleApply() async {
    final tp = ThemeProvider.instance;
    try {
      if (tp.isApplied(t)) {
        await tp.cancelTheme(t.isLightMode);
        Toast.show('取消应用主题：${t.title}');
      } else {
        if (!Vip.require(_vipText)) return;
        await tp.applyTheme(t);
        Toast.show('应用主题：${t.title}');
      }
      widget.onChanged?.call();
    } catch (e) {
      Toast.show('操作失败:$e', iserror: true);
    }
  }

  Future<void> _edit({bool view = false}) async {
    if (!view && !Vip.require(_vipText)) return;
    await Get.to(() => NewThemePage(theme: t, isLight: t.isLightMode, readOnly: view));
    ThemeProvider.instance.refresh();
    widget.onChanged?.call();
  }

  Future<void> _copy() async {
    if (!Vip.require(_vipText)) return;
    final c = t.copy()
      ..id = newId()
      ..title = '${t.title} 副本';
    await ThemeManager.install(c);
    widget.onChanged?.call();
  }

  Future<void> _export() async {
    if (!Vip.require(_vipText)) return;
    try {
      final f = await ThemePackage.exportFile(t);
      await DeviceIo.shareFile(f, text: t.title);
    } catch (e) {
      Toast.show('操作失败:$e', iserror: true);
    }
  }

  Future<void> _delete() async {
    if (!await Dialogs.confirm(context, '删除主题', '确定要删除主题 "${t.title}" 吗？', danger: true)) return;
    final tp = ThemeProvider.instance;
    if (tp.isApplied(t)) await tp.cancelTheme(t.isLightMode);
    await ThemeManager.remove(t.id);
    Toast.show('主题已删除');
    tp.refresh();
    widget.onChanged?.call();
  }

  Widget _action(String label, String id, Future<void> Function() run, {Color? color}) => InkWell(
        key: Key('theme_${id}_${t.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: run,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(label, style: TextStyle(fontSize: 12, color: color ?? Theme.of(context).colorScheme.primary)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final applied = ThemeProvider.instance.isApplied(t);
    final scheme = ThemeColors.scheme(t.schemeConfig, t.isLightMode ? Brightness.light : Brightness.dark);
    final bg = ThemeFiles.image(t.regular.backgroundImage);
    final icon = ThemeFiles.image(t.icon);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(view: true),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: ThemeColors.of(t.regular.backgroundColor) ?? scheme.surface,
                image: bg == null ? null : DecorationImage(image: bg, fit: BoxFit.cover),
              ),
              child: Stack(children: [
                Center(
                  child: icon != null
                      ? Image(image: icon, width: 48, height: 48, errorBuilder: (_, _, _) => const Icon(Icons.palette_outlined))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          for (final c in [scheme.primary, scheme.secondary, scheme.tertiary])
                            Container(width: 18, height: 18, margin: const EdgeInsets.all(3), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                        ]),
                ),
                if (applied)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(8)),
                      child: Text('使用中', style: TextStyle(color: cs.onPrimary, fontSize: 11)),
                    ),
                  ),
              ]),
            ),
          ),
          // as the original card (0x6cdcb0): title / author, a visible 应用 / 取消应用 button (取消应用 returns to the default theme),
          // then the row 编辑 · 导出 · 查看 · 拷贝 · 删除
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title.isEmpty ? '主题' : t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(t.author.isEmpty ? '匿名' : t.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.outline)),
                ]),
              ),
              GestureDetector(
                key: Key('theme_apply_${t.id}'),
                onTap: _toggleApply,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: applied ? cs.surfaceContainerHighest : cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(applied ? '取消应用' : '应用', style: TextStyle(fontSize: 12, color: applied ? cs.onSurface : cs.onPrimary)),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _action('编辑', 'edit', _edit),
              _action('导出', 'export', _export),
              _action('查看', 'view', () => _edit(view: true)),
              _action('拷贝', 'copy', _copy),
              _action('删除', 'delete', _delete, color: Colors.red),
            ]),
          ),
        ]),
      ),
    );
  }
}
