// pages/txtrule/txt_rule_setting.dart — "目录规则管理" (original `_TxtRuleSettingState` 0x61c5b0: 恢复默认 · 本地导入 · 网络导入; list 0x61cc30:
// 导入 · 删除 · 更多 · 全选 ( · 反选; delete 0xfe1b90: 删除确认 / 确定要删除《…》吗？ / 无法删除保留内容 / 删除失败: ; batch 0xfedb00: 操作确认 /
// 确定要 启用|停用 这些规则吗？; import 0xfef0bc / 0xfef4e0: 导入成功! / 恢复失败: / 导入失败: / 选择文件失败:).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/txtrule.dart';
import '../../models/txt_toc_rule.dart';
import '../../util/toast.dart';
import '../replace/rule_import.dart';
import '../source/source_setting.dart';
import 'txt_rule_edit.dart';

class TxtRuleSetting extends StatefulWidget {
  const TxtRuleSetting({super.key});

  @override
  State<TxtRuleSetting> createState() => _TxtRuleSettingState();
}

class _TxtRuleSettingState extends State<TxtRuleSetting> {
  List<TxtTocRule> _rules = [];
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    await Txtruledata.load();
    if (mounted) setState(() => _rules = [...Txtruledata.rules]);
  }

  Future<void> _edit([TxtTocRule? r]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => TxtRuleEdit(rule: r)));
    if (saved == true) await _reload();
  }

  Future<void> _import(Future<String?> Function() source) async {
    final text = await source();
    if (text == null || text.trim().isEmpty) return;
    try {
      await Txtrule.importJson(text);
      Toast.show('导入成功!');
    } catch (e) {
      Toast.show('导入失败:$e');
    }
    await _reload();
  }

  Future<void> _delete(TxtTocRule r) async {
    if (!r.candel) return Toast.show('无法删除保留内容');
    if (!await RuleImport.confirm(context, '删除确认', '确定要删除《${r.name}》吗？')) return;
    try {
      await Txtrule.delete(r.name);
    } catch (e) {
      Toast.show('删除失败: $e');
    }
    await _reload();
  }

  /// 导出规则 (the original's selection action): the selected rules as a JSON file in the import format.
  Future<void> _export() async {
    final list = [for (final r in _rules) if (_selected.contains(r.name)) r.toJson()];
    if (list.isEmpty) return Toast.show('请先选择规则!');
    try {
      await SourceImport.shareFile('shareTxtTocRule.json', const JsonEncoder.withIndent('  ').convert(list));
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
  }

  Future<void> _batch(String action) async {
    if (_selected.isEmpty) return Toast.show('请先选择规则!');
    try {
      if (action == '删除') {
        if (!await RuleImport.confirm(context, '删除确认', '确定要删除这些规则吗？')) return;
        for (final n in _selected) {
          await Txtrule.delete(n);
        }
      } else {
        if (!await RuleImport.confirm(context, '操作确认', '确定要$action这些规则吗？')) return;
        for (final n in _selected) {
          await Txtrule.setEnabled(n, action == '启用');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('目录规则管理'),
        actions: [
          IconButton(tooltip: '新建规则', icon: const Icon(Icons.add), onPressed: _edit),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) async {
              switch (v) {
                case 'reset':
                  try {
                    await Txtrule.reset();
                  } catch (e) {
                    Toast.show('恢复失败:$e');
                  }
                  await _reload();
                case 'local':
                  await _import(RuleImport.pickFile);
                case 'net':
                  await _import(() => RuleImport.fromNetwork(context));
                default:
                  setState(() => _selecting = !_selecting);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('恢复默认')),
              PopupMenuItem(value: 'local', child: Text('本地导入')),
              PopupMenuItem(value: 'net', child: Text('网络导入')),
              PopupMenuItem(value: 'select', child: Text('多选')),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _rules.length,
        itemBuilder: (context, i) {
          final r = _rules[i];
          return ListTile(
            leading: _selecting
                ? Checkbox(
                    value: _selected.contains(r.name),
                    onChanged: (v) => setState(() => v == true ? _selected.add(r.name) : _selected.remove(r.name)),
                  )
                : null,
            title: Text(r.name),
            subtitle: Text(r.rule, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _edit(r),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: r.isEnabled,
                onChanged: (v) async {
                  await Txtrule.setEnabled(r.name, v);
                  await _reload();
                },
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'top') {
                    await Txtrule.moveToTop(r.name);
                    await _reload();
                  } else {
                    await _delete(r);
                  }
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
      bottomNavigationBar: _selecting
          ? RuleBatchBar(
              selected: _selected.length,
              total: _rules.length,
              onSelectAll: () => setState(() => _selected.addAll(_rules.map((e) => e.name))),
              onInvert: () => setState(() {
                for (final r in _rules) {
                  if (!_selected.remove(r.name)) _selected.add(r.name);
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
