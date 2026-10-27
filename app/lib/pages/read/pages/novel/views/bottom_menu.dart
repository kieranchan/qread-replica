// pages/read/pages/novel/views/bottom_menu.dart — the reader's bottom menu (original `ButtomMenu` / `_ButtomMenuState`, 352 functions).
//
// Main bar: chapter progress slider with 上一章 / 下一章, buttons 目录 · 朗读 · 界面 · 设置 · 夜间/白天, side buttons for auto turn, AI chat
// (`aichat`), brightness and search. Panels (strings of the original): 界面设置 (字号 · 字体 · 单列/双列 · 间距设置 · 翻页设置 · 排版管理 · 更多),
// 背景设置 / 亮度设置 (自动), 间距设置 (标题间距 ...), 翻页设置 (翻页方式 · 点击区域), 排版管理 (排版 N · 使用中 · 编辑排版 · 删除排版 ·
// 确定要删除排版"…"吗？ · 排版已删除 · 应用排版:  · 排版添加成功 · 暂无自定义排版 · 点击右上角+添加排版).
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../../../data/ground.dart';
import '../../../../../models/back_ground.dart';
import '../../../../../read/setting/read_setting.dart';
import '../../../../../read/util/read.dart';
import '../../../../../util/toast.dart';
import '../read_more_setting.dart';
import '../theme_page.dart';
import 'reader_host.dart';
import 'turn.dart';

enum _Panel { main, ui, light, space, turn, layout }

class ButtomMenu extends StatefulWidget {
  final ReaderHost host;
  final VoidCallback? onAiChat;

  const ButtomMenu({super.key, required this.host, this.onAiChat});

  @override
  State<ButtomMenu> createState() => _ButtomMenuState();
}

class _ButtomMenuState extends State<ButtomMenu> {
  _Panel _panel = _Panel.main;
  double? _dragChapter;
  List<ReaderFont> _fonts = ReaderFonts.builtin;

  ReaderHost get host => widget.host;
  ReadSetting get s => widget.host.setting;

  @override
  void initState() {
    super.initState();
    ReaderFonts.all().then((f) {
      if (mounted) setState(() => _fonts = f);
    });
    Ground.load().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object _) {});
  }

  void _go(_Panel p) => setState(() => _panel = p);

  // ------------------------------------------------------------------ main bar

  Widget _main(BuildContext context) {
    final n = host.chapters.length;
    final cur = (_dragChapter ?? host.chapterIndex.toDouble()).clamp(0.0, (n - 1).toDouble());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          TextButton(onPressed: host.prevChapter, child: const Text('上一章')),
          Expanded(
            child: Slider(
              value: cur,
              min: 0,
              max: n <= 1 ? 1 : (n - 1).toDouble(),
              label: n == 0 ? '' : host.chapters[cur.round().clamp(0, n - 1)].name,
              divisions: n <= 1 ? null : n - 1,
              onChanged: n <= 1 ? null : (v) => setState(() => _dragChapter = v),
              onChangeEnd: (v) {
                setState(() => _dragChapter = null);
                host.jumpToChapter(v.round());
              },
            ),
          ),
          TextButton(onPressed: host.nextChapter, child: const Text('下一章')),
        ]),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _tool(Icons.format_list_bulleted, '目录', host.openCatalog),
            _tool(Icons.headphones_outlined, '朗读', host.startListen),
            _tool(Icons.text_fields, '界面', () => _go(_Panel.ui)),
            _tool(Icons.settings_outlined, '设置', () => _push(context, ReadMoreSettingPage(setting: s))),
            _tool(s.night ? Icons.light_mode_outlined : Icons.dark_mode_outlined, s.night ? '白天' : '夜间', host.toggleNight),
          ],
        ),
      ],
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 12))]),
        ),
      );

  Future<void> _push(BuildContext context, Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------ 界面设置

  Widget _title(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(children: [
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_back), onPressed: () => _go(_panel == _Panel.ui || _panel == _Panel.light ? _Panel.main : _Panel.ui)),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          ?trailing,
        ]),
      );

  Widget _ui(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('界面设置', trailing: TextButton(onPressed: () => _push(context, ReadMoreSettingPage(setting: s)), child: const Text('更多'))),
        _row('字号', Row(children: [
          IconButton(key: const ValueKey('font_minus'), icon: const Icon(Icons.text_decrease), onPressed: s.fontSize <= 10 ? null : () => s.setFontSize(s.fontSize - 1)),
          SizedBox(width: 36, child: Text('${s.fontSize}', textAlign: TextAlign.center, key: const ValueKey('font_size_value'))),
          IconButton(key: const ValueKey('font_plus'), icon: const Icon(Icons.text_increase), onPressed: s.fontSize >= 55 ? null : () => s.setFontSize(s.fontSize + 1)),
        ])),
        _row('字体', SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final f in _fonts)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: s.fontFamily == f.family,
                    onSelected: (_) async {
                      final ok = await ReaderFonts.ensure(f.family);
                      if (!ok) {
                        Toast.show('字体加载失败');
                        return;
                      }
                      await s.setFontFamily(f.family);
                    },
                  ),
                ),
            ],
          ),
        )),
        _row('排版', Wrap(spacing: 6, children: [
          ChoiceChip(label: const Text('单列'), selected: s.fen != 2, onSelected: (_) => s.setFen(1)),
          ChoiceChip(label: const Text('双列'), selected: s.fen == 2, onSelected: (_) => s.setFen(2)),
        ])),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: () => _go(_Panel.space), child: const Text('间距设置')),
            OutlinedButton(onPressed: () => _go(_Panel.turn), child: const Text('翻页设置')),
            OutlinedButton(onPressed: () => _go(_Panel.layout), child: const Text('排版管理')),
            OutlinedButton(onPressed: () => _go(_Panel.light), child: const Text('背景设置')),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _row(String label, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(children: [SizedBox(width: 56, child: Text(label)), Expanded(child: child)]),
      );

  // ------------------------------------------------------------------ 背景设置 / 亮度设置

  Widget _swatch(int id, {String? label}) {
    final c = s.config(id);
    final selected = s.currentBackgroundId == id;
    return GestureDetector(
      onTap: () => s.setBackgroundId(id),
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.only(right: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.backgroundColor,
          image: c.image,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.black12, width: selected ? 3 : 1),
        ),
        child: Text(label ?? '文', style: TextStyle(color: c.textColor, fontSize: 12)),
      ),
    );
  }

  Widget _light(BuildContext context) {
    final grounds = Ground.grounds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('背景设置'),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < ReadSetting.builtinColors.length; i++) _swatch(i),
              for (var i = 0; i < ReadSetting.builtinImages.length; i++) _swatch(ReadSetting.imageIdBase + i),
              for (final g in grounds)
                if (g.name >= ReadSetting.userIdBase) _swatch(g.name, label: g.themeName.isEmpty ? null : g.themeName.characters.first),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('亮度设置')),
        Row(children: [
          const SizedBox(width: 8),
          const Icon(Icons.brightness_low, size: 18),
          Expanded(
            child: Slider(
              value: s.brightness < 0 ? 1 : s.brightness,
              onChanged: s.autoBrightness ? null : (v) => s.setBrightness(v),
            ),
          ),
          const Icon(Icons.brightness_high, size: 18),
          Checkbox(value: s.autoBrightness, onChanged: (v) => s.setAutoBrightness(v ?? true)),
          const Text('自动'),
          const SizedBox(width: 12),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }

  // ------------------------------------------------------------------ 间距设置

  Widget _space(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('间距设置'),
        _SettingSlider(label: '行距', value: s.lineHeight, min: 1, max: 4, divisions: 30, digits: 1, onCommit: s.setLineHeight),
        _SettingSlider(label: '段距', value: s.paragraphSpacing, min: 0, max: 100, divisions: 100, onCommit: s.setParagraphSpacing),
        _SettingSlider(label: '字距', value: s.letterSpacing, min: -2, max: 10, divisions: 24, digits: 1, onCommit: s.setLetterSpacing),
        _SettingSlider(label: '缩进', value: s.kong.toDouble(), min: 0, max: 4, divisions: 4, onCommit: (v) => s.setKong(v.round())),
        _SettingSlider(label: '上边距', value: s.topMargin.toDouble(), min: 0, max: 100, divisions: 100, onCommit: (v) => s.setMargins(top: v.round())),
        _SettingSlider(label: '下边距', value: s.bottomMargin.toDouble(), min: 0, max: 100, divisions: 100, onCommit: (v) => s.setMargins(bottom: v.round())),
        _SettingSlider(label: '左边距', value: s.leftMargin.toDouble(), min: 0, max: 100, divisions: 100, onCommit: (v) => s.setMargins(left: v.round())),
        _SettingSlider(label: '右边距', value: s.rightMargin.toDouble(), min: 0, max: 100, divisions: 100, onCommit: (v) => s.setMargins(right: v.round())),
        _SettingSlider(label: '标题间距', value: s.titleBottomMargin.toDouble(), min: 0, max: 100, divisions: 100, onCommit: (v) => s.setTitle(bottom: v.round())),
        const SizedBox(height: 8),
      ],
    );
  }

  // ------------------------------------------------------------------ 翻页设置

  Widget _turn(BuildContext context) {
    final ios = Platform.isIOS;
    final labels = TurnMode.labels(ios: ios);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('翻页设置'),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('翻页方式')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final e in labels.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: s.turn == e.key,
                onSelected: (_) {
                  if (e.key == TurnMode.appleBook && s.needcss2) {
                    Toast.show('完整 css 无法使用 IOS 原生仿真，请先关闭完整 CSS！');
                    return;
                  }
                  s.setTurn(e.key);
                },
              ),
          ]),
        ),
        _SettingSlider(label: '速度', value: s.pageTurnSpeed.toDouble(), min: 100, max: 1000, divisions: 18, unit: '毫秒', onCommit: (v) => s.setPageTurnSpeed(v.round())),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [
            OutlinedButton(
              onPressed: () async {
                final r = await Navigator.of(context).push<ClickAreaSetting>(
                  MaterialPageRoute(builder: (_) => CustomClickAreaSetting(initial: s.clickArea)),
                );
                if (r != null) await s.setClickArea(r);
              },
              child: const Text('点击区域'),
            ),
            OutlinedButton(onPressed: host.startAutoTurn, child: const Text('自动翻页')),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ------------------------------------------------------------------ 排版管理

  Future<void> _addLayout() async {
    var id = ReadSetting.userIdBase;
    for (final g in Ground.grounds) {
      if (g.name >= id) id = g.name + 1;
    }
    final b = s.toBackGround(name: id, themeName: '排版 ${id - ReadSetting.userIdBase + 1}');
    await Ground.add(b);
    Toast.show('排版添加成功');
    if (mounted) setState(() {});
  }

  Future<void> _deleteLayout(BackGround g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除排版"${g.themeName}"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) return;
    await Ground.delete(g.name);
    if (s.background == g.name) await s.setBackgroundId(0, forNight: false);
    if (s.darkbackground == g.name) await s.setBackgroundId(4, forNight: true);
    Toast.show('排版已删除');
    if (mounted) setState(() {});
  }

  Widget _layout(BuildContext context) {
    final list = [for (final g in Ground.grounds) if (g.name >= ReadSetting.userIdBase) g];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('排版管理', trailing: IconButton(tooltip: '新增排版', icon: const Icon(Icons.add), onPressed: _addLayout)),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('暂无自定义排版\n点击右上角+添加排版', textAlign: TextAlign.center)),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final g in list)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(backgroundColor: ReadSetting.parseColor(g.backgroundColor) ?? Colors.white),
                  title: Text(g.themeName.isEmpty ? '排版 ${g.name}' : g.themeName),
                  subtitle: s.currentBackgroundId == g.name ? const Text('使用中') : null,
                  onTap: () async {
                    await s.applyLayout(g);
                    await s.setBackgroundId(g.name);
                    Toast.show('应用排版: ${g.themeName}');
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        await _push(context, ThemePage(setting: s, background: g));
                      } else {
                        await _deleteLayout(g);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑排版')),
                      PopupMenuItem(value: 'delete', child: Text('删除排版')),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = switch (_panel) {
      _Panel.main => _main(context),
      _Panel.ui => _ui(context),
      _Panel.light => _light(context),
      _Panel.space => _space(context),
      _Panel.turn => _turn(context),
      _Panel.layout => _layout(context),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_panel == _Panel.main)
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (s.aichat && widget.onAiChat != null)
                _fab(Icons.smart_toy_outlined, 'AI', widget.onAiChat!),
              _fab(Icons.search, '搜索正文', host.openSearch),
              _fab(Icons.slow_motion_video, '自动翻页', host.startAutoTurn),
              _fab(Icons.brightness_6_outlined, '亮度设置', () => _go(_Panel.light)),
            ]),
          ),
        Material(
          color: scheme.surfaceContainerHigh,
          elevation: 6,
          child: SafeArea(top: false, child: AnimatedSize(duration: const Duration(milliseconds: 150), child: body)),
        ),
      ],
    );
  }

  Widget _fab(IconData icon, String tip, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FloatingActionButton.small(heroTag: null, tooltip: tip, onPressed: onTap, child: Icon(icon)),
      );
}

/// A slider that shows the value while dragging and commits it once at the end (a commit re-paginates the book).
class _SettingSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final int digits;
  final String unit;
  final Future<void> Function(double v) onCommit;

  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    this.divisions,
    this.digits = 0,
    this.unit = '',
  });

  @override
  State<_SettingSlider> createState() => _SettingSliderState();
}

class _SettingSliderState extends State<_SettingSlider> {
  double? _v;

  @override
  Widget build(BuildContext context) {
    final v = (_v ?? widget.value).clamp(widget.min, widget.max);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        SizedBox(width: 56, child: Text(widget.label)),
        Expanded(
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (x) => setState(() => _v = x),
            onChangeEnd: (x) async {
              await widget.onCommit(x);
              if (mounted) setState(() => _v = null);
            },
          ),
        ),
        SizedBox(width: 64, child: Text('${v.toStringAsFixed(widget.digits)}${widget.unit}', textAlign: TextAlign.end)),
      ]),
    );
  }
}
