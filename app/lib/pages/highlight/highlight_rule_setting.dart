// pages/highlight/highlight_rule_setting.dart — the highlight-rule list "高亮规则" (original `_HighlightRuleSettingState`, 76 functions).
// Strings: 新建规则 · 本地导入 · 网络导入 · 扫码导入 · 搜索规则 · 全部分组 · 未分组 · 起效高亮 · 点击右上角添加规则开始使用 · json解析中 · 未解析到规则 ·
// 选择的规则为空 · 条规则 · 导入规则失败: · 解析规则错误 · 全选 ( · 反选 · 启用 · 停用 · 删除 · 删除确认 · 确定要删除《…》吗？ ·
// 确定要删除这些规则吗？ · 操作确认 · 置顶 · 置顶确认 · 确定要把《…》置顶吗？ · 请先选择规则!.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/highlight.dart';
import '../../models/highlight_rule.dart';
import '../../util/toast.dart';
import '../replace/rule_import.dart';
import '../source/source_setting.dart';
import 'highlight_rule_edit.dart';

class HighlightRuleSetting extends StatefulWidget {
  const HighlightRuleSetting({super.key});

  @override
  State<HighlightRuleSetting> createState() => _HighlightRuleSettingState();
}

class _HighlightRuleSettingState extends State<HighlightRuleSetting> {
  static const String allGroups = '全部分组';
  static const String noGroup = '未分组';

  List<HighlightRule> _rules = [];
  String _group = allGroups;
  String _query = '';
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    await HighlightData.load();
    if (mounted) setState(() => _rules = [...HighlightData.rules]);
  }

  List<String> get _groups => [allGroups, ...{for (final r in _rules) r.groupname.isEmpty ? noGroup : r.groupname}];

  List<HighlightRule> get _visible => _rules.where((r) {
        if (_group != allGroups && (r.groupname.isEmpty ? noGroup : r.groupname) != _group) return false;
        return _query.isEmpty || r.name.contains(_query) || r.pattern.contains(_query);
      }).toList();

  Future<void> _edit([HighlightRule? r]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => HighlightRuleEdit(rule: r)));
    if (saved == true) await _reload();
  }

  Future<void> _import(Future<String?> Function() source) async {
    final text = await source();
    if (text == null || text.trim().isEmpty) return;
    Toast.show('json解析中');
    try {
      final n = await Highlights.importJson(text);
      Toast.show(n == 0 ? '未解析到规则' : '$n 条规则');
    } catch (e) {
      Toast.show('导入规则失败:$e');
    }
    await _reload();
  }

  /// 导出规则 (the original's selection action): the selected rules as a JSON file in the import format.
  Future<void> _export() async {
    final list = [for (final r in _rules) if (_selected.contains(r.id)) r.toJson()];
    if (list.isEmpty) return Toast.show('请先选择规则!');
    try {
      await SourceImport.shareFile('shareHighlightRule.json', const JsonEncoder.withIndent('  ').convert(list));
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
  }

  Future<void> _batch(String action) async {
    if (_selected.isEmpty) return Toast.show('选择的规则为空');
    try {
      if (action == '删除') {
        if (!await RuleImport.confirm(context, '删除确认', '确定要删除这些规则吗？')) return;
        await Highlights.deleteMany(_selected);
      } else {
        if (!await RuleImport.confirm(context, '操作确认', '确定要$action这些规则吗？')) return;
        for (final id in _selected) {
          await Highlights.setEnabled(id, action == '启用');
        }
      }
      _selected.clear();
    } catch (e) {
      Toast.show('操作失败: $e');
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    final enabled = _rules.where((r) => r.isEnabled).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('高亮规则'),
        actions: [
          IconButton(tooltip: '新建规则', icon: const Icon(Icons.add), onPressed: _edit),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) {
              switch (v) {
                case 'local':
                  _import(RuleImport.pickFile);
                case 'net':
                  _import(() => RuleImport.fromNetwork(context));
                case 'scan':
                  RuleImport.fromScanner(context);
                default:
                  setState(() => _selecting = !_selecting);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'local', child: Text('本地导入')),
              PopupMenuItem(value: 'net', child: Text('网络导入')),
              PopupMenuItem(value: 'scan', child: Text('扫码导入')),
              PopupMenuItem(value: 'select', child: Text('多选')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(hintText: '搜索规则', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _groups.contains(_group) ? _group : allGroups,
              items: [for (final g in _groups) DropdownMenuItem(value: g, child: Text(g))],
              onChanged: (v) => setState(() => _group = v ?? allGroups),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(8), child: Text('起效高亮 $enabled 条规则')),
        Expanded(
          child: _rules.isEmpty
              ? const Center(child: Text('点击右上角添加规则开始使用'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final r = list[i];
                    return ListTile(
                      leading: _selecting
                          ? Checkbox(
                              value: _selected.contains(r.id),
                              onChanged: (v) => setState(() => v == true ? _selected.add(r.id) : _selected.remove(r.id)),
                            )
                          : null,
                      title: Text(r.name),
                      subtitle: Text(r.pattern, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _edit(r),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          value: r.isEnabled,
                          onChanged: (v) async {
                            await Highlights.setEnabled(r.id, v);
                            await _reload();
                          },
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'top') {
                              if (!await RuleImport.confirm(context, '置顶确认', '确定要把《${r.name}》置顶吗？')) return;
                              await Highlights.move(r.id, -1 << 20);
                            } else {
                              if (!await RuleImport.confirm(context, '删除确认', '确定要删除《${r.name}》吗？')) return;
                              await Highlights.delete(r.id);
                            }
                            await _reload();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'top', child: Text('置顶')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
      bottomNavigationBar: _selecting
          ? RuleBatchBar(
              selected: _selected.length,
              total: list.length,
              onSelectAll: () => setState(() => _selected.addAll(list.map((e) => e.id))),
              onInvert: () => setState(() {
                for (final r in list) {
                  if (!_selected.remove(r.id)) _selected.add(r.id);
                }
              }),
              actions: [
                TextButton(onPressed: () => _batch('启用'), child: const Text('启用')),
                TextButton(onPressed: () => _batch('停用'), child: const Text('停用')),
                TextButton(onPressed: () => _batch('删除'), child: const Text('删除')),
                TextButton(onPressed: _export, child: const Text('导出')),
              ],
            )
          : null,
    );
  }
}
