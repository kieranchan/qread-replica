// pages/theme/theme_manager_page.dart — 主题管理 (`ThemeManagerPage`, state 0x627dc8): two tabs 白天 / 夜间 with the installed themes
// of each mode (`ThemeItemWidget` grid), actions 导入主题 (0xff5eb8: `.qtheme` / `.zip`, see theme_package.dart) and 创建主题
// (new_theme_page.dart). Both actions are member-only (`主题为会员功能！`). An empty tab shows `暂无` + the mode.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/theme.dart';
import '../../theme/theme_provider.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';
import 'new_theme_page.dart';
import 'theme_item_widget.dart';
import 'theme_package.dart';

class ThemeManagerPage extends StatefulWidget {
  /// Tab opened first (true = 白天).
  final bool isLight;
  const ThemeManagerPage({super.key, this.isLight = true});

  @override
  State<ThemeManagerPage> createState() => _ThemeManagerPageState();
}

class _ThemeManagerPageState extends State<ThemeManagerPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.isLight ? 0 : 1);

  @override
  void initState() {
    super.initState();
    ThemeManager.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _light => _tabs.index == 0;

  Future<void> _import() async {
    if (!Vip.require('主题为会员功能！')) return;
    final f = await DeviceIo.pickFile(extensions: ThemePackage.extensions);
    if (f == null) return;
    try {
      await ThemePackage.importFile(f, expectLight: _light);
      Toast.show('主题导入成功');
    } on ThemePackageException catch (e) {
      Toast.show(e.message, iserror: true);
    } catch (e) {
      Toast.show('导入主题失败: $e', iserror: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    if (!Vip.require('主题为会员功能！')) return;
    await Get.to(() => NewThemePage(isLight: _light));
    if (mounted) setState(() {});
  }

  Widget _grid(bool light) {
    final list = ThemeManager.themes.where((t) => t.isLightMode == light).toList();
    if (list.isEmpty) {
      return Center(child: Text('暂无${light ? '白天' : '夜间'}主题', style: TextStyle(color: Theme.of(context).colorScheme.outline)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, childAspectRatio: 0.66, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: list.length,
      itemBuilder: (_, i) => ThemeItemWidget(key: ValueKey(list[i].id), theme: list[i], onChanged: () => setState(() {})),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeProvider.instance,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('主题管理'),
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: '白天'), Tab(text: '夜间')]),
          actions: [
            IconButton(key: const Key('theme_import'), tooltip: '导入主题', icon: const Icon(Icons.file_download_outlined), onPressed: _import),
            IconButton(key: const Key('theme_create'), tooltip: '创建主题', icon: const Icon(Icons.add), onPressed: _create),
          ],
        ),
        body: TabBarView(controller: _tabs, children: [_grid(true), _grid(false)]),
      ),
    );
  }
}
