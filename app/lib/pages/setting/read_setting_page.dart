// pages/setting/read_setting_page.dart — "阅读设置" of the settings tab (original `_ReadSettingPageState`, 215 functions, 0x7fe684 ...).
// Sections and strings: 界面设置 (书架排序 · 首页书架书本的排列顺序 · 未读章节 · 书架页是否显示未读章节红点 · 书架缩放比例 (范围：50-200%,
// 请输入50-200之间的数字) · 每行个数 (0为自适应) · 底栏隐藏模式 (底栏始终显示 / 底栏消失不显示按钮) · 设置字体大小 · 文字详情 正常/简略),
// 阅读设置 (继续阅读 · 替换净化 · 沉浸光感 强/均衡/弱 + descriptions · 每日目标 · 历史记录 · 翻页方式 · 朗读优化 提前播报阈值 (毫秒) 范围：0-5000，
// 设为0则关闭 · 净化正则 匹配到的字符将在朗读时被移除 默认值：[^\w一-龥] · 朗读预缓存), 备份设置 (自动备份 · 设置最大自动备份数量 ·
// 当应用启动时会自动备份设置、书架等数据), 图片缓存 (设置图片最大缓存大小 · 请输入图片缓存的最大大小（单位：MB）).
// All values are prefs keys of docs/SETTINGS.md; other areas read them (shelf, main page, TTS).
// TODO(asm 0x8079e4): the bottom-bar tab editor (底栏标签配置) belongs to the main page and is not built here.
import 'package:flutter/material.dart';

import '../../read/setting/read_setting.dart';
import '../../storage/storage.dart';
import '../../util/toast.dart';

class ReadSettingPage extends StatefulWidget {
  const ReadSettingPage({super.key});

  @override
  State<ReadSettingPage> createState() => _ReadSettingPageState();
}

class _ReadSettingPageState extends State<ReadSettingPage> {
  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );

  Widget _switch(String title, String key, bool def, {String? subtitle}) => SwitchListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: Storage.getBool(key, def),
        onChanged: (v) async {
          await Storage.setBool(key, v);
          setState(() {});
        },
      );

  Widget _choice(String title, String key, int def, Map<int, String> options, {String? subtitle}) {
    final v = Storage.getInt(key, def);
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: DropdownButton<int>(
        value: options.containsKey(v) ? v : def,
        underline: const SizedBox(),
        items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (x) async {
          if (x == null) return;
          await Storage.setInt(key, x);
          setState(() {});
        },
      ),
    );
  }

  /// A number typed in a dialog, checked against [min]..[max] with the original's messages.
  Widget _number(String title, String key, int def, {required int min, required int max, required String hint, String? help, String unit = '', String? rangeError}) {
    final v = Storage.getInt(key, def);
    return ListTile(
      title: Text(title),
      subtitle: help == null ? null : Text(help),
      trailing: Text('$v$unit'),
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
        if (n < min || n > max) return Toast.show(rangeError ?? '请输入$min-$max之间的数字');
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
          const Text('匹配到的字符将在朗读时被移除'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读设置')),
      body: ListView(children: [
        _header('界面设置'),
        _choice('书架排序', 'booklistordrer', 0, const {0: '默认', 1: '更新时间', 2: '书名', 3: '作者'}, subtitle: '首页书架书本的排列顺序'),
        _switch('未读章节', 'isredupdate', true, subtitle: '书架页是否显示未读章节红点'),
        _number('书架缩放比例', 'bookshelfScale', 100,
            min: 50, max: 200, hint: '请输入缩放比例', unit: '%', help: '调整书架为列表时书本的显示大小，范围50-200%', rangeError: '请输入50-200之间的数字'),
        _number('每行个数', 'bookshelfColumns', 0, min: 0, max: 10, hint: '0为自适应', help: '0为自适应'),
        _choice('底栏隐藏模式', 'bottomBarHideMode', 0, const {0: '底栏始终显示', 1: '默认', 2: '底栏消失不显示按钮'}),
        _choice('文字详情', 'textDetail', 0, const {0: '正常', 1: '简略'}),
        _header('阅读设置'),
        _switch('继续阅读', 'continueRead', false),
        _switch('替换净化', 'useReplaceRule', true),
        _choice('沉浸光感', 'immersiveLight2223', 1, const {0: '强', 1: '均衡', 2: '弱'},
            subtitle: switch (Storage.getInt('immersiveLight2223', 1)) {
              0 => '最强光感特效，视觉效果最佳',
              2 => '无光感，适合性能较低的设备',
              _ => '兼顾效果与性能',
            }),
        _switch('每日目标', 'showDailyGoal', true),
        _switch('历史记录', 'historyRecord', true),
        _choice('翻页方式', 'turn', 0, TurnMode.labels()),
        _number('朗读优化', 'readyouhua', 0, min: 0, max: 5000, hint: '请输入毫秒数', help: '范围：0-5000，设为0则关闭', unit: '毫秒'),
        ListTile(title: const Text('净化正则'), subtitle: Text(Storage.getString('readPurificationRegex', r'[^\w一-龥]')), onTap: _regex),
        _number('朗读预缓存', 'listemcachenum', 15, min: 1, max: 50, hint: '输入数值', unit: '个'),
        _header('备份设置'),
        _number('自动备份', 'autoBackupNum', 7, min: 0, max: 100, hint: '输入数值', unit: '个', help: '当应用启动时会自动备份设置、书架等数据'),
        _header('图片缓存'),
        _number('图片缓存', 'maxImageCacheSize', 1000, min: 50, max: 100000, hint: '请输入图片缓存的最大大小（单位：MB）', unit: 'MB'),
        const SizedBox(height: 24),
      ]),
    );
  }
}
