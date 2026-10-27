// pages/replace/replace_rule_setting.dart — the replace-rule list "替换净化" (original `_ReplaceRuleSettingState`, 70 functions).
// Strings: 新建规则 · 本地导入 · 网络导入 · 扫码导入 · 净化帮助 · 全部分组 · 未分组 · 搜索 · 还没有添加替换规则 · 点击右上角添加规则开始使用 ·
// 全选 ( · 反选 · 启用 · 停用 · 删除 · 删除确认 · 确定要删除《…》吗？ · 确定要删除这些规则吗？ · 操作确认 · 确定要 … 这些规则吗？ · 置顶 ·
// 置顶确认 · 确定要把《…》置顶吗？ · 测试 · 规则:  · 字符数变化:  · 净化过程中出错:  · 导入失败: · 已有 · 删除失败:  · 操作失败: .
import 'package:flutter/material.dart';

import '../../data/replace.dart';
import '../../models/replacerule.dart';
import '../../read/util/replace_rules.dart';
import '../../util/toast.dart';
import 'replace_rule_edit.dart';
import 'replace_rule_help.dart';
import 'rule_import.dart';

class ReplaceRuleSetting extends StatefulWidget {
  const ReplaceRuleSetting({super.key});

  @override
  State<ReplaceRuleSetting> createState() => _ReplaceRuleSettingState();
}

class _ReplaceRuleSettingState extends State<ReplaceRuleSetting> {
  static const String allGroups = '全部分组';
  static const String noGroup = '未分组';

  List<ReplaceRule> _rules = [];
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
    await ReplaceData.load();
    if (!mounted) return;
    setState(() => _rules = [...ReplaceData.rules]..sort((a, b) => a.ruleorder.compareTo(b.ruleorder)));
  }

  List<String> get _groups {
    final s = <String>{};
    for (final r in _rules) {
      s.add(r.groupname.isEmpty ? noGroup : r.groupname);
    }
    return [allGroups, ...s];
  }

  List<ReplaceRule> get _visible => _rules.where((r) {
        if (_group != allGroups && (r.groupname.isEmpty ? noGroup : r.groupname) != _group) return false;
        if (_query.isEmpty) return true;
        return r.name.contains(_query) || r.pattern.contains(_query);
      }).toList();

  Future<void> _edit([ReplaceRule? r]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReplaceRuleEdit(rule: r)));
    if (saved == true) await _reload();
  }

  Future<void> _import(Future<String?> Function() source) async {
    final text = await source();
    if (text == null || text.trim().isEmpty) return;
    try {
      final n = await Replaces.importJson(text);
      Toast.show(n == 0 ? '已有' : '导入成功! $n');
    } catch (e) {
      Toast.show('导入失败:$e');
    }
    await _reload();
  }

  Future<void> _delete(ReplaceRule r) async {
    if (!await RuleImport.confirm(context, '删除确认', '确定要删除《${r.name}》吗？')) return;
    try {
      await Replaces.delete(r.id);
    } catch (e) {
      Toast.show('删除失败: $e');
    }
    await _reload();
  }

  Future<void> _top(ReplaceRule r) async {
    if (!await RuleImport.confirm(context, '置顶确认', '确定要把《${r.name}》置顶吗？')) return;
    try {
      await Replaces.moveToTop(r.id);
    } catch (e) {
      Toast.show('置顶失败: $e');
    }
    await _reload();
  }

  Future<void> _batch(String action) async {
    if (_selected.isEmpty) return Toast.show('请先选择规则!');
    try {
      if (action == '删除') {
        if (!await RuleImport.confirm(context, '删除确认', '确定要删除这些规则吗？')) return;
        await Replaces.deleteMany(_selected);
      } else {
        if (!await RuleImport.confirm(context, '操作确认', '确定要$action这些规则吗？')) return;
        for (final id in _selected) {
          await Replaces.setEnabled(id, action == '启用');
        }
      }
      _selected.clear();
    } catch (e) {
      Toast.show('操作失败: $e');
    }
    await _reload();
  }

  Future<void> _test(ReplaceRule r) async {
    final input = TextEditingController();
    String? result;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('测试'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('规则: ${r.name}'),
              TextField(controller: input, maxLines: 4, minLines: 2, decoration: const InputDecoration(hintText: '正文')),
              if (result != null) ...[const SizedBox(height: 8), Text(result!)],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            TextButton(
              onPressed: () {
                try {
                  final copy = ReplaceRule.fromJson(r.toJson())..isEnabled = true;
                  final out = ReplaceRuleEngine.apply(input.text, [copy]);
                  set(() => result = '$out\n字符数变化: ${input.text.length} -> ${out.length}');
                } catch (e) {
                  set(() => result = '净化过程中出错: $e');
                }
              },
              child: const Text('测试'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('替换净化'),
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
                case 'select':
                  setState(() => _selecting = !_selecting);
                default:
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReplaceRuleHelp()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'local', child: Text('本地导入')),
              PopupMenuItem(value: 'net', child: Text('网络导入')),
              PopupMenuItem(value: 'scan', child: Text('扫码导入')),
              PopupMenuItem(value: 'select', child: Text('多选')),
              PopupMenuItem(value: 'help', child: Text('净化帮助')),
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
                decoration: const InputDecoration(hintText: '搜索', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
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
        Expanded(
          child: _rules.isEmpty
              ? const Center(child: Text('还没有添加替换规则\n点击右上角添加规则开始使用', textAlign: TextAlign.center))
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
                      title: Text(r.name.isEmpty ? r.pattern : r.name),
                      subtitle: Text(r.groupname.isEmpty ? noGroup : r.groupname),
                      onTap: () => _edit(r),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          value: r.isEnabled,
                          onChanged: (v) async {
                            await Replaces.setEnabled(r.id, v);
                            await _reload();
                          },
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) => switch (v) { 'top' => _top(r), 'test' => _test(r), _ => _delete(r) },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'top', child: Text('置顶')),
                            PopupMenuItem(value: 'test', child: Text('测试')),
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
              ],
            )
          : null,
    );
  }
}
