// pages/read/pages/novel/read_more_setting.dart — "更多设置" of the reader (original `_ReadMoreSettingPageState`, 97 functions).
// Sections and strings are the original's: 显示设置 (隐藏状态栏 · 隐藏导航栏 · 隐藏标题 · 标题对齐方式 左对齐/居中/右对齐 · 页眉/页脚
// 不显示/页眉/页脚/页眉和页脚 · 显示进度 不显示/章节进度/全文进度/章节进度和全文进度 · 朗读标识 下划线/阴影 · 自定义页眉 💎), 翻页设置
// (音量键翻页 · 翻页速度 毫秒 · 双指缩放), 更多设置 (屏幕常亮 跟随系统/1分钟/2分钟/5分钟/10分钟/常亮 · 锁定屏幕 · 目录倒序 · 完整CSS ·
// 顶栏按钮自定义 💎 "此功能为会员专享，开通会员后可自定义顶栏按钮").
// TODO(asm 0x1010228): the custom header/footer slot editor (自定义页眉 💎: 左边区域 / 中间区域 / 右边区域) is gated but not built;
// TODO(asm read_more_setting): 屏幕常亮 is stored (`wakelockTimeout`) but no wakelock plugin is bundled; 双指缩放 / 显示段评 are not ported.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../read/setting/read_setting.dart';
import '../../../../storage/setting.dart';
import '../../../../util/vip.dart';
import 'views/top_menu.dart';

class ReadMoreSettingPage extends StatefulWidget {
  final ReadSetting setting;
  const ReadMoreSettingPage({super.key, required this.setting});

  @override
  State<ReadMoreSettingPage> createState() => _ReadMoreSettingPageState();
}

class _ReadMoreSettingPageState extends State<ReadMoreSettingPage> {
  ReadSetting get s => widget.setting;

  static const Map<int, String> wakeChoices = {-1: '跟随系统', 1: '1分钟', 2: '2分钟', 5: '5分钟', 10: '10分钟', 0: '常亮'};

  Future<void> _run(Future<void> Function() f) async {
    await f();
    if (mounted) setState(() {});
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );

  Widget _choice<T>(String title, T value, Map<T, String> options, Future<void> Function(T v) onChanged) => ListTile(
        title: Text(title),
        trailing: DropdownButton<T>(
          value: options.containsKey(value) ? value : options.keys.first,
          underline: const SizedBox(),
          items: [for (final e in options.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            if (v != null) _run(() => onChanged(v));
          },
        ),
      );

  Future<void> _editTopButtons() async {
    if (!Vip.require('此功能为会员专享，开通会员后可自定义顶栏按钮')) return;
    final selected = Setting.getTopMenuButtons().toSet();
    final r = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('顶栏按钮自定义 💎'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final id in Setting.validTopMenuButtons)
                CheckboxListTile(
                  dense: true,
                  value: selected.contains(id),
                  title: Text(TopMenu.entries[id]?.label ?? id),
                  onChanged: (v) => set(() => v == true ? selected.add(id) : selected.remove(id)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, [for (final id in Setting.validTopMenuButtons) if (selected.contains(id)) id]),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (r != null) await Setting.setTopMenuButtons(r);
  }

  int get _headerFooter => (s.showTop ? 1 : 0) + (s.showBottom ? 2 : 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更多设置')),
      body: ListView(
        children: [
          _header('显示设置'),
          SwitchListTile(title: const Text('隐藏状态栏'), value: s.hidetop, onChanged: (v) => _run(() => s.setHidetop(v))),
          SwitchListTile(title: const Text('隐藏导航栏'), value: s.hidebottom, onChanged: (v) => _run(() => s.setHidebottom(v))),
          SwitchListTile(title: const Text('隐藏标题'), value: s.hidetitle, onChanged: (v) => _run(() => s.setHidetitle(v))),
          _choice<int>('标题对齐方式', s.titleAlign, const {0: '左对齐', 1: '居中', 2: '右对齐'}, (v) => s.setTitle(align: v)),
          _choice<int>('页眉页脚', _headerFooter, const {0: '不显示', 1: '页眉', 2: '页脚', 3: '页眉和页脚'},
              (v) => s.setHeaderFooter(top: v & 1 != 0, bottom: v & 2 != 0)),
          _choice<int>('显示进度', s.showProgress, const {0: '不显示', 1: '章节进度', 2: '全文进度', 3: '章节进度和全文进度'}, s.setShowProgress),
          _choice<int>('朗读标识', s.readHighlightType, const {0: '下划线', 1: '阴影'}, (v) => s.setInt('readHighlightType', v)),
          ListTile(title: const Text('自定义页眉 💎'), trailing: const Icon(Icons.chevron_right), onTap: () => Vip.require()),
          _header('翻页设置'),
          SwitchListTile(title: const Text('音量键翻页'), value: s.volumeButton, onChanged: (v) => _run(() => s.setVolumeButton(v))),
          ListTile(
            title: const Text('翻页速度'),
            subtitle: Slider(
              value: s.pageTurnSpeed.toDouble(),
              min: 100,
              max: 1000,
              divisions: 18,
              onChanged: (v) => _run(() => s.setPageTurnSpeed(v.round())),
            ),
            trailing: Text('${s.pageTurnSpeed}毫秒'),
          ),
          SwitchListTile(title: const Text('下拉添加书签'), value: s.downmark, onChanged: (v) => _run(() => s.setBool('downmark', v))),
          SwitchListTile(title: const Text('上滑退出阅读'), value: s.exit, onChanged: (v) => _run(() => s.setBool('exit', v))),
          _header('更多设置'),
          _choice<int>('屏幕常亮', s.wakelockTimeout, wakeChoices, s.setWakelockTimeout),
          SwitchListTile(
            title: const Text('锁定屏幕'),
            value: s.lock,
            onChanged: (v) => _run(() async {
              await s.setBool('lock', v);
              try {
                await SystemChrome.setPreferredOrientations(v ? const [DeviceOrientation.portraitUp] : const []);
              } catch (_) {}
            }),
          ),
          SwitchListTile(title: const Text('完整CSS'), value: s.needcss2, onChanged: (v) => _run(() => s.setBool('needcss2', v))),
          SwitchListTile(title: const Text('AI 助手'), value: s.aichat, onChanged: (v) => _run(() => s.setBool('aichat', v))),
          ListTile(title: const Text('顶栏按钮自定义 💎'), trailing: const Icon(Icons.chevron_right), onTap: _editTopButtons),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
