// pages/txtrule/txt_rule_edit.dart — "目录规则编辑" (original `_TxtRuleEditState` 0x6d7da8: 拷贝规则 · 粘贴规则; save shares the replace-rule
// texts 保存成功 / 保存失败： / 规则名称重复 / 规则已复制 / 粘贴失败: / 剪贴板为空!). A rule is a regular expression matched against each line of
// a TXT file; "测试" shows the lines of a sample that would become chapter titles. Pops `true` after a save.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/txtrule.dart';
import '../../models/txt_toc_rule.dart';
import '../../util/toast.dart';

/// Lines of [sample] that [rule] marks as chapter titles (multi-line regex, like the TXT parser).
List<String> testTxtRule(String rule, String sample) {
  final re = RegExp(rule, multiLine: true);
  return [for (final m in re.allMatches(sample)) m.group(0)!.trim()].where((s) => s.isNotEmpty).toList();
}

class TxtRuleEdit extends StatefulWidget {
  final TxtTocRule? rule;
  const TxtRuleEdit({super.key, this.rule});

  @override
  State<TxtRuleEdit> createState() => _TxtRuleEditState();
}

class _TxtRuleEditState extends State<TxtRuleEdit> {
  late final TextEditingController _name = TextEditingController(text: widget.rule?.name ?? '');
  late final TextEditingController _rule = TextEditingController(text: widget.rule?.rule ?? '');
  final TextEditingController _sample = TextEditingController(text: '第一章 开始\n正文内容……\n第二章 继续\n正文内容……');
  List<String>? _result;
  String? _error;

  bool get _locked => widget.rule != null && !widget.rule!.candel;

  @override
  void dispose() {
    _name.dispose();
    _rule.dispose();
    _sample.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final rule = _rule.text;
    if (name.isEmpty || rule.isEmpty) return Toast.show('保存失败：名称和规则不能为空');
    try {
      RegExp(rule);
    } catch (e) {
      return Toast.show('保存失败：$e');
    }
    try {
      await Txtruledata.load();
      final old = widget.rule?.name;
      if (Txtruledata.rules.any((r) => r.name == name && r.name != old)) return Toast.show('规则名称重复');
      final r = TxtTocRule(name: name, rule: rule, candel: true, isEnabled: widget.rule?.isEnabled ?? true);
      if (old == null) {
        await Txtrule.add(r);
      } else {
        await Txtrule.update(old, r);
      }
      Toast.show('保存成功');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      Toast.show('保存失败：$e');
    }
  }

  void _test() {
    setState(() {
      try {
        _result = testTxtRule(_rule.text, _sample.text);
        _error = null;
      } catch (e) {
        _error = '$e';
        _result = null;
      }
    });
  }

  Future<void> _paste() async {
    try {
      final d = await Clipboard.getData('text/plain');
      final text = d?.text ?? '';
      if (text.trim().isEmpty) return Toast.show('剪贴板为空!');
      final m = jsonDecode(text);
      if (m is! Map) throw const FormatException();
      setState(() {
        _name.text = '${m['name'] ?? ''}';
        _rule.text = '${m['rule'] ?? ''}';
      });
    } catch (e) {
      Toast.show('粘贴失败:$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('目录规则编辑'),
        actions: [
          if (!_locked) IconButton(tooltip: '保存', icon: const Icon(Icons.save), onPressed: _save),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: jsonEncode({'name': _name.text, 'rule': _rule.text})));
                Toast.show('规则已复制');
              } else {
                await _paste();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('拷贝规则')),
              PopupMenuItem(value: 'paste', child: Text('粘贴规则')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(key: const ValueKey('txt_name'), controller: _name, enabled: !_locked, decoration: const InputDecoration(labelText: '规则名称', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('txt_rule'),
            controller: _rule,
            enabled: !_locked,
            maxLines: 5,
            minLines: 2,
            decoration: const InputDecoration(labelText: '目录规则', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(controller: _sample, maxLines: 6, minLines: 3, decoration: const InputDecoration(labelText: '测试文本', border: OutlineInputBorder())),
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _test, child: const Text('测试'))),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_result != null) ...[
            Text('匹配到 ${_result!.length} 个章节'),
            for (final t in _result!) Text('· $t'),
          ],
        ],
      ),
    );
  }
}
