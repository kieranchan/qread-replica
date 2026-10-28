// pages/setting/read_setting_page.dart — "阅读设置" of the settings tab (original `_ReadSettingPageState`, build 0x7fe684). Sections,
// titles and help lines are the original's, each item writes the key its closure writes (settings_keys.tsv):
//   书架设置: 书架排序 · 未读章节 (完整显示 / 不显示 / 缩略显示) · 列表缩放 / 宫格缩放 (50-200%) · 列表列数 / 宫格列数 (0 自适应) · 缩放影响
//     (`scaleEffect` 全部 / 仅书本列表) · 文字详情 (`textDetail` 正常 / 简略) · 显示类型 · 封面阴影 · 打开动画 · 宫格卡片 · 继续阅读;
//   阅读设置: 朗读缓存 (`listemcachenum`) · 朗读优化 (`readyouhua`, " ms", 0 = 关闭) · 默认引擎 (`ttsEngine`) · 引擎一致 · 替换净化 ·
//     延迟加载 · 朗读净化 · 净化正则 · 计算图片 · 朗读按钮 (`readbt`) · 添加提醒;
//   阅读统计: 全局统计 (`globalReadRecord`) · 单本统计 (`perBookReadRecord`) · 历史记录;
//   界面设置: 底栏图标 (the 底栏标签配置 sheet, 0x80773c / 0x8079e4 / 0x808a7c / 0x8088d0) · 字体大小 (`globalFontScale` 0.8-1.5) · 最近阅读 ·
//     每日目标 · 沉浸光感 (`ImmersiveLight`, 弱 / 均衡 / 强);
//   缓存设置: 图片缓存 (`maxImageCacheSize`, 100-5000MB); 备份设置: 自动备份 (`autoBackupNum`, 1-30个); AI模型: AI模型配置;
//   其他设置: 底栏隐藏 (`bottomBarHideMode` 0 默认 / 1 底栏消失不显示按钮 / 2 底栏始终显示, 0x803660) · 侧边导航 · 原生底栏 (`bottomBarType`).
import 'package:flutter/material.dart';

import '../../common/immersive_light.dart';
import '../../common/nav.dart';
import '../../data/tts.dart';
import '../../storage/storage.dart';
import '../../util/toast.dart';
import '../../widget/book/shelf_prefs.dart';
import '../main_page.dart';

class ReadSettingPage extends StatefulWidget {
  const ReadSettingPage({super.key});

  @override
  State<ReadSettingPage> createState() => _ReadSettingPageState();
}

class _ReadSettingPageState extends State<ReadSettingPage> {
  bool _b(String key, bool def) => Storage.getString(key).isEmpty ? def : Storage.getBool(key, def);
  int _i(String key, int def) => Storage.getString(key).isEmpty ? def : Storage.getInt(key, def);

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Text(title, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(12),
            child: Column(children: children),
          ),
        ]),
      );

  Widget _switch(String title, String key, bool def, String help) => SwitchListTile(
        title: Text(title),
        subtitle: Text(help, style: const TextStyle(fontSize: 12)),
        value: _b(key, def),
        onChanged: (v) async {
          await Storage.setBool(key, v);
          setState(() {});
        },
      );

  Widget _choice(String title, String key, int def, Map<int, String> options, String help, {VoidCallback? after}) {
    final v = _i(key, def);
    return ListTile(
      title: Text(title),
      subtitle: Text(help, style: const TextStyle(fontSize: 12)),
      trailing: DropdownButton<int>(
        value: options.containsKey(v) ? v : options.keys.first,
        underline: const SizedBox(),
        items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (x) async {
          if (x == null) return;
          await Storage.setInt(key, x);
          after?.call();
          setState(() {});
        },
      ),
    );
  }

  /// A number typed in a dialog, checked against [min]..[max] with the original's messages.
  Widget _number(String title, String key, int def,
      {required int min, required int max, required String hint, required String help, String unit = '', String Function(int v)? show}) {
    final v = _i(key, def);
    return ListTile(
      title: Text(title),
      subtitle: Text(help, style: const TextStyle(fontSize: 12)),
      trailing: Text(show?.call(v) ?? '$v$unit'),
      onTap: () async {
        final c = TextEditingController(text: '$v');
        final r = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: hint, helperText: help)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('确认')),
            ],
          ),
        );
        if (r == null) return;
        final n = int.tryParse(r);
        if (n == null) return Toast.show('请输入有效的数字');
        if (n < min || n > max) return Toast.show('请输入$min-$max之间的数字');
        await Storage.setInt(key, n);
        setState(() {});
      },
    );
  }

  Future<void> _regex() async {
    const def = r'[^\w一-龥]';
    final c = TextEditingController(text: Storage.getString('readPurificationRegex', def));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('净化正则'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('朗读净化时使用的正则表达式，匹配到的字符将被移除'),
          TextField(controller: c),
          const SizedBox(height: 4),
          const Text(r'默认值：[^\w一-龥]', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('确定')),
        ],
      ),
    );
    if (r == null) return;
    try {
      RegExp(r);
    } catch (e) {
      return Toast.show('$e');
    }
    await Storage.setString('readPurificationRegex', r);
    setState(() {});
  }

  Future<void> _engine() async {
    try {
      await TTSData.load();
    } catch (_) {}
    if (!mounted) return;
    final engines = [TTSData.defaultEngine, ...TTSData.engines];
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('默认引擎'),
        children: [for (final e in engines) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.id), child: Text(e.name))],
      ),
    );
    if (r == null) return;
    await Storage.setString('ttsEngine', r == TTSData.defaultEngine.id ? '' : r);
    setState(() {});
  }

  String get _engineName {
    final id = Storage.getString('ttsEngine');
    if (id.isEmpty) return '系统默认';
    return TTSData.byId(id)?.name ?? '系统默认';
  }

  /// 设置字体大小 (0x806978): a slider 0.8 .. 1.5 in 14 steps, "标准" at 100%.
  Future<void> _fontScale() async {
    var v = Storage.getDouble('globalFontScale', 1).clamp(0.8, 1.5);
    final r = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                const Expanded(child: Text('设置字体大小', textAlign: TextAlign.center, style: TextStyle(fontSize: 18))),
                TextButton(onPressed: () => Navigator.pop(ctx, v), child: const Text('完成')),
              ]),
              const Text('拖动下面的滑块，可设置字体大小'),
              const Text('设置后，会改变界面中的字体大小', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              Row(children: [
                const Text('A', style: TextStyle(fontSize: 12)),
                Expanded(child: Slider(value: v, min: 0.8, max: 1.5, divisions: 14, onChanged: (x) => set(() => v = x))),
                const Text('A', style: TextStyle(fontSize: 20)),
              ]),
              Text((v - 1).abs() < 0.001 ? '标准' : '${(v * 100).round()}%'),
            ]),
          ),
        ),
      ),
    );
    if (r == null) return;
    await Storage.setDouble('globalFontScale', double.parse(r.toStringAsFixed(2)));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final light = ImmersiveLight.level.value;
    final readyouhua = _i('readyouhua', 0);
    return Scaffold(
      appBar: AppBar(title: const Text('阅读设置'), centerTitle: true),
      body: ListView(children: [
        _section('书架设置', [
          _choice('书架排序', ShelfPrefs.sortKey, 0, ShelfPrefs.sortModes, '首页书架书本的排列顺序'),
          _choice('未读章节', ShelfPrefs.unreadKey, ShelfPrefs.unreadDot,
              const {ShelfPrefs.unreadFull: '完整显示', ShelfPrefs.unreadHidden: '不显示', ShelfPrefs.unreadDot: '缩略显示'}, '书架页是否显示未读章节红点'),
          _number('列表缩放', ShelfPrefs.listScaleKey, 100, min: 50, max: 200, hint: '请输入缩放比例', help: '调整书架为列表时书本的显示大小，范围50-200%', unit: '%'),
          _number('宫格缩放', ShelfPrefs.gridScaleKey, 100, min: 50, max: 200, hint: '请输入缩放比例', help: '调整书架宫格时书本的显示大小，范围50-200%', unit: '%'),
          _number('列表列数', ShelfPrefs.listColumnsKey, 0, min: 0, max: 10, hint: '0为自适应', help: '书架为列表显示时每行个数，0为自适应', show: (v) => v == 0 ? '自适应' : '$v'),
          _number('宫格列数', ShelfPrefs.gridColumnsKey, 0, min: 0, max: 10, hint: '0为自适应', help: '书架为宫格显示时每行个数，0为自适应', show: (v) => v == 0 ? '自适应' : '$v'),
          _choice('缩放影响', 'scaleEffect', 0, const {0: '全部', 1: '仅书本列表'}, '书架缩放的影响范围'),
          _choice('文字详情', 'textDetail', 0, const {0: '正常', 1: '简略'}, '书架显示的文字详细程度'),
          _switch('显示类型', ShelfPrefs.showTypeKey, true, '是否在封面显示书本类型'),
          _switch('封面阴影', ShelfPrefs.coverShadowKey, true, '是否在宫格列表显示封面阴影效果'),
          _switch('打开动画', 'openBookAnimation', true, '从书架打开书本时播放翻书动画'),
          _switch('宫格卡片', ShelfPrefs.gridCardKey, false, '宫格模式下使用卡片样式显示书本'),
          _switch('继续阅读', 'continueRead', false, '启动时打开上次阅读的书本，重新打开应用生效'),
        ]),
        _section('阅读设置', [
          _number('朗读缓存', 'listemcachenum', 15, min: 1, max: 50, hint: '输入数值', help: '使用朗读引擎时，预先缓存多少段'),
          _number('朗读优化', 'readyouhua', 0,
              min: 0, max: 5000, hint: '请输入毫秒数', help: '在剩余时间还剩指定毫秒时直接播报下一个, 设为0关闭, 对直接播报的系统引擎无效', show: (_) => readyouhua == 0 ? '关闭' : '$readyouhua ms'),
          ListTile(title: const Text('默认引擎'), subtitle: const Text('朗读时的默认引擎', style: TextStyle(fontSize: 12)), trailing: Text(_engineName), onTap: _engine),
          _switch('引擎一致', 'useGlobalTtsEngine', true, '是否所有书本使用一个朗读引擎'),
          _switch('替换净化', 'useReplaceRule', false, '是否默认开启替换净化，已在书架的需要手动调整'),
          _switch('延迟加载', 'lazyLoad', false, '阅读时是否等动画结束时再加载书本，进入动画卡顿时可以打开'),
          _switch('朗读净化', 'readPurification', false, '朗读时是否净化符号空格'),
          ListTile(
            title: const Text('净化正则'),
            subtitle: Text(Storage.getString('readPurificationRegex', r'[^\w一-龥]'), style: const TextStyle(fontSize: 12)),
            onTap: _regex,
          ),
          _switch('计算图片', 'calcImage', true, '小说阅读器分页时是否先计算图片再分页，如果一个图片一页请打开这个。'),
          _switch('朗读按钮', 'readbt', false, '打开后朗读控制中心按钮将会变成上一段下一段'),
          _switch('添加提醒', 'showAddToBookshelfReminder', true, '退出阅读页时如果书本未加入书架会提醒'),
        ]),
        _section('阅读统计', [
          _switch('全局统计', 'globalReadRecord', true, '是否记录阅读时间，关闭后不记录每日阅读时间'),
          _switch('单本统计', 'perBookReadRecord', true, '是否记录每本书的阅读时间，关闭后不再记录阅读时间'),
          _switch('历史记录', 'historyRecord', true, '是否保存阅读历史记录，关闭后不再记录阅读历史'),
        ]),
        _section('界面设置', [
          ListTile(title: const Text('底栏图标'), trailing: const Icon(Icons.chevron_right), onTap: () => showTabEditor(context)),
          ListTile(
            title: const Text('字体大小'),
            subtitle: const Text('在系统字体大小基础上进行缩放', style: TextStyle(fontSize: 12)),
            trailing: Text('${(Storage.getDouble('globalFontScale', 1) * 100).round()}%'),
            onTap: _fontScale,
          ),
          _switch('最近阅读', 'showRecentRead', true, '是否在界面上显示最近阅读的内容'),
          _switch('每日目标', 'showDailyGoal', true, '是否显示每日阅读目标'),
          ListTile(
            title: const Text('沉浸光感'),
            subtitle: const Text('沉浸光感特效强度，如果卡顿请选择弱', style: TextStyle(fontSize: 12)),
            trailing: DropdownButton<int>(
              key: const ValueKey('immersive_light'),
              value: light,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: ImmersiveLight.off, child: Text('弱')),
                DropdownMenuItem(value: ImmersiveLight.balanced, child: Text('均衡')),
                DropdownMenuItem(value: ImmersiveLight.strong, child: Text('强')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await ImmersiveLight.set(v);
                setState(() {});
              },
            ),
          ),
        ]),
        _section('缓存设置', [
          _number('图片缓存', 'maxImageCacheSize', 1000, min: 100, max: 5000, hint: '请输入图片缓存的最大大小（单位：MB）', help: '设置图片缓存的最大大小，范围100-5000MB', unit: 'MB'),
        ]),
        _section('备份设置', [
          _number('自动备份', 'autoBackupNum', 7, min: 1, max: 30, hint: '输入数值', help: '设置最大自动备份数量，范围1-30个', unit: '个'),
        ]),
        _section('AI模型', [
          ListTile(
            title: const Text('AI模型配置'),
            subtitle: const Text('配置多角色分析模型和正文净化模型', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Nav.openNamed(context, 'ai_model_page'),
          ),
        ]),
        _section('其他设置', [
          _choice('底栏隐藏', 'bottomBarHideMode', 0, const {0: '默认', 1: '底栏消失不显示按钮', 2: '底栏始终显示'}, '控制底栏滚动时的行为',
              after: MainTabs.changed),
          _switch('侧边导航', 'sideNavigation', false, '允许大屏设备开启侧边导航'),
          SwitchListTile(
            title: const Text('原生底栏'),
            subtitle: const Text('是否显示IOS26原生底栏', style: TextStyle(fontSize: 12)),
            value: _i('bottomBarType', 1) == 1,
            onChanged: (v) async {
              await Storage.setInt('bottomBarType', v ? 1 : 0);
              MainTabs.changed();
              setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// 底栏标签配置 (0x80773c / 0x8079e4): the five tabs in their configured order, drag to reorder, a switch for 发现 and 订阅 (书架 and 我的
/// are always shown), 取消 / 保存 (0x1095da0 -> `MainTabs.save`).
Future<void> showTabEditor(BuildContext context) {
  final order = List<String>.of(MainTabs.configured());
  var found = MainTabs.visible('发现');
  var ding = MainTabs.visible('订阅');
  const icons = {
    '书架': Icons.menu_book_outlined,
    '发现': Icons.travel_explore_outlined,
    '探索': Icons.explore_outlined,
    '订阅': Icons.bookmark_border,
    '我的': Icons.person_outline,
  };
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: theme.dividerColor.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.tab_outlined, size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('底栏标签配置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    Text('拖动调整顺序，开关控制显示/隐藏', style: TextStyle(fontSize: 14)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('「书架」和「我的」始终显示，但可以调整位置', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ReorderableListView(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) => set(() => order.insert(to, order.removeAt(from))),
                  children: [
                    for (var i = 0; i < order.length; i++)
                      Container(
                        key: ValueKey('tab_${order[i]}'),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          leading: Icon(icons[order[i]]),
                          title: Text(order[i]),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (order[i] == '发现')
                              Switch(key: const ValueKey('tab_switch_发现'), value: found, onChanged: (v) => set(() => found = v)),
                            if (order[i] == '订阅')
                              Switch(key: const ValueKey('tab_switch_订阅'), value: ding, onChanged: (v) => set(() => ding = v)),
                            ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await MainTabs.save(order, found: found, ding: ding);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('保存'),
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    ),
  );
}
