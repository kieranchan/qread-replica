// pages/read/pages/novel/read_more_setting.dart — "更多设置" of the reader (original `_ReadMoreSettingPageState`, build 0x7c5de4).
// Cards in the original's order, each switch / choice writes the key its closure writes:
//   隐藏状态栏 / 隐藏导航栏 (`hidetop` / `hidebottom`) · 锁定屏幕 (`lock`) · 双指缩放 (`two`, 0x1081774) · 屏幕常亮 (`wakelockTimeout`,
//   跟随系统 0 / 1分钟 / 2分钟 / 5分钟 / 10分钟 / 常亮 -1);
//   显示设置: 隐藏标题 (`hidetitle`) · 目录倒序 (the book's `reverseCatalog`, 0x1081478) · 完整CSS (`needcss2`, EPUB books only) · 朗读标识
//   (`readHighlightType` 下划线 / 阴影) · 标题对齐方式 (`titleAlign`) · 分割线 (`fen` 不显示 / 页眉 / 页脚 / 页眉和页脚) · 显示进度
//   (`showProgress`) · 显示段评 (`needdp`);
//   自定义页眉 💎 / 自定义页脚 💎: 左边区域 / 中间区域 / 右边区域, each a set of the items 时间 · 内置百分比电池 · 外置百分比电池 · 章节进度 ·
//   全文进度 · 标题 · 书名 (pp+0x72a78; `customHeaderLeft` ... `customFooterRight`, member feature);
//   翻页设置: 上滑退出 (`exit`) · 下滑书签 (`downmark`) · 音量键翻页 (`volumeButton`) · 翻页速度 (`pageTurnSpeed`, 毫秒);
//   页面设置: 页眉区域 / 页脚区域 (`showTop` / `showBottom`) · 底部对齐 (`bottomfix`) · AI 聊天 (`aichat`);
//   菜单设置: 菜单滑动条 按章节 / 按分页 (`menuSliderType` and `menuSliderType2`, 0x7cbbd8) · 顶栏按钮自定义 💎.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/bookself.dart';
import '../../../../models/book.dart';
import '../../../../read/setting/read_setting.dart';
import '../../../../storage/setting.dart';
import '../../../../storage/storage.dart';
import '../../../../util/vip.dart';
import 'views/top_menu.dart';

class ReadMoreSettingPage extends StatefulWidget {
  final ReadSetting setting;

  /// The open book (目录倒序, 完整CSS for EPUB); null outside the reader.
  final Book? book;
  const ReadMoreSettingPage({super.key, required this.setting, this.book});

  @override
  State<ReadMoreSettingPage> createState() => _ReadMoreSettingPageState();
}

class _ReadMoreSettingPageState extends State<ReadMoreSettingPage> {
  ReadSetting get s => widget.setting;

  static const Map<int, String> wakeChoices = WakeMode.labels;

  Future<void> _run(Future<void> Function() f) async {
    await f();
    if (mounted) setState(() {});
  }

  Widget _card(String? title, List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(title, style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
              ),
            ...children,
          ]),
        ),
      );

  Widget _switch(String title, bool value, Future<void> Function(bool v) onChanged, {String? help}) => SwitchListTile(
        title: Text(title),
        subtitle: help == null ? null : Text(help, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: (v) => _run(() => onChanged(v)),
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

  /// One custom slot: the seven items as chips; tapping toggles the item (member feature, 0x7ca77c / 0x7caaec).
  Widget _slot(String label, String key) {
    final items = s.slots[key] ?? const <int>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < SlotItem.names.length; i++)
            FilterChip(
              key: ValueKey('slot_${key}_$i'),
              label: Text(SlotItem.names[i], style: const TextStyle(fontSize: 12)),
              selected: items.contains(i),
              onSelected: (on) {
                if (!Vip.require()) return;
                final next = List<int>.of(items);
                on ? next.add(i) : next.remove(i);
                _run(() => s.setSlot(key, next));
              },
            ),
        ]),
      ]),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final epub = book != null && book.bookUrl.toLowerCase().endsWith('.epub');
    return Scaffold(
      appBar: AppBar(title: const Text('更多设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), centerTitle: true),
      body: ListView(
        children: [
          _card(null, [
            _switch('隐藏状态栏', s.hidetop, s.setHidetop),
            _switch('隐藏导航栏', s.hidebottom, s.setHidebottom),
            _switch('锁定屏幕', s.lock, (v) async {
              await s.setBool('lock', v);
              try {
                await SystemChrome.setPreferredOrientations(v ? const [DeviceOrientation.portraitUp] : const []);
              } catch (_) {}
            }),
            _switch('双指缩放', Storage.getBool('two'), (v) => Storage.setBool('two', v), help: '允许双指缩小或者放大内容（连点两下可恢复）。'),
            _choice<int>('屏幕常亮', s.wakelockTimeout, wakeChoices, s.setWakelockTimeout),
          ]),
          _card('显示设置', [
            _switch('隐藏标题', s.hidetitle, s.setHidetitle),
            if (book != null)
              _switch('目录倒序', book.reverseCatalog, (v) async {
                book.reverseCatalog = v;
                await BookSelfN.setReverseCatalog(book.bookUrl, v);
              }),
            if (epub)
              _switch('完整CSS', s.needcss2, (v) => s.setBool('needcss2', v), help: '是否用 webview 显示 epub 书本，使用 webview 后能显示完整 css。'),
            _choice<int>('朗读标识', s.readHighlightType, const {0: '下划线', 1: '阴影'}, (v) => s.setInt('readHighlightType', v)),
            _choice<int>('标题对齐方式', s.titleAlign, const {0: '左对齐', 1: '居中', 2: '右对齐'}, (v) => s.setTitle(align: v)),
            _choice<int>('分割线', s.fen, const {0: '不显示', 1: '页眉', 2: '页脚', 3: '页眉和页脚'}, s.setFen),
            _choice<int>('显示进度', s.showProgress, const {0: '不显示', 1: '章节进度', 2: '全文进度', 3: '章节进度和全文进度'}, s.setShowProgress),
            _switch('显示段评', s.needdp, (v) => s.setBool('needdp', v)),
          ]),
          _card('自定义页眉 💎', [
            _slot('左边区域', 'customHeaderLeft'),
            _slot('中间区域', 'customHeaderCenter'),
            _slot('右边区域', 'customHeaderRight'),
          ]),
          _card('自定义页脚 💎', [
            _slot('左边区域', 'customFooterLeft'),
            _slot('中间区域', 'customFooterCenter'),
            _slot('右边区域', 'customFooterRight'),
          ]),
          _card('翻页设置', [
            _switch('上滑退出', s.exit, (v) => s.setBool('exit', v)),
            _switch('下滑书签', s.downmark, (v) => s.setBool('downmark', v)),
            _switch('音量键翻页', s.volumeButton, s.setVolumeButton, help: '开启音量键翻页后进入阅读页面会停止播放其他音频，关闭后正常。'),
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
          ]),
          _card('页面设置', [
            _switch('页眉区域', s.showTop, (v) => s.setHeaderFooter(top: v)),
            _switch('页脚区域', s.showBottom, (v) => s.setHeaderFooter(bottom: v)),
            _switch('底部对齐', s.bottomfix, (v) => s.setBool('bottomfix', v), help: '将多出的高度均分给段高，使底部距离一致'),
            _switch('AI 聊天', s.aichat, (v) => s.setBool('aichat', v)),
          ]),
          _card('菜单设置', [
            _choice<int>('菜单滑动条', s.menuSliderType, const {0: '按章节', 1: '按分页'}, (v) async {
              await s.setMenuSliderType(v);
              await Storage.setInt('menuSliderType2', v);
            }),
            ListTile(title: const Text('顶栏按钮自定义 💎'), trailing: const Icon(Icons.chevron_right), onTap: _editTopButtons),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
