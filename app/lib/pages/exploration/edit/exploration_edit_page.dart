// pages/exploration/edit/exploration_edit_page.dart — 探索编辑 (`ExplorationEditPage`, `_EditComponentSheet`).
//
// Templates: 「模版列表」 (switch / 「新模版」 / rename 「模版名称」 「输入模版名称...」 / delete 「确定要删除这个模版吗？」 「确认删除」,
// 「至少需要保留一个模版」, 「请选择一个模版」). Components: 「组件列表」 「n 个组件」, 「暂无组件」 「点击下方按钮添加组件来构建你的探索页面」,
// 「添加组件」 → 「选择组件」 (7 types), up / down (`arrow.up` / `arrow.down`), 编辑 / 删除. The component sheet (「配置」): 标题
// (「请填写标题」), 书源 (「请选择书源」), 发现项 (「点击选择发现」, 「请选择发现项」, 「请选择正确的发现」), for 多分类排行榜 several
// categories (「多分类排行榜至少选择2个分类」, 「已存在该分类」, 「编辑分类名称」), 数量. Cloud: 「备份到云端」 (item
// `exploration_templates_backup`: 「没有可备份的模版」, 「已备份 n 个模版到云端」, 「备份失败: 」) and 「从云端恢复」 (「云端没有找到备份」,
// 「云端备份为空」, 「云端有 n 个模版，当前本地模版将被覆盖，确定继续？」 「恢复云端备份」, 「已从云端恢复 n 个模版」, 「恢复失败: 」).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../api/userapi.dart';
import '../../../data/exploration.dart';
import '../../../data/list_store.dart' show newId;
import '../../../data/source.dart';
import '../../../models/explore.dart';
import '../../../models/exploration_template.dart';
import '../../../models/source.dart';
import '../../../util/toast.dart';
import '../../../widget/base_page.dart';
import '../../../widget/exploration/exploration_component.dart';
import '../../search/book_search_service.dart';
import '../exploration_page.dart';

class ExplorationEditPage extends StatefulWidget {
  const ExplorationEditPage({super.key});

  @override
  State<ExplorationEditPage> createState() => _ExplorationEditPageState();
}

class _ExplorationEditPageState extends BasePage<ExplorationEditPage> {
  ExplorationTemplate? _t;
  List<ExplorationComponent> _comps = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? select}) async {
    await ExplorationData.load();
    if (ExplorationData.templates.isEmpty) {
      final t = await Exploration.create('默认');
      await Exploration.setActive(t.id);
    }
    final id = select ?? _t?.id ?? ExplorationData.active?.id;
    final t = ExplorationData.templates.where((x) => x.id == id).firstOrNull ?? ExplorationData.templates.first;
    update(() {
      _t = t;
      _comps = componentsOf(t);
    });
  }

  Future<void> _save() async {
    final t = _t;
    if (t == null) return;
    for (var i = 0; i < _comps.length; i++) {
      _comps[i].order = i;
    }
    t.components = [for (final c in _comps) c.toJson()];
    await Exploration.update(t);
    await _load(select: t.id);
  }

  Future<void> _templates() async {
    final v = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('模版列表'), children: [
        for (final t in ExplorationData.templates) ChoiceOption<String>(value: t.id, current: _t?.id ?? '', title: t.name),
        SimpleDialogOption(onPressed: () => Navigator.of(c).pop('+'), child: const Text('新模版', style: TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
    if (v == null) return;
    if (v == '+') {
      final name = await input('模版名称', hint: '输入模版名称...');
      if (name == null || name.trim().isEmpty) return;
      final t = await Exploration.create(name.trim());
      await Exploration.setActive(t.id);
      await _load(select: t.id);
    } else {
      await Exploration.setActive(v);
      await _load(select: v);
    }
  }

  Future<void> _rename() async {
    final t = _t;
    if (t == null) return;
    final name = await input('模版名称', initial: t.name, hint: '输入模版名称...');
    if (name == null || name.trim().isEmpty) return;
    t.name = name.trim();
    await _save();
  }

  Future<void> _deleteTemplate() async {
    if (ExplorationData.templates.length <= 1) {
      Toast.show('至少需要保留一个模版');
      return;
    }
    if (!await confirm('确认删除', '确定要删除这个模版吗？')) return;
    await Exploration.delete(_t!.id);
    _t = null;
    await _load();
  }

  Future<void> _addComponent() async {
    final type = await showDialog<ComponentType>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('选择组件'), children: [
        for (final t in ComponentType.values) SimpleDialogOption(key: Key('ctype_${t.name}'), onPressed: () => Navigator.of(c).pop(t), child: Text(t.label)),
      ]),
    );
    if (type == null || !mounted) return;
    final comp = ExplorationComponent(id: newId(), type_: type.name, config: {'title': type.label, 'count': type.defaultCount}, order: _comps.length);
    final edited = await _EditComponentSheet.show(context, comp);
    if (edited == null) return;
    _comps.add(edited);
    await _save();
  }

  Future<void> _edit(int i) async {
    final edited = await _EditComponentSheet.show(context, ExplorationComponent.fromJson(_comps[i].toJson()));
    if (edited == null) return;
    _comps[i] = edited;
    await _save();
  }

  Future<void> _move(int i, int d) async {
    final j = i + d;
    if (j < 0 || j >= _comps.length) return;
    final c = _comps.removeAt(i);
    _comps.insert(j, c);
    await _save();
  }

  Future<void> _backup() async {
    await ExplorationData.load();
    if (ExplorationData.templates.isEmpty) {
      Toast.show('没有可备份的模版');
      return;
    }
    try {
      await UserApi.setItemJsonFile(ExplorationData.cloudItem, Exploration.exportJson());
      Toast.show('已备份 ${ExplorationData.templates.length} 个模版到云端');
    } catch (e) {
      Toast.show('备份失败: $e', iserror: true);
    }
  }

  Future<void> _restore() async {
    try {
      final text = await UserApi.getItemJson(ExplorationData.cloudItem);
      if (text.trim().isEmpty) {
        Toast.show('云端没有找到备份');
        return;
      }
      final list = jsonDecode(text);
      if (list is! List || list.isEmpty) {
        Toast.show('云端备份为空');
        return;
      }
      if (!await confirm('恢复云端备份', '云端有 ${list.length} 个模版，当前本地模版将被覆盖，确定继续？')) return;
      final n = await Exploration.importJson(text);
      _t = null;
      await _load();
      Toast.show('已从云端恢复 $n 个模版');
    } catch (e) {
      Toast.show('恢复失败: $e', iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(
        title: const Text('探索编辑'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'backup' ? _backup() : _restore(),
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'backup', child: Text('备份到云端')),
              PopupMenuItem(value: 'restore', child: Text('从云端恢复')),
            ],
          ),
        ],
      ),
      body: t == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              ListTile(
                key: const Key('tpl_switch'),
                leading: const Icon(Icons.view_list_outlined),
                title: Text(t.name),
                subtitle: const Text('模版列表'),
                onTap: _templates,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: '编辑', icon: const Icon(Icons.edit_outlined), onPressed: _rename),
                  IconButton(tooltip: '删除', icon: const Icon(Icons.delete_outline), onPressed: _deleteTemplate),
                ]),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(children: [const Text('组件列表', style: TextStyle(fontWeight: FontWeight.w600)), const Spacer(), Text('${_comps.length} 个组件')]),
              ),
              Expanded(
                child: _comps.isEmpty
                    ? const Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('暂无组件'),
                          SizedBox(height: 6),
                          Text('点击下方按钮添加组件来构建你的探索页面', style: TextStyle(color: Colors.grey)),
                        ]),
                      )
                    : ListView.builder(
                        itemCount: _comps.length,
                        itemBuilder: (c, i) {
                          final comp = _comps[i];
                          final cfg = ComponentConfig(comp.config);
                          return ListTile(
                            key: Key('comp_row_$i'),
                            title: Text(cfg.title.isEmpty ? typeOf(comp).label : cfg.title),
                            subtitle: Text('${typeOf(comp).label} · ${cfg.source?.bookSourceName ?? '请选择书源'}'),
                            onTap: () => _edit(i),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(icon: const Icon(Icons.arrow_upward, size: 20), onPressed: i == 0 ? null : () => _move(i, -1)),
                              IconButton(icon: const Icon(Icons.arrow_downward, size: 20), onPressed: i == _comps.length - 1 ? null : () => _move(i, 1)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () async {
                                  _comps.removeAt(i);
                                  await _save();
                                },
                              ),
                            ]),
                          );
                        },
                      ),
              ),
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(key: const Key('comp_add'), onPressed: t == null ? null : _addComponent, icon: const Icon(Icons.add), label: const Text('添加组件')),
        ),
      ),
    );
  }
}

/// 「配置」 sheet of one component.
class _EditComponentSheet extends StatefulWidget {
  final ExplorationComponent component;
  const _EditComponentSheet(this.component);

  static Future<ExplorationComponent?> show(BuildContext context, ExplorationComponent c) =>
      showModalBottomSheet<ExplorationComponent>(context: context, isScrollControlled: true, builder: (_) => _EditComponentSheet(c));

  @override
  State<_EditComponentSheet> createState() => _EditComponentSheetState();
}

class _EditComponentSheetState extends BasePage<_EditComponentSheet> {
  late final Map<String, dynamic> _cfg = Map<String, dynamic>.from(widget.component.config);
  late final _title = TextEditingController(text: '${_cfg['title'] ?? ''}');
  late final _count = TextEditingController(text: '${_cfg['count'] ?? ''}');
  List<Explore>? _kinds;

  ComponentType get _type => typeOf(widget.component);
  bool get _multi => _type == ComponentType.multiCategoryRanking;

  @override
  void dispose() {
    _title.dispose();
    _count.dispose();
    super.dispose();
  }

  Source? get _source => Sourcedata.sourceByUrl('${_cfg['bookSourceUrl'] ?? ''}');

  Future<void> _chooseSource() async {
    await Sourcedata.load();
    if (!mounted) return;
    final list = [for (final m in Sourcedata.exploreRaw) Source.fromJson(m)];
    final s = await showDialog<Source>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('书源'), children: [
        for (final s in list) SimpleDialogOption(onPressed: () => Navigator.of(c).pop(s), child: Text(s.bookSourceName)),
      ]),
    );
    if (s == null) return;
    update(() {
      _cfg['bookSourceUrl'] = s.bookSourceUrl;
      _cfg['isQRead'] = s.isqread;
      _cfg.remove('exploreUrl');
      _cfg.remove('categories');
      _kinds = null;
    });
  }

  Future<Explore?> _chooseKind() async {
    final s = _source;
    if (s == null) {
      Toast.show('请选择书源');
      return null;
    }
    try {
      _kinds ??= await BookSearchService.instance.exploreKinds(s);
    } catch (e) {
      Toast.show('搜索错误: $e', iserror: true);
      return null;
    }
    if (!mounted) return null;
    final list = _kinds!.where((k) => k.url.trim().isNotEmpty).toList();
    return showDialog<Explore>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('发现项'), children: [
        for (final k in list) SimpleDialogOption(onPressed: () => Navigator.of(c).pop(k), child: Text(k.title)),
      ]),
    );
  }

  List<Map<String, String>> get _cats => ComponentConfig(_cfg).categories;

  Future<void> _addCategory() async {
    final k = await _chooseKind();
    if (k == null) return;
    final cats = _cats;
    if (cats.any((c) => c['exploreUrl'] == k.url)) {
      Toast.show('已存在该分类');
      return;
    }
    update(() => _cfg['categories'] = [...cats, {'title': k.title, 'exploreUrl': k.url}]);
  }

  Future<void> _renameCategory(int i) async {
    final cats = _cats;
    final name = await input('编辑分类名称', initial: cats[i]['title']!);
    if (name == null || name.trim().isEmpty) return;
    cats[i]['title'] = name.trim();
    update(() => _cfg['categories'] = cats);
  }

  void _done() {
    if (_title.text.trim().isEmpty) {
      Toast.show('请填写标题');
      return;
    }
    if (_source == null) {
      Toast.show('请选择书源');
      return;
    }
    if (_multi) {
      if (_cats.length < 2) {
        Toast.show('多分类排行榜至少选择2个分类');
        return;
      }
    } else if ('${_cfg['exploreUrl'] ?? ''}'.isEmpty) {
      Toast.show('请选择发现项');
      return;
    }
    _cfg['title'] = _title.text.trim();
    final n = int.tryParse(_count.text.trim());
    if (n != null && n > 0) _cfg[_multi ? 'countPerCategory' : 'count'] = n;
    Navigator.of(context).pop(ExplorationComponent.fromJson(widget.component.toJson())..config = _cfg);
  }

  @override
  Widget build(BuildContext context) {
    final s = _source;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('配置 · ${_type.label}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            TextField(key: const Key('comp_title'), controller: _title, decoration: const InputDecoration(labelText: '标题')),
            ListTile(
              key: const Key('comp_source'),
              contentPadding: EdgeInsets.zero,
              title: const Text('书源'),
              trailing: Text(s?.bookSourceName ?? '请选择书源'),
              onTap: _chooseSource,
            ),
            if (!_multi)
              ListTile(
                key: const Key('comp_kind'),
                contentPadding: EdgeInsets.zero,
                title: const Text('发现项'),
                trailing: Text('${_cfg['exploreTitle'] ?? ''}'.isNotEmpty ? '${_cfg['exploreTitle']}' : ('${_cfg['exploreUrl'] ?? ''}'.isEmpty ? '点击选择发现' : '默认')),
                onTap: () async {
                  final k = await _chooseKind();
                  if (k != null) {
                    update(() {
                      _cfg['exploreUrl'] = k.url;
                      _cfg['exploreTitle'] = k.title;
                    });
                  }
                },
              )
            else ...[
              for (var i = 0; i < _cats.length; i++)
                ListTile(
                  dense: true,
                  title: Text(_cats[i]['title']!),
                  onTap: () => _renameCategory(i),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => update(() => _cfg['categories'] = [..._cats]..removeAt(i)),
                  ),
                ),
              TextButton.icon(onPressed: _addCategory, icon: const Icon(Icons.add), label: const Text('点击选择发现')),
            ],
            TextField(controller: _count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '数量')),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(key: const Key('comp_save'), onPressed: _done, child: const Text('保存'))),
            ]),
          ]),
        ),
      ),
    );
  }
}
