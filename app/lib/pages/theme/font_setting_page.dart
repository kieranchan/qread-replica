// pages/theme/font_setting_page.dart — 主题设置 (`FontSettingPage`, 67 functions; opened by 「我的」 → 主题管理, 0xf64758). Card
// 主题设置 with 日间模式 / 夜间模式 (the applied theme or `未选择`, tap → theme manager on that tab, `可在主题管理器中选择`) (0x8176c0),
// 精选推荐 (主题广场 `海量精美主题`, 图标广场 `个性图标随心选`), 字体 (导航字体 / 标题字体 / 常规字体: 跟随主题 or 自定义 =
// 默认字体 / 谷歌汉字 / 阿里黑体 / 阿里圆体 / imported fonts) and 封面 (默认封面 跟随主题 / 自定义 `已设置 n 张`, 封面应用范围
// 全部 / 仅加载失败, `注：默认封面仅在导入书本未设置封面时生效`). Errors loading the settings: `加载字体设置失败: …`.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/fonts.dart';
import '../../data/theme.dart';
import '../../theme/theme_provider.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import 'icon_plaza_page.dart';
import 'theme_manager_page.dart';
import 'theme_package.dart';
import 'theme_plaza_page.dart';

class FontSettingPage extends StatefulWidget {
  const FontSettingPage({super.key});

  @override
  State<FontSettingPage> createState() => _FontSettingPageState();
}

class _FontSettingPageState extends State<FontSettingPage> {
  final ThemeProvider tp = ThemeProvider.instance;

  @override
  void initState() {
    super.initState();
    Future.wait([ThemeManager.load(), FontsData.load()]).then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      Toast.show('加载字体设置失败: $e', iserror: true);
    });
  }

  Future<void> _font(String key, String label) async {
    final names = ['跟随主题', ...AppFonts.all()];
    final own = tp.ownFont(key);
    final i = await Dialogs.choose(context, label, names, selected: own.isEmpty ? 0 : names.indexOf(own));
    if (i == null) return;
    await tp.setOwnFont(key, i == 0 ? '' : names[i]);
    Toast.show('已应用当前主题设置');
    setState(() {});
  }

  Future<void> _covers() async {
    final own = tp.ownCovers;
    final i = await Dialogs.choose(context, '默认封面', ['跟随主题', '自定义（添加一张）', if (own.isNotEmpty) '清除自定义封面']);
    if (i == null) return;
    if (i == 0 || i == 2) {
      await tp.setOwnCovers([]);
    } else {
      final f = await DeviceIo.pickFile(image: true);
      if (f == null) return;
      await tp.setOwnCovers([...own, await ThemePackage.storeImage(f, 'covers')]);
    }
    setState(() {});
  }

  Widget _modeTile(bool light) {
    final t = light ? tp.dayTheme : tp.nightTheme;
    return Expanded(
      child: InkWell(
        key: Key(light ? 'fs_day' : 'fs_night'),
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Get.to(() => ThemeManagerPage(isLight: light));
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Icon(light ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            const SizedBox(height: 6),
            Text(light ? '日间模式' : '夜间模式', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(t?.title ?? '未选择', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      ),
    );
  }

  Widget _feature(IconData icon, String title, String sub, VoidCallback onTap, Key key) => Expanded(
        child: Card(
          child: InkWell(
            key: key,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(sub, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  String _fontLabel(String key) {
    final own = tp.ownFont(key);
    if (own.isNotEmpty) return own;
    final t = tp.current;
    final themed = switch (key) {
      ThemeProvider.navFontKey => t?.navFont ?? '',
      ThemeProvider.titleFontKey => t?.titleFont ?? '',
      _ => t?.regularFont ?? '',
    };
    return '跟随主题：${themed.isEmpty ? AppFonts.defaultName : themed}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: tp,
      builder: (context, _) => StyledScaffold(
        page: 'fontsetting',
        appBar: AppBar(title: const Text('主题设置')),
        body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          SectionCard(page: 'fontsetting', title: '主题设置', children: [
            Row(children: [_modeTile(true), _modeTile(false)]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text('可在主题管理器中选择', style: TextStyle(fontSize: 12, color: cs.outline)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text('精选推荐', style: Theme.of(context).textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              _feature(Icons.storefront_outlined, '主题广场', '海量精美主题', () => Get.to(() => const ThemePlazaPage()), const Key('fs_plaza')),
              _feature(Icons.apps_outlined, '图标广场', '个性图标随心选', () => Get.to(() => const IconPlazaPage()), const Key('fs_icons')),
            ]),
          ),
          SectionCard(page: 'fontsetting', title: '字体', children: [
            ListTile(title: const Text('导航字体'), subtitle: Text(_fontLabel(ThemeProvider.navFontKey)), trailing: const Text('选择'), onTap: () => _font(ThemeProvider.navFontKey, '导航字体')),
            ListTile(title: const Text('标题字体'), subtitle: Text(_fontLabel(ThemeProvider.titleFontKey)), trailing: const Text('选择'), onTap: () => _font(ThemeProvider.titleFontKey, '标题字体')),
            ListTile(title: const Text('常规字体'), subtitle: Text(_fontLabel(ThemeProvider.regularFontKey)), trailing: const Text('选择'), onTap: () => _font(ThemeProvider.regularFontKey, '常规字体')),
          ]),
          SectionCard(page: 'fontsetting', title: '封面', children: [
            ListTile(
              title: const Text('默认封面'),
              subtitle: Text(tp.ownCovers.isEmpty ? '跟随主题' : '自定义'),
              trailing: Text(tp.ownCovers.isEmpty ? (tp.current?.defaultCover.isNotEmpty == true ? '跟随' : '暂无封面') : '已设置 ${tp.ownCovers.length} 张'),
              onTap: _covers,
            ),
            ListTile(
              title: const Text('封面应用范围'),
              trailing: SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('全部')), ButtonSegment(value: false, label: Text('仅加载失败'))],
                selected: {tp.useDefaultCoverForAll},
                onSelectionChanged: (v) => tp.setUseDefaultCoverForAll(v.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('注：默认封面仅在导入书本未设置封面时生效', style: TextStyle(fontSize: 12, color: cs.outline)),
            ),
          ]),
        ]),
      ),
    );
  }
}
