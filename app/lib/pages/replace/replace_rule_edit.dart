// pages/replace/replace_rule_edit.dart — "替换规则编辑" (original `_ReplaceRuleEditState`, save 0x10470c8, copy/paste 0x1046da4).
// Fields and strings: 替换规则名称 (请输入替换规则名称) · 分组 · 替换规则 (请输入替换规则) · 使用正则表达式 · 替换为 · 作用于： 标题 / 正文 ·
// 替换范围，选填书名或者书源 URL · 排除范围，选填书名或者书源 URL · 超时毫秒数 (请输入有效的超时毫秒数) · 拷贝规则 / 粘贴规则 (规则已复制 /
// 粘贴失败: / 剪贴板为空!) · 保存成功 / 保存失败： / 规则名称重复 · 净化帮助. Pops `true` after a save.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/replace.dart';
import '../../models/replacerule.dart';
import '../../util/toast.dart';
import 'replace_rule_help.dart';

class ReplaceRuleEdit extends StatefulWidget {
  final ReplaceRule? rule;

  /// Pre-filled pattern (from the reader's selection "替换净化") and scope (the book name).
  final String initialPattern;
  final String scope;

  const ReplaceRuleEdit({super.key, this.rule, this.initialPattern = '', this.scope = ''});

  @override
  State<ReplaceRuleEdit> createState() => _ReplaceRuleEditState();
}

class _ReplaceRuleEditState extends State<ReplaceRuleEdit> {
  late final TextEditingController _name;
  late final TextEditingController _group;
  late final TextEditingController _pattern;
  late final TextEditingController _replacement;
  late final TextEditingController _scope;
  late final TextEditingController _exclude;
  late final TextEditingController _timeout;
  late bool _regex;
  late bool _title;
  late bool _content;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _name = TextEditingController(text: r?.name ?? (widget.initialPattern.length > 12 ? widget.initialPattern.substring(0, 12) : widget.initialPattern));
    _group = TextEditingController(text: r?.groupname ?? '');
    _pattern = TextEditingController(text: r?.pattern ?? widget.initialPattern);
    _replacement = TextEditingController(text: r?.replacement ?? '');
    _scope = TextEditingController(text: r?.scope ?? widget.scope);
    _exclude = TextEditingController(text: r?.excludeScope ?? '');
    _timeout = TextEditingController(text: '${r == null || r.timeoutMillisecond <= 0 ? 3000 : r.timeoutMillisecond}');
    _regex = r?.isRegex ?? false;
    _title = r?.scopeTitle ?? false;
    _content = r?.scopeContent ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _group, _pattern, _replacement, _scope, _exclude, _timeout]) {
      c.dispose();
    }
    super.dispose();
  }

  ReplaceRule _build() => ReplaceRule(
        id: widget.rule?.id ?? '',
        name: _name.text.trim(),
        groupname: _group.text.trim(),
        pattern: _pattern.text,
        replacement: _replacement.text,
        scope: _scope.text.trim(),
        excludeScope: _exclude.text.trim(),
        scopeTitle: _title,
        scopeContent: _content,
        isEnabled: widget.rule?.isEnabled ?? true,
        isRegex: _regex,
        timeoutMillisecond: int.tryParse(_timeout.text.trim()) ?? 0,
        ruleorder: widget.rule?.ruleorder ?? 0,
      );

  Future<void> _save() async {
    final r = _build();
    if (r.name.isEmpty) return Toast.show('请输入替换规则名称');
    if (r.pattern.isEmpty) return Toast.show('请输入替换规则');
    final t = int.tryParse(_timeout.text.trim());
    if (t == null || t <= 0) return Toast.show('请输入有效的超时毫秒数');
    if (r.isRegex) {
      try {
        RegExp(r.pattern);
      } catch (e) {
        return Toast.show('保存失败：$e');
      }
    }
    try {
      await ReplaceData.load();
      if (ReplaceData.rules.any((e) => e.name == r.name && e.id != r.id)) return Toast.show('规则名称重复');
      if (r.id.isEmpty) {
        await Replaces.add(r);
      } else {
        await Replaces.update(r);
      }
      Toast.show('保存成功');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      Toast.show('保存失败：$e');
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: jsonEncode(_build().toJson())));
    Toast.show('规则已复制');
  }

  Future<void> _paste() async {
    try {
      final d = await Clipboard.getData('text/plain');
      final text = d?.text ?? '';
      if (text.trim().isEmpty) return Toast.show('剪贴板为空!');
      final m = jsonDecode(text);
      if (m is! Map) throw const FormatException();
      final map = Map<String, dynamic>.from(m);
      map['groupname'] ??= map['group'];
      final r = ReplaceRule.fromJson(map);
      setState(() {
        _name.text = r.name;
        _group.text = r.groupname;
        _pattern.text = r.pattern;
        _replacement.text = r.replacement;
        _scope.text = r.scope;
        _exclude.text = r.excludeScope;
        _regex = r.isRegex;
        _title = r.scopeTitle;
        _content = r.scopeContent || !r.scopeTitle;
        if (r.timeoutMillisecond > 0) _timeout.text = '${r.timeoutMillisecond}';
      });
    } catch (e) {
      Toast.show('粘贴失败:$e');
    }
  }

  Widget _field(TextEditingController c, String label, {String? hint, int maxLines = 1, TextInputType? keyboard, Key? key}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          key: key,
          controller: c,
          maxLines: maxLines,
          minLines: 1,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('替换规则编辑'),
        actions: [
          IconButton(tooltip: '保存', icon: const Icon(Icons.save), onPressed: _save),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'copy' => _copy(),
              'paste' => _paste(),
              _ => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReplaceRuleHelp())),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('拷贝规则')),
              PopupMenuItem(value: 'paste', child: Text('粘贴规则')),
              PopupMenuItem(value: 'help', child: Text('净化帮助')),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          _field(_name, '替换规则名称', hint: '请输入替换规则名称', key: const ValueKey('rule_name')),
          _field(_group, '分组', hint: '请输入'),
          _field(_pattern, '替换规则', hint: '请输入替换规则', maxLines: 4, key: const ValueKey('rule_pattern')),
          CheckboxListTile(title: const Text('使用正则表达式'), value: _regex, onChanged: (v) => setState(() => _regex = v ?? false)),
          _field(_replacement, '替换为', maxLines: 3, key: const ValueKey('rule_replacement')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Text('作用于：'),
              Checkbox(value: _title, onChanged: (v) => setState(() => _title = v ?? false)),
              const Text('标题'),
              Checkbox(value: _content, onChanged: (v) => setState(() => _content = v ?? false)),
              const Text('正文'),
            ]),
          ),
          _field(_scope, '替换范围，选填书名或者书源 URL'),
          _field(_exclude, '排除范围，选填书名或者书源 URL'),
          _field(_timeout, '超时毫秒数', keyboard: TextInputType.number),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
