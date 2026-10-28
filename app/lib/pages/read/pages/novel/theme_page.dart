// pages/read/pages/novel/theme_page.dart — "编辑排版" / "新增排版": edits one layout preset (`BackGround` of `Ground.grounds`).
// Original `_ThemePageState` (98 functions, 0x65dc5c layout: 基础设置 · 排版名称 · 背景色 · 文字颜色 · 朗读文字颜色 · 标题HTML样式 (注意：必须包含
// $title 变量作为标题内容占位符) · 快速生成样式 · 背景图片 (正文背景图片 / 标题页背景图片 / 卷名页背景图片) · 高级设置 · 独立布局 (启用后，该排版将
// 使用独立布局设置); save 0x1013330: 请填写排版名称 / 请填写背景色 / 请填写文字颜色 / 排版已更新 / 排版已添加; 导出配置 / 导入配置 (导入成功！)).
// 取色 (0x100f288): the 背景色 becomes the colour of the centre pixel of the 正文背景图片 (asset or file; "无法加载图片" / "无法解码图片" /
// "取色失败: "). Uploading background images to the theme plaza belongs to the theme area.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/ground.dart';
import '../../../../models/back_ground.dart';
import '../../../../read/setting/read_setting.dart';
import '../../../../read/util/css.dart';
import '../../../../util/toast.dart';

class ThemePage extends StatefulWidget {
  /// The colour (`#rrggbb`) of the centre pixel of an encoded image.
  static Future<String> centerColor(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const FormatException('无法解码图片');
      final x = img.width ~/ 2, y = img.height ~/ 2;
      final o = (y * img.width + x) * 4;
      String h(int v) => v.toRadixString(16).padLeft(2, '0');
      return '#${h(data.getUint8(o))}${h(data.getUint8(o + 1))}${h(data.getUint8(o + 2))}';
    } finally {
      img.dispose();
    }
  }

  final ReadSetting setting;

  /// The preset to edit; null = a new one from the current settings.
  final BackGround? background;

  const ThemePage({super.key, required this.setting, this.background});

  @override
  State<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> {
  late BackGround _b;
  late final TextEditingController _name;
  late final TextEditingController _bg;
  late final TextEditingController _text;
  late final TextEditingController _read;
  late final TextEditingController _css;

  bool get _isNew => widget.background == null;

  @override
  void initState() {
    super.initState();
    _b = widget.background != null ? BackGround.fromJson(widget.background!.toJson()) : widget.setting.toBackGround();
    _name = TextEditingController(text: _b.themeName);
    _bg = TextEditingController(text: _b.backgroundColor);
    _text = TextEditingController(text: _b.textColor);
    _read = TextEditingController(text: _b.readColor);
    _css = TextEditingController(text: _b.titleCss);
  }

  @override
  void dispose() {
    for (final c in [_name, _bg, _text, _read, _css]) {
      c.dispose();
    }
    super.dispose();
  }

  void _collect() {
    _b
      ..themeName = _name.text.trim()
      ..backgroundColor = _bg.text.trim()
      ..textColor = _text.text.trim()
      ..readColor = _read.text.trim()
      ..titleCss = _css.text.trim();
  }

  Future<void> _save() async {
    _collect();
    if (_b.themeName.isEmpty) return Toast.show('请填写排版名称');
    if (_b.backgroundColor.isEmpty) return Toast.show('请填写背景色');
    if (_b.textColor.isEmpty) return Toast.show('请填写文字颜色');
    if (StyleGenUtils.parseColor(_b.backgroundColor) == null || StyleGenUtils.parseColor(_b.textColor) == null) {
      return Toast.show('请输入有效的颜色值');
    }
    if (_b.titleCss.isNotEmpty && !StyleGenUtils.isValidTemplate(_b.titleCss)) return Toast.show(r'必须包含 $title 变量作为标题占位符');
    if (_isNew) {
      var id = ReadSetting.userIdBase;
      for (final g in Ground.grounds) {
        if (g.name >= id) id = g.name + 1;
      }
      _b.name = id;
      await Ground.add(_b);
      Toast.show('排版已添加');
    } else {
      await Ground.update(_b);
      Toast.show('排版已更新');
    }
    if (widget.setting.currentBackgroundId == _b.name) await widget.setting.applyLayout(_b);
    if (mounted) Navigator.pop(context, _b);
  }

  Future<void> _quickStyle() async {
    var size = 24;
    var weight = 700;
    var align = 'left';
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('标题样式设置'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [const Text('字号'), Expanded(child: Slider(value: size.toDouble(), min: 12, max: 48, onChanged: (v) => set(() => size = v.round()))), Text('$size像素')]),
            Row(children: [
              const Text('字重'),
              const Spacer(),
              DropdownButton<int>(
                value: weight,
                items: const [
                  DropdownMenuItem(value: 300, child: Text('细')),
                  DropdownMenuItem(value: 400, child: Text('正常')),
                  DropdownMenuItem(value: 500, child: Text('中等')),
                  DropdownMenuItem(value: 700, child: Text('粗体')),
                  DropdownMenuItem(value: 900, child: Text('极粗')),
                ],
                onChanged: (v) => set(() => weight = v ?? weight),
              ),
            ]),
            Row(children: [
              const Text('文字对齐'),
              const Spacer(),
              DropdownButton<String>(
                value: align,
                items: const [
                  DropdownMenuItem(value: 'left', child: Text('左对齐')),
                  DropdownMenuItem(value: 'center', child: Text('居中')),
                  DropdownMenuItem(value: 'right', child: Text('右对齐')),
                ],
                onChanged: (v) => set(() => align = v ?? align),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                StyleGenUtils.generate(TitleStyleOptions(fontSize: size, fontWeight: weight, align: align, color: _text.text.trim())),
              ),
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
    if (r != null) setState(() => _css.text = r);
  }

  Future<void> _pickImage(int slot) async {
    final path = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('选择默认图片')),
          SizedBox(
            height: 72,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final p in ReadSetting.builtinImages)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, p),
                  child: Padding(padding: const EdgeInsets.all(4), child: Image.asset(p, width: 48, height: 64, fit: BoxFit.cover)),
                ),
            ]),
          ),
          ListTile(title: const Text('清除'), onTap: () => Navigator.pop(ctx, '')),
          ListTile(title: const Text('取消'), onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    );
    if (path == null) return;
    setState(() {
      switch (slot) {
        case 1:
          _b.backgroundimage = path;
        case 2:
          _b.backgroundimage2 = path;
        default:
          _b.backgroundimage3 = path;
      }
    });
  }

  Future<void> _pickColor() async {
    final path = _b.backgroundimage;
    if (path.isEmpty) return;
    Uint8List bytes;
    try {
      bytes = path.startsWith('lib/') || path.startsWith('assets/')
          ? (await rootBundle.load(path)).buffer.asUint8List()
          : await File(path).readAsBytes();
    } catch (_) {
      Toast.show('无法加载图片');
      return;
    }
    try {
      final c = await ThemePage.centerColor(bytes);
      if (!mounted) return;
      setState(() {
        _bg.text = c;
        _b.backgroundColor = c;
      });
    } catch (e) {
      debugPrint('Error extracting color: $e');
      Toast.show('取色失败: $e');
    }
  }

  Future<void> _export() async {
    _collect();
    await Clipboard.setData(ClipboardData(text: jsonEncode(_b.toJson())));
    Toast.show('已复制');
  }

  Future<void> _import() async {
    try {
      final d = await Clipboard.getData('text/plain');
      final m = jsonDecode(d?.text ?? '');
      if (m is! Map) throw const FormatException('格式错误');
      final b = BackGround.fromJson(Map<String, dynamic>.from(m))..name = _b.name;
      setState(() {
        _b = b;
        _name.text = b.themeName;
        _bg.text = b.backgroundColor;
        _text.text = b.textColor;
        _read.text = b.readColor;
        _css.text = b.titleCss;
      });
      Toast.show('导入成功！');
    } catch (e) {
      Toast.show('导入失败:$e');
    }
  }

  Widget _colorField(String label, TextEditingController c, String hint) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            suffixIcon: Padding(
              padding: const EdgeInsets.all(10),
              child: CircleAvatar(radius: 10, backgroundColor: StyleGenUtils.parseColor(c.text) ?? Colors.transparent),
            ),
          ),
        ),
      );

  Widget _imageTile(String label, String path, int slot) => ListTile(
        title: Text(label),
        subtitle: Text(path.isEmpty ? '点击选择图片' : '已选择'),
        trailing: path.isEmpty ? const Icon(Icons.image_outlined) : Image(image: ReadSetting.imageProviderOf(path), width: 32, height: 40, fit: BoxFit.cover),
        onTap: () => _pickImage(slot),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新增排版' : '编辑排版'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) => v == 'export' ? _export() : _import(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('导出配置')),
              PopupMenuItem(value: 'import', child: Text('导入配置')),
            ],
          ),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        children: [
          const ListTile(title: Text('基础设置')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(controller: _name, decoration: const InputDecoration(labelText: '排版名称', hintText: '请输入排版名称', border: OutlineInputBorder())),
          ),
          _colorField('背景色', _bg, '请输入背景色'),
          if (_b.backgroundimage.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('theme_pick_color'),
                icon: const Icon(Icons.colorize, size: 18),
                label: const Text('取色'),
                onPressed: _pickColor,
              ),
            ),
          _colorField('文字颜色', _text, '请输入文字颜色'),
          _colorField('朗读文字颜色', _read, '#1565C0'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _css,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '标题HTML样式',
                helperText: r'注意：必须包含 $title 变量作为标题内容占位符',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 8), child: TextButton(onPressed: _quickStyle, child: const Text('快速生成样式')))),
          const ListTile(title: Text('背景图片')),
          _imageTile('正文背景图片', _b.backgroundimage, 1),
          _imageTile('标题页背景图片', _b.backgroundimage2, 2),
          _imageTile('卷名页背景图片', _b.backgroundimage3, 3),
          const ListTile(title: Text('高级设置')),
          SwitchListTile(
            title: const Text('独立布局'),
            subtitle: const Text('启用后，该排版将使用独立布局设置'),
            value: _b.independentUI,
            onChanged: (v) => setState(() => _b.independentUI = v),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
