// pages/highlight/highlight_rule_edit.dart — "高亮规则编辑" (original `_HighlightRuleEditState` 0x64bf54, save 0x100cb50).
// Strings: 规则名称 (请输入规则名称) · 分组 · 匹配规则（正则或文本） (请输入匹配规则) · 使用正则表达式 · 快捷正则规则（点击直接填入） · 白天 / 夜间 ·
// 文字颜色 · 背景颜色 (如 #FF0000 或 red) · 字体样式 正常/斜体 · 字体粗细 细/正常/中等/粗体/特粗 · 文本装饰 无/下划线/删除线/上划线 · 字体大小
// (如 16px 或 1.2em) · 行高 (如 1.5) · 字体 系统默认 · 文字示例 · 保存成功 / 保存失败： / 规则名称重复.
// TODO(asm 0x6513e0): background images with nine-patch stretching (上传背景图 / 拖拽 4 条线划分九宫格 / 透明度 / 文字边距) are not ported; the
// reader does not draw them (see read/util/highlight_apply.dart). TODO(asm 0x64bf54): the original list of quick regex presets.
import 'package:flutter/material.dart';

import '../../data/highlight.dart';
import '../../models/highlight_rule.dart';
import '../../read/util/css.dart';
import '../../read/util/highlight_apply.dart';
import '../../util/toast.dart';

class HighlightRuleEdit extends StatefulWidget {
  final HighlightRule? rule;
  const HighlightRuleEdit({super.key, this.rule});

  @override
  State<HighlightRuleEdit> createState() => _HighlightRuleEditState();
}

class _HighlightRuleEditState extends State<HighlightRuleEdit> {
  late HighlightRule _r;
  late final TextEditingController _name;
  late final TextEditingController _group;
  late final TextEditingController _pattern;
  late final Map<String, TextEditingController> _c;
  bool _night = false;

  static const Map<String, String> quick = {
    '“对话”': '“[^”]*”',
    '「对话」': '「[^」]*」',
    '数字': r'\d+',
    '英文': r'[A-Za-z]+',
    '括号': r'（[^）]*）|\([^)]*\)',
  };

  @override
  void initState() {
    super.initState();
    _r = widget.rule == null ? HighlightRule(isEnabled: true) : HighlightRule.fromJson(widget.rule!.toJson());
    _name = TextEditingController(text: _r.name);
    _group = TextEditingController(text: _r.groupname);
    _pattern = TextEditingController(text: _r.pattern);
    _c = {
      'dayColor': TextEditingController(text: _r.dayColor),
      'nightColor': TextEditingController(text: _r.nightColor),
      'dayBgColor': TextEditingController(text: _r.dayBgColor),
      'nightBgColor': TextEditingController(text: _r.nightBgColor),
      'fontSize': TextEditingController(text: _r.fontSize),
      'lineHeight': TextEditingController(text: _r.lineHeight),
    };
  }

  @override
  void dispose() {
    for (final c in [_name, _group, _pattern, ..._c.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _collect() {
    _r
      ..name = _name.text.trim()
      ..groupname = _group.text.trim()
      ..pattern = _pattern.text
      ..dayColor = _c['dayColor']!.text.trim()
      ..nightColor = _c['nightColor']!.text.trim()
      ..dayBgColor = _c['dayBgColor']!.text.trim()
      ..nightBgColor = _c['nightBgColor']!.text.trim()
      ..fontSize = _c['fontSize']!.text.trim()
      ..lineHeight = _c['lineHeight']!.text.trim();
  }

  Future<void> _save() async {
    _collect();
    if (_r.name.isEmpty) return Toast.show('请输入规则名称');
    if (_r.pattern.isEmpty) return Toast.show('请输入匹配规则');
    if (_r.isRegex && !HighlightData.isValid(_r)) return Toast.show('保存失败：正则表达式错误');
    try {
      await HighlightData.load();
      if (HighlightData.rules.any((e) => e.name == _r.name && e.id != _r.id)) return Toast.show('规则名称重复');
      if (_r.id.isEmpty) {
        await Highlights.add(_r);
      } else {
        await Highlights.update(_r);
      }
      Toast.show('保存成功');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      Toast.show('保存失败：$e');
    }
  }

  Widget _field(TextEditingController c, String label, {String? hint, Key? key, bool color = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          key: key,
          controller: c,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            suffixIcon: color
                ? Padding(padding: const EdgeInsets.all(10), child: CircleAvatar(radius: 10, backgroundColor: StyleGenUtils.parseColor(c.text) ?? Colors.transparent))
                : null,
          ),
        ),
      );

  Widget _preview() {
    _collect();
    final bg = _night ? const Color(0xFF000000) : const Color(0xFFE6E6E6);
    final fg = _night ? Colors.white70 : Colors.black87;
    const sample = '文字示例：“这是一句对话。”他说道。';
    final decos = HighlightApply.ruleDecos(sample, [HighlightRule.fromJson(_r.toJson())..isEnabled = true], night: _night);
    final spans = <TextSpan>[];
    var pos = 0;
    for (final d in decos..sort((a, b) => a.start.compareTo(b.start))) {
      if (d.start < pos) continue;
      if (d.start > pos) spans.add(TextSpan(text: sample.substring(pos, d.start)));
      spans.add(TextSpan(text: sample.substring(d.start, d.end), style: d.apply(const TextStyle())));
      pos = d.end;
    }
    if (pos < sample.length) spans.add(TextSpan(text: sample.substring(pos)));
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      color: bg,
      child: Text.rich(TextSpan(style: TextStyle(color: fg, fontSize: 16), children: spans)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _night ? 'night' : 'day';
    return Scaffold(
      appBar: AppBar(title: const Text('高亮规则编辑'), actions: [IconButton(tooltip: '保存', icon: const Icon(Icons.save), onPressed: _save)]),
      body: ListView(
        children: [
          _field(_name, '规则名称', hint: '请输入规则名称', key: const ValueKey('hl_name')),
          _field(_group, '分组', hint: '请输入'),
          _field(_pattern, '匹配规则（正则或文本）', hint: '请输入匹配规则', key: const ValueKey('hl_pattern')),
          CheckboxListTile(title: const Text('使用正则表达式'), value: _r.isRegex, onChanged: (v) => setState(() => _r.isRegex = v ?? false)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('快捷正则规则（点击直接填入）')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 6, children: [
              for (final e in quick.entries)
                ActionChip(
                  label: Text(e.key),
                  onPressed: () => setState(() {
                    _pattern.text = e.value;
                    _r.isRegex = true;
                  }),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('白天')), ButtonSegment(value: true, label: Text('夜间'))],
              selected: {_night},
              onSelectionChanged: (s) => setState(() => _night = s.first),
            ),
          ),
          _field(_c['${p}Color']!, '文字颜色', hint: '如 #FF0000 或 red', color: true),
          _field(_c['${p}BgColor']!, '背景颜色', hint: '如 #FF0000 或 red', color: true),
          ListTile(
            title: const Text('字体样式'),
            trailing: DropdownButton<String>(
              value: _r.fontStyle == 'italic' ? 'italic' : '',
              items: const [DropdownMenuItem(value: '', child: Text('正常')), DropdownMenuItem(value: 'italic', child: Text('斜体'))],
              onChanged: (v) => setState(() => _r.fontStyle = v ?? ''),
            ),
          ),
          ListTile(
            title: const Text('字体粗细'),
            trailing: DropdownButton<String>(
              value: const ['', '300', '400', '500', '700', '800'].contains(_r.fontWeight) ? _r.fontWeight : '',
              items: const [
                DropdownMenuItem(value: '', child: Text('无')),
                DropdownMenuItem(value: '300', child: Text('细')),
                DropdownMenuItem(value: '400', child: Text('正常')),
                DropdownMenuItem(value: '500', child: Text('中等')),
                DropdownMenuItem(value: '700', child: Text('粗体')),
                DropdownMenuItem(value: '800', child: Text('特粗')),
              ],
              onChanged: (v) => setState(() => _r.fontWeight = v ?? ''),
            ),
          ),
          ListTile(
            title: const Text('文本装饰'),
            trailing: DropdownButton<String>(
              value: const ['', 'underline', 'line-through', 'overline'].contains(_r.textDecoration) ? _r.textDecoration : '',
              items: const [
                DropdownMenuItem(value: '', child: Text('无')),
                DropdownMenuItem(value: 'underline', child: Text('下划线')),
                DropdownMenuItem(value: 'line-through', child: Text('删除线')),
                DropdownMenuItem(value: 'overline', child: Text('上划线')),
              ],
              onChanged: (v) => setState(() => _r.textDecoration = v ?? ''),
            ),
          ),
          _field(_c['fontSize']!, '字体大小', hint: '如 16px 或 1.2em'),
          _field(_c['lineHeight']!, '行高', hint: '如 1.5'),
          _preview(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
