// pages/rss/rss_setting.dart — `RssSettingPage`: the RSS-source manager (RSS设置, `rsssetting`; opened by 编辑订阅源 of the 订阅 tab), also
// the selection list of an RSS import (`已有` / `新增`). Same structure as the book-source manager: group filter (`全部分组`, `未分组`,
// groups), search, list with checkbox / switch / edit / item menu (open / login / setVariable / debug / top / bottomSource / del),
// bottom bar `全选 (n/m)` / `反选` / `删除` / `更多`, import (local / url / clipboard / scan), export.
//
// Original `_RssSettingPageState` (117 functions; strings `置顶确认` / `确定要置顶这些订阅源吗？` / `置顶成功` / `置底…`, `删除确认`,
// `选择您想要导入的书源文件`, `请选择解析类型` (run mode of an import when a backend is bound), `是否要清理服务器端全部cookie？`,
// backend calls `/getRssSourcejson`, `/delRssSource(s)`, `/stopRssSource`; import flow 0xe713b0 `导入订阅源失败:`).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/rss.dart';
import '../../data/source.dart' show SourceImportResult;
import '../../qread/api/rssapi.dart';
import '../../qread/qread.dart';
import '../../qread/rssdata.dart';
import '../../util/toast.dart';
import '../../util/webbook/model/rss_source.dart';
import '../source/login_dialog.dart';
import '../source/source_setting.dart' show SourceImport;
import 'debug.dart';
import 'edit.dart';
import 'open.dart';

const String rssAllGroups = '全部分组';
const String rssNoGroup = '未分组';

abstract class RssImport {
  /// RSS maps in [text]; entries without url or name are dropped. Throws [FormatException].
  static List<Map<String, dynamic>> parse(String text) {
    final v = jsonDecode(text.trim());
    final items = v is List ? v : [v];
    return [
      for (final e in items)
        if (e is Map && '${e['sourceUrl'] ?? ''}'.trim().isNotEmpty && '${e['sourceName'] ?? ''}'.trim().isNotEmpty) Map<String, dynamic>.from(e)
    ];
  }

  /// 0xe713b0: like the book-source import (preview list, run mode when a backend is bound).
  static Future<SourceImportResult?> importText(BuildContext context, String text, {bool preview = true}) async {
    try {
      var t = text.trim();
      if (t.startsWith('http://') || t.startsWith('https://')) t = await SourceImport.download(t);
      final maps = parse(t);
      if (maps.isEmpty) {
        Toast.show('未解析到订阅源');
        return null;
      }
      var chosen = maps;
      if (preview) {
        if (!context.mounted) return null;
        final r = await Navigator.of(context).push<List<Map<String, dynamic>>>(MaterialPageRoute(builder: (c) => RssSettingPage(importList: maps)));
        if (r == null) return null;
        if (r.isEmpty) {
          Toast.show('选择的订阅源为空');
          return null;
        }
        chosen = r;
      }
      if (Qread.isbind && context.mounted) {
        final mode = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('请选择解析类型'),
            content: const Text('您导入的订阅源为开源阅读专有格式，请选择运行方式！'),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop('qread'), child: const Text('轻阅读解析')),
              TextButton(onPressed: () => Navigator.of(c).pop('local'), child: const Text('兼容层解析')),
            ],
          ),
        );
        if (mode == null) return null;
        if (mode == 'qread') {
          if (!Qread.requireEdit()) return null;
          await RssApi.saveAll(chosen);
          await QRssSources.refresh();
          Toast.show('轻阅读新增${chosen.length}条订阅源');
          return SourceImportResult(chosen.length, 0, 0);
        }
      }
      final r = await RssSources.addAll(chosen);
      Toast.show('轻悦时光新增${r.added}条订阅源，更新${r.updated}条订阅源');
      return r;
    } catch (e) {
      Toast.show('导入订阅源失败:$e', iserror: true);
      return null;
    }
  }
}

class _RItem {
  final Map<String, dynamic> raw;
  _RItem(this.raw);
  String get url => '${raw['sourceUrl'] ?? ''}';
  String get name => '${raw['sourceName'] ?? ''}';
  String get group => '${raw['sourceGroup'] ?? ''}';
  bool get remote => raw['isqread'] == true || '${raw['isqread']}' == 'true';
  bool get enabled => raw['enabled'] == null || raw['enabled'] == true || '${raw['enabled']}' == 'true';
}

class RssSettingPage extends StatefulWidget {
  final List<Map<String, dynamic>>? importList;
  const RssSettingPage({super.key, this.importList});

  @override
  State<RssSettingPage> createState() => _RssSettingPageState();
}

class _RssSettingPageState extends State<RssSettingPage> {
  final _search = TextEditingController();
  List<_RItem> _items = [];
  final Set<String> _selected = {};
  String _group = rssAllGroups;
  bool _loading = true;

  bool get _importing => widget.importList != null;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await Rssdata.load();
    if (_importing) {
      setState(() {
        _items = [for (final m in widget.importList!) _RItem(m)];
        _selected.addAll(_items.map((e) => e.url));
        _loading = false;
      });
      return;
    }
    final remote = <Map<String, dynamic>>[];
    if (Qread.isbind) {
      for (final s in await QRssSources.load()) {
        remote.add({...s.toJson(), 'isqread': true});
      }
    }
    if (!mounted) return;
    setState(() {
      _items = [for (final m in Rssdata.raw) _RItem(m), for (final m in remote) _RItem(m)];
      _selected.removeWhere((u) => !_items.any((e) => e.url == u));
      _loading = false;
    });
  }

  List<String> get _groups {
    final set = <String>{};
    for (final i in _items) {
      for (final g in i.group.split(',')) {
        if (g.trim().isNotEmpty) set.add(g.trim());
      }
    }
    return [rssAllGroups, rssNoGroup, ...(set.toList()..sort())];
  }

  List<_RItem> get _shown {
    final q = _search.text.trim().toLowerCase();
    return _items.where((i) {
      final ok = _group == rssAllGroups || (_group == rssNoGroup ? i.group.trim().isEmpty : i.group.split(',').map((e) => e.trim()).contains(_group));
      return ok && (q.isEmpty || i.name.toLowerCase().contains(q) || i.url.toLowerCase().contains(q) || i.group.toLowerCase().contains(q));
    }).toList();
  }

  List<_RItem> get _chosen => _items.where((i) => _selected.contains(i.url)).toList();

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
            TextButton(key: const Key('confirm_ok'), onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
          ],
        ),
      ) ==
      true;

  Future<void> _setEnabled(List<_RItem> items, bool on) async {
    try {
      final local = [for (final i in items) if (!i.remote) i.url];
      final remote = [for (final i in items) if (i.remote) i.url];
      if (local.isNotEmpty) await RssSources.setEnabled(local, on);
      if (remote.isNotEmpty) {
        await RssApi.setEnabled(remote, on);
        await QRssSources.refresh();
      }
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
    await _reload();
  }

  Future<void> _move(List<String> urls, bool top) async {
    final set = urls.toSet();
    await Rssdata.store.run((list) {
      final moved = [for (final e in list) if (set.contains('${e['sourceUrl']}')) e];
      list.removeWhere((e) => set.contains('${e['sourceUrl']}'));
      top ? list.insertAll(0, moved) : list.addAll(moved);
    });
    await _reload();
  }

  Future<void> _delete(List<_RItem> items) async {
    try {
      final local = [for (final i in items) if (!i.remote) i.url];
      final remote = [for (final i in items) if (i.remote) i.url];
      if (local.isNotEmpty) await RssSources.delete(local);
      if (remote.isNotEmpty) {
        if (!Qread.requireEdit()) return;
        await RssApi.delete(remote);
        await QRssSources.refresh();
      }
      _selected.removeAll(items.map((e) => e.url));
      Toast.show('删除成功');
    } catch (e) {
      Toast.show('删除失败: $e', iserror: true);
    }
    await _reload();
  }

  Future<void> _edit(Map<String, dynamic>? raw, {bool remote = false}) async {
    if ((remote || (raw != null && _RItem(raw).remote)) && !Qread.requireEdit()) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (c) => EditRssSourcePage(source: raw, remote: remote)));
    await _reload();
  }

  Future<void> _onItemMenu(_RItem i, String v) async {
    switch (v) {
      case 'open':
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => RssOpen(source: i.raw)));
      case 'login':
        await showSourceLogin(context, RssSource.fromJson(i.raw));
      case 'setVariable':
        if (i.remote) {
          final cur = await RssApi.getVariable(i.url).catchError((_) => '');
          if (mounted) await showSourceVariableDialog(context, RssSource.fromJson(i.raw), current: cur, onSave: (t) => RssApi.setVariable(i.url, t));
        } else {
          await showSourceVariableDialog(context, RssSource.fromJson(i.raw));
        }
      case 'debug':
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => DebugRssPage(source: i.raw)));
      case 'top':
      case 'bottomSource':
        final top = v == 'top';
        if (!await _confirm(top ? '置顶确认' : '置底确认', '确定要把《${i.name}》${top ? '置顶' : '置底'}吗？')) return;
        try {
          await _move([i.url], top);
          Toast.show(top ? '置顶成功' : '置底成功');
        } catch (e) {
          Toast.show('${top ? '置顶' : '置底'}失败: $e');
        }
      case 'del':
        if (await _confirm('删除确认', '确定要删除《${i.name}》吗？')) await _delete([i]);
    }
  }

  Future<String?> _askText(String title) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(key: const Key('ask_text'), controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'https://')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(key: const Key('ask_ok'), onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('确定')),
        ],
      ),
    );
  }

  Future<void> _onSelected(String v) async {
    switch (v) {
      case 'add':
        await _edit(null);
      case 'addremote':
        await _edit(null, remote: true);
      case 'addsource':
        try {
          final t = await SourceImport.pickFileText();
          if (t != null && mounted) await RssImport.importText(context, t);
        } catch (e) {
          Toast.show('选择文件失败:$e', iserror: true);
        }
      case 'urladd':
        final u = await _askText('网络导入');
        if (u != null && u.trim().isNotEmpty && mounted) await RssImport.importText(context, u);
      case 'clipboard':
        final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        if (t.trim().isEmpty) {
          Toast.show('剪贴板为空!');
        } else if (mounted) {
          await RssImport.importText(context, t);
        }
      case 'maadd':
        final u = await SourceImport.scan(context);
        if (u != null && u.startsWith('http') && mounted) await RssImport.importText(context, u);
      case 'exportall':
        await _export(_items);
      case 'refresh':
        if (Qread.isbind) {
          try {
            await QRssSources.refresh();
          } catch (e) {
            Toast.show('获取订阅源出错:$e', iserror: true);
          }
        }
    }
    await _reload();
  }

  Future<void> _export(List<_RItem> items) async {
    final local = items.where((i) => !i.remote).map((e) => e.url).toList();
    if (local.isEmpty) {
      Toast.show('请先选择规则!');
      return;
    }
    try {
      await SourceImport.shareFile('shareRssSource.json', await RssSources.exportJson(urls: local));
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
  }

  Future<void> _editGroup(bool remove) async {
    final c = TextEditingController();
    final names = remove ? {for (final i in _chosen) ...i.group.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)}.toList() : _groups.skip(2).toList();
    final g = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(remove ? '移除分组' : '选择或输入分组'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final n in names) ListTile(dense: true, title: Text(n), onTap: () => Navigator.of(ctx).pop(n)),
              if (!remove) TextField(key: const Key('group_input'), controller: c, decoration: const InputDecoration(labelText: '输入新分组', border: OutlineInputBorder())),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          if (!remove) TextButton(key: const Key('group_ok'), onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (g == null || g.isEmpty) return;
    final local = [for (final i in _chosen) if (!i.remote) i.url];
    final remote = [for (final i in _chosen) if (i.remote) i.url];
    try {
      if (local.isNotEmpty) await (remove ? RssSources.removeGroup(local, g) : RssSources.addGroup(local, g));
      if (remote.isNotEmpty) {
        await RssApi.editGroup(remote, g, st: remove ? 0 : 1);
        await QRssSources.refresh();
      }
      Toast.show('操作成功');
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
    await _reload();
  }

  Future<void> _showMoreActions() async {
    if (_selected.isEmpty) {
      Toast.show('请先选择规则!');
      return;
    }
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final a in const [
              ('enable', '启用所选'),
              ('disable', '禁用所选'),
              ('addGroup', '加入分组'),
              ('removeGroup', '移除分组'),
              ('top', '置顶所选'),
              ('bottom', '置底所选'),
              ('export', '导出所选'),
            ])
              ListTile(key: Key('more_${a.$1}'), title: Text(a.$2), onTap: () => Navigator.of(c).pop(a.$1)),
          ]),
        ),
      ),
    );
    final items = _chosen;
    switch (v) {
      case 'enable':
        await _setEnabled(items, true);
      case 'disable':
        await _setEnabled(items, false);
      case 'addGroup':
        await _editGroup(false);
      case 'removeGroup':
        await _editGroup(true);
      case 'top':
      case 'bottom':
        final top = v == 'top';
        if (!await _confirm(top ? '置顶确认' : '置底确认', '确定要${top ? '置顶' : '置底'}这些订阅源吗？')) return;
        try {
          await _move([for (final i in items) if (!i.remote) i.url], top);
          Toast.show(top ? '置顶成功' : '置底成功');
        } catch (e) {
          Toast.show('${top ? '置顶' : '置底'}失败: $e');
        }
      case 'export':
        await _export(items);
    }
  }

  Widget _tile(_RItem i) {
    final cs = Theme.of(context).colorScheme;
    final exists = _importing && Rssdata.byUrl(i.url) != null;
    return InkWell(
      key: ValueKey('rss_${i.url}'),
      onTap: () => setState(() => _selected.contains(i.url) ? _selected.remove(i.url) : _selected.add(i.url)),
      child: Row(children: [
        Checkbox(value: _selected.contains(i.url), onChanged: (v) => setState(() => v == true ? _selected.add(i.url) : _selected.remove(i.url))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i.remote ? '📶' : ''}${i.name}${i.group.trim().isEmpty ? '' : ' [${i.group}]'}', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(i.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.outline)),
          ]),
        ),
        if (_importing)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(exists ? '已有' : '新增', style: TextStyle(color: exists ? cs.outline : cs.primary)))
        else ...[
          Switch(key: Key('rss_enable_${i.url}'), value: i.enabled, onChanged: (v) => _setEnabled([i], v)),
          IconButton(tooltip: '编辑', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(i.raw)),
          PopupMenuButton<String>(
            key: Key('rss_menu_${i.url}'),
            onSelected: (v) => _onItemMenu(i, v),
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'open', child: Text('打开')),
              if (!i.remote) const PopupMenuItem(value: 'top', child: Text('置顶')),
              if (!i.remote) const PopupMenuItem(value: 'bottomSource', child: Text('置底')),
              if ('${i.raw['loginUrl'] ?? ''}'.trim().isNotEmpty) const PopupMenuItem(value: 'login', child: Text('登录')),
              const PopupMenuItem(value: 'setVariable', child: Text('设置源变量')),
              const PopupMenuItem(value: 'debug', child: Text('调试')),
              const PopupMenuItem(value: 'del', child: Text('删除')),
            ],
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final cs = Theme.of(context).colorScheme;
    final allSel = shown.isNotEmpty && shown.every((i) => _selected.contains(i.url));
    return Scaffold(
      appBar: AppBar(
        title: Text(_importing ? '导入' : '订阅源管理'),
        actions: _importing
            ? null
            : [
                PopupMenuButton<String>(
                  tooltip: '分组列表',
                  icon: const Icon(Icons.folder_outlined),
                  onSelected: (g) => setState(() => _group = g),
                  itemBuilder: (c) => [
                    for (final g in _groups)
                      PopupMenuItem(value: g, child: Row(children: [Icon(g == _group ? Icons.check_circle : Icons.circle_outlined, size: 18), const SizedBox(width: 8), Text(g)])),
                  ],
                ),
                PopupMenuButton<String>(
                  key: const Key('rss_setting_menu'),
                  tooltip: '更多',
                  onSelected: _onSelected,
                  itemBuilder: (c) => [
                    const PopupMenuItem(value: 'add', child: Text('新建订阅源')),
                    if (Qread.isbind) const PopupMenuItem(value: 'addremote', child: Text('新建后端订阅源')),
                    const PopupMenuItem(value: 'addsource', child: Text('本地导入')),
                    const PopupMenuItem(value: 'urladd', child: Text('网络导入')),
                    const PopupMenuItem(value: 'clipboard', child: Text('剪贴板导入')),
                    const PopupMenuItem(value: 'maadd', child: Text('扫码导入')),
                    const PopupMenuItem(value: 'exportall', child: Text('导出订阅源')),
                    const PopupMenuItem(value: 'refresh', child: Text('刷新')),
                  ],
                ),
              ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '搜索订阅源',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(child: TextButton(onPressed: () => _edit(null), child: const Text('还没有订阅源，点击新建')))
                    : ListView.builder(itemCount: shown.length, itemBuilder: (c, i) => _tile(shown[i])),
          ),
        ]),
      ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : Material(
              elevation: 6,
              color: cs.surfaceContainer,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    TextButton(
                      onPressed: () => setState(() => allSel ? _selected.removeAll(shown.map((e) => e.url)) : _selected.addAll(shown.map((e) => e.url))),
                      child: Text('全选 (${_selected.length}/${_items.length})'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final i in shown) {
                          _selected.contains(i.url) ? _selected.remove(i.url) : _selected.add(i.url);
                        }
                      }),
                      child: const Text('反选'),
                    ),
                    if (_importing)
                      ElevatedButton(
                        key: const Key('rss_import_ok'),
                        onPressed: () => Navigator.of(context).pop([for (final i in _items) if (_selected.contains(i.url)) i.raw]),
                        child: const Text('确定'),
                      )
                    else ...[
                      TextButton(
                        key: const Key('rss_delete_selected'),
                        onPressed: () async {
                          if (_selected.isEmpty) {
                            Toast.show('请先选择规则!');
                          } else if (await _confirm('删除确认', '确定要删除这些订阅源吗？')) {
                            await _delete(_chosen);
                          }
                        },
                        child: Text('删除', style: TextStyle(color: cs.error)),
                      ),
                      TextButton(onPressed: _showMoreActions, child: const Text('更多')),
                    ],
                  ]),
                ),
              ),
            ),
    );
  }
}
