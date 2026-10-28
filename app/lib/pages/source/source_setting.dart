// pages/source/source_setting.dart — `SourceSettingPage`: the book-source manager (书源管理, `sourcesetting`), also used as the
// selection list of an import (title `导入`, every entry marked `已有` / `新增`, ✓ returns the chosen sources).
//
// Original `_SourceSettingPageState` (page 0x54c174: app bar with sort toggle `toggleSort`, group menu `全部分组` + groups
// (`分组列表`), more menu `_onSelected` 0xf8e798 add / addsource / urladd / help / maadd / refresh; search `搜索书源` 0x54cdb0;
// list 0x547a58 (ReorderableListView while sorting) and item 0x54839c (checkbox, `📶` / `📒` mark, name ` [group]`, `已有` / `新增`,
// check status `检验中` / `成功`, switch, edit button, item menu 0xf8bc70 login / help / search / setVariable / delVariable /
// topVariable / bottomSource / remote / debug / found / re); bottom bar 0x5439e4 `全选 (n/m)` / `反选` / `删除` / `更多`
// (`_showMoreActions`, actions 0x544a14); group filters 0x1c8304 (`未分组`, `时光源`, `阅读源`); type dialog 0x54d324; group dialogs
// 0x546b88 `选择或输入分组` / 0x54e118 `自定义分组`; top / bottom 0xf888b4 / 0xf88310 / 0xf8c790 / 0xf8c438; delete 0xf8b3d0; check
// 0xf83ec8 + 0xf84838 (`尝试搜索：` … `检验成功` / `检验失败:`); export 0xf82ea0 (`shareBookSource.json`); file import 0xf8efc0
// (`请选择您想要导入的书源文件`, `选择文件失败:`); import flow 0xe73fc8 (`json解析中`, `未解析到书源`, `选择的书源为空`,
// `轻悦时光新增…条书源，更新…条书源`, `导入书源失败:`) with the run-mode dialog util.dart 0x1c9160 (`轻阅读解析` / `兼容层解析`).
//
// `re` (重载书源线程) drops the per-source runtime state (SourceApi.reloadSource). Not ported: the 远程/本地 switch (`remote`, toggles
// `help` of backend 阅读源 whose html starts with `@yuedu`, 0x54839c) — it moves a backend source to the original's local compat
// layer; the replica runs backend sources on the backend only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../api/sourceapi.dart';
import '../../common/immersive_light.dart';
import '../../common/nav.dart';
import '../../data/qsource.dart';
import '../../data/source.dart';
import '../../models/source.dart';
import '../../qread/api/qsourceapi.dart';
import '../../qread/qread.dart';
import '../../util/http.dart';
import '../../util/source/source.dart' as ts;
import '../../util/toast.dart';
import '../../util/webbook/model/book_source.dart';
import '../../widget/ui/q_glass.dart';
import '../qread/qread_login.dart';
import '../scanner/mobile_scanner.dart';
import 'debug_qsource.dart';
import 'debug_source.dart';
import 'edit_source.dart';
import 'login_dialog.dart';
import 'sg_login.dart';
import 'source_help.dart';

const String allGroups = '全部分组';
const String noGroup = '未分组';
const String sgGroup = '时光源';
const String bqGroup = '阅读源';

/// File picking, QR input and sharing behind hooks so the import / export flows run in tests.
abstract class SourceImport {
  static Future<String?> Function() pickFileText = _pickFileText;
  static Future<String?> Function(BuildContext context) scan =
      (context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (c) => const MobileScannerPage()));
  static Future<void> Function(String fileName, String text) shareFile = _shareFile;

  static Future<String?> _pickFileText() async {
    final files = await FilePicker.pickFiles(dialogTitle: '请选择您想要导入的书源文件', type: FileType.any);
    if (files.isEmpty) return null;
    return utf8.decode(await files.first.readAsBytes(), allowMalformed: true);
  }

  static Future<void> _shareFile(String fileName, String text) async {
    final file = File(p.join(Directory.systemTemp.path, fileName));
    await file.writeAsString(text);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  /// The source maps in [text] (a JSON array or object); entries without url or name are dropped. Throws [FormatException].
  static List<Map<String, dynamic>> parse(String text) {
    final v = jsonDecode(text.trim());
    final items = v is List ? v : [v];
    return [
      for (final e in items)
        if (e is Map && '${e['bookSourceUrl'] ?? ''}'.trim().isNotEmpty && '${e['bookSourceName'] ?? ''}'.trim().isNotEmpty) Map<String, dynamic>.from(e)
    ];
  }

  /// Downloads a source file.
  static Future<String> download(String url) async {
    final res = await AppHttp.send(HttpRequest(url: url.trim(), useCookieJar: false));
    if (!res.isSuccessful) throw HttpFailure('HTTP ${res.statusCode}');
    return AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType);
  }

  /// 0xe73fc8: parse, let the user pick (unless [preview] is false), choose the run mode when a backend is bound, store.
  static Future<SourceImportResult?> importText(BuildContext context, String text, {bool preview = true}) async {
    try {
      var t = text.trim();
      if (t.startsWith('http://') || t.startsWith('https://')) t = await download(t);
      final maps = parse(t);
      if (maps.isEmpty) {
        Toast.show('未解析到书源');
        return null;
      }
      var chosen = maps;
      if (preview) {
        if (!context.mounted) return null;
        final r = await Navigator.of(context).push<List<Map<String, dynamic>>>(MaterialPageRoute(builder: (c) => SourceSettingPage(importList: maps)));
        if (r == null) return null;
        if (r.isEmpty) {
          Toast.show('选择的书源为空');
          return null;
        }
        chosen = r;
      }
      if (Qread.isbind && context.mounted) {
        final mode = await _runMode(context);
        if (mode == null) return null;
        if (mode == 'qread') {
          if (!Qread.requireEdit()) return null;
          await QSourceApi.saveAll(chosen);
          await QSourceApi.refresh();
          Toast.show('轻阅读新增${chosen.length}条书源');
          return SourceImportResult(chosen.length, 0, 0);
        }
      }
      final r = await Sources.addAll(chosen);
      Toast.show('轻悦时光新增${r.added}条书源，更新${r.updated}条书源');
      return r;
    } catch (e) {
      Toast.show('导入书源失败:$e', iserror: true);
      return null;
    }
  }

  /// util.dart 0x1c9160.
  static Future<String?> _runMode(BuildContext context) => showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Row(children: [Icon(Icons.info_outline), SizedBox(width: 12), Text('提示')]),
          content: const Text('您导入的书源有开源阅读书源，请选择运行方式！', style: TextStyle(height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop('qread'), child: const Text('轻阅读解析')),
            TextButton(onPressed: () => Navigator.of(c).pop('local'), child: const Text('兼容层解析')),
          ],
        ),
      );

  /// `legado://import/bookSource?src=…`, `yuedu://booksource/importonline?src=…` and the RSS variants.
  static Future<void> handleLink(BuildContext context, Uri uri, {Future<void> Function(BuildContext, String)? importRss}) async {
    final src = uri.queryParameters['src'] ?? '';
    if (src.isEmpty) {
      Toast.show('导入失败:!');
      return;
    }
    final kind = '${uri.host}${uri.path}'.toLowerCase();
    if (kind.contains('rss') && importRss != null) {
      await importRss(context, src);
    } else {
      await importText(context, src);
    }
  }
}

/// 0xf84838: checks one source (search with its check keyword, details, toc, first chapter). Gives `检验成功` or
/// `检验失败:<reason>`; [onStep] receives the intermediate texts (`尝试搜索：…`, `搜索成功：…`, `详情页检验成功`, `目录获取成功：…`).
Future<String> checkSource(Map<String, dynamic> raw, {void Function(String step)? onStep}) async {
  final source = BookSource.fromJson(raw);
  final rs = raw['ruleSearch'];
  var key = rs is Map ? '${rs['checkKeyWord'] ?? ''}'.trim() : '';
  if (key.isEmpty) key = '我的';
  try {
    onStep?.call('尝试搜索：$key');
    final hits = await SourceApi.search(source, key, useCache: false);
    if (hits.isEmpty) return '检验失败:搜索内容为空';
    onStep?.call('搜索成功：${hits.length}');
    final book = hits.first.toBook();
    final url = book.bookUrl;
    await SourceApi.bookInfo(source, book);
    if (book.bookUrl != url) return '检验失败:bookurl 为书本唯一标识不能改动';
    onStep?.call('详情页检验成功');
    final chapters = await SourceApi.chapters(source, book);
    if (chapters.isEmpty) return '检验失败:目录内容为空';
    onStep?.call('目录获取成功：${chapters.length}');
    final first = chapters.firstWhere((c) => !c.isVolume, orElse: () => chapters.first);
    final i = chapters.indexOf(first);
    final text = await SourceApi.content(source, book, first, nextChapterUrl: i + 1 < chapters.length ? chapters[i + 1].getAbsoluteURL() : null);
    if (text.trim().isEmpty) return '检验失败:正文内容为空';
    return '检验成功';
  } catch (e) {
    return '检验失败:$e';
  }
}

/// One row of the list.
class _Item {
  final Map<String, dynamic> raw;
  final SourceKind kind;
  _Item(this.raw) : kind = sourceKindOf(raw);
  String get url => '${raw['bookSourceUrl'] ?? ''}';
  String get name => '${raw['bookSourceName'] ?? ''}';
  String get group => '${raw['bookSourceGroup'] ?? ''}';
  bool get remote => kind == SourceKind.q;
  bool get enabled => raw['enabled'] == null || raw['enabled'] == true || '${raw['enabled']}' == 'true';
}

class SourceSettingPage extends StatefulWidget {
  /// Import mode: the parsed sources to choose from; the page pops with the chosen maps.
  final List<Map<String, dynamic>>? importList;
  const SourceSettingPage({super.key, this.importList});

  @override
  State<SourceSettingPage> createState() => _SourceSettingPageState();
}

class _SourceSettingPageState extends State<SourceSettingPage> {
  final _search = TextEditingController();
  List<_Item> _items = [];
  final Set<String> _selected = {};
  String _group = allGroups;
  bool _sorting = false;
  bool _loading = true;
  final Map<String, ValueNotifier<String>> _status = {};

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
    for (final n in _status.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    if (_importing) {
      await Sourcedata.load();
      setState(() {
        _items = [for (final m in widget.importList!) _Item(m)];
        _selected
          ..clear()
          ..addAll(_items.map((e) => e.url));
        _loading = false;
      });
      return;
    }
    await Sourcedata.load();
    final remote = <Map<String, dynamic>>[];
    if (Qread.isbind) {
      for (final s in await QSources.load()) {
        remote.add({...s.toJson(), 'isqread': true});
      }
    }
    if (!mounted) return;
    setState(() {
      _items = [for (final m in Sourcedata.raw) _Item(m), for (final m in remote) _Item(m)];
      _selected.removeWhere((u) => !_items.any((e) => e.url == u));
      _loading = false;
    });
  }

  /// Group names for the filter menu (`未分组`, `时光源`, `阅读源` first).
  List<String> get _groups {
    final set = <String>{};
    for (final i in _items) {
      for (final g in i.group.split(',')) {
        if (g.trim().isNotEmpty) set.add(g.trim());
      }
    }
    return [allGroups, noGroup, sgGroup, bqGroup, ...(set.toList()..sort())];
  }

  /// 0x1c8304 + 0x1c8254.
  List<_Item> get _shown {
    final q = _search.text.trim().toLowerCase();
    return _items.where((i) {
      final okGroup = switch (_group) {
        allGroups => true,
        noGroup => i.group.trim().isEmpty,
        sgGroup => i.kind == SourceKind.sg,
        bqGroup => i.kind == SourceKind.bq,
        _ => i.group.split(',').map((e) => e.trim()).contains(_group),
      };
      if (!okGroup) return false;
      if (q.isEmpty) return true;
      return i.name.toLowerCase().contains(q) || i.url.toLowerCase().contains(q) || i.group.toLowerCase().contains(q);
    }).toList();
  }

  List<_Item> get _chosen => _items.where((i) => _selected.contains(i.url)).toList();

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

  // --------------------------------------------------------------------------------------------------------------- actions

  Future<void> _setEnabled(List<_Item> items, bool on, {bool explore = false}) async {
    try {
      final local = [for (final i in items) if (!i.remote) i.url];
      final remote = [for (final i in items) if (i.remote) i.url];
      if (local.isNotEmpty) await (explore ? Sources.setEnabledExplore(local, on) : Sources.setEnabled(local, on));
      if (remote.isNotEmpty) {
        await (explore ? QSourceApi.setEnabledExplore(remote, on) : QSourceApi.setEnabled(remote, on));
        await QSourceApi.refresh();
      }
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
    await _reload();
  }

  /// Moves the local sources [urls] to the top or the bottom of the list.
  Future<void> _move(List<String> urls, {required bool top}) async {
    final set = urls.toSet();
    await Sourcedata.store.run((list) {
      final moved = [for (final e in list) if (set.contains('${e['bookSourceUrl']}')) e];
      list.removeWhere((e) => set.contains('${e['bookSourceUrl']}'));
      if (top) {
        list.insertAll(0, moved);
      } else {
        list.addAll(moved);
      }
    });
    await _reload();
  }

  Future<void> _delete(List<_Item> items) async {
    try {
      final local = [for (final i in items) if (!i.remote) i.url];
      final remote = [for (final i in items) if (i.remote) i.url];
      if (local.isNotEmpty) await Sources.delete(local);
      if (remote.isNotEmpty) {
        if (!Qread.requireEdit()) return;
        await QSourceApi.delete(remote);
        await QSourceApi.refresh();
      }
      _selected.removeAll(items.map((e) => e.url));
      Toast.show('删除成功');
    } catch (e) {
      Toast.show('删除失败: $e', iserror: true);
    }
    await _reload();
  }

  Future<void> _edit(_Item i) async {
    if (i.remote && !Qread.requireEdit()) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (c) => EditSource(source: i.raw)));
    await _reload();
  }

  Future<void> _add() async {
    final kind = await chooseSourceKind(context);
    if (kind == null || !mounted) return;
    if (kind == SourceKind.q && !Qread.requireEdit()) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (c) => EditSource(kind: kind)));
    await _reload();
  }

  Future<void> _debug(_Item i) async {
    if (i.remote) {
      if (!Qread.requireEdit()) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (c) => DebugQSourcePage(url: i.url, name: i.name)));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (c) => DebugSourcePage(source: i.raw)));
  }

  /// Item menu 0xf8bc70.
  Future<void> _onItemMenu(_Item i, String v) async {
    switch (v) {
      case 'top':
      case 'bottomSource':
        final top = v == 'top';
        if (!await _confirm(top ? '置顶确认' : '置底确认', '确定要把《${i.name}》${top ? '置顶' : '置底'}吗？')) return;
        try {
          await _move([i.url], top: top);
          Toast.show(top ? '置顶成功' : '置底成功');
        } catch (e) {
          Toast.show('${top ? '置顶' : '置底'}失败: $e');
        }
      case 'del':
        if (await _confirm('删除确认', '确定要删除《${i.name}》吗？')) await _delete([i]);
      case 'login':
        if (!mounted) return;
        if (i.kind == SourceKind.sg) {
          await showTimeSourceLogin(context, ts.BaseSource.fromJson(i.raw));
        } else {
          await showSourceLogin(context, BookSource.fromJson(i.raw));
        }
      case 'setVariable':
        if (i.remote) {
          final cur = await QSourceApi.getVariable(i.url).catchError((_) => '');
          if (mounted) await showSourceVariableDialog(context, BookSource.fromJson(i.raw), current: cur, onSave: (t) => QSourceApi.setVariable(i.url, t));
        } else if (mounted) {
          await showSourceVariableDialog(context, BookSource.fromJson(i.raw));
        }
      case 'search':
        // 0xf8bc70: SearchBookPage(key '', the source)
        if (mounted) await Nav.openSearch(context, sources: [Source.fromJson(i.raw)]);
      case 'found':
        // 0xf8bc70: DiscoveryPageNew on this source
        if (mounted) await Nav.openNamed(context, 'discovery_page_new', arguments: Source.fromJson(i.raw));
      case 're':
        // 0xf8bc70: `是否重载<name>书源线程` (操作提示), then the source's runner is dropped (SourceApi 0xe77e8c)
        if (!await _confirm('操作提示', '是否重载${i.name}书源线程')) return;
        SourceApi.reloadSource(i.url);
        if (mounted) setState(() {});
      case 'debug':
        await _debug(i);
      case 'help':
        if (!mounted) return;
        if (i.kind == SourceKind.sg && ts.BaseSource.fromJson(i.raw).help) {
          await showTimeSourceHelp(context, ts.BaseSource.fromJson(i.raw));
        } else {
          await Navigator.of(context).push(MaterialPageRoute(builder: (c) => const SourceHelpPage()));
        }
    }
  }

  /// More menu 0xf8e798.
  Future<void> _onSelected(String v) async {
    switch (v) {
      case 'add':
        await _add();
      case 'addsource':
        try {
          final t = await SourceImport.pickFileText();
          if (t != null && mounted) await SourceImport.importText(context, t);
        } catch (e) {
          Toast.show('选择文件失败:$e', iserror: true);
        }
      case 'urladd':
        final url = await _askText('网络导入', 'https://');
        if (url != null && url.trim().isNotEmpty && mounted) await SourceImport.importText(context, url);
      case 'clipboard':
        final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        if (t.trim().isEmpty) {
          Toast.show('剪贴板为空!');
        } else if (mounted) {
          await SourceImport.importText(context, t);
        }
      case 'maadd':
        final url = await SourceImport.scan(context);
        if (url != null && url.startsWith('http') && mounted) await SourceImport.importText(context, url);
      case 'exportall':
        await _export(_items.where((i) => !i.remote).toList());
      case 'qread':
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => const QReadLoginPage()));
      case 'refresh':
        if (Qread.isbind) {
          try {
            await QSourceApi.refresh();
          } catch (e) {
            Toast.show('获取轻阅读书源失败', iserror: true);
          }
        }
      case 'help':
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => const SourceHelpPage()));
    }
    await _reload();
  }

  Future<String?> _askText(String title, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(key: const Key('ask_text'), controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(key: const Key('ask_ok'), onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('确定')),
        ],
      ),
    );
  }

  /// 0xf82ea0: the chosen local sources as `shareBookSource.json`.
  Future<void> _export(List<_Item> items) async {
    final local = items.where((i) => !i.remote).toList();
    if (local.isEmpty) {
      Toast.show('请先选择规则!');
      return;
    }
    try {
      final text = await Sources.exportJson(urls: local.map((e) => e.url));
      await SourceImport.shareFile('shareBookSource.json', text);
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
  }

  /// 0x546b88 `选择或输入分组`: an existing group or a new name.
  Future<String?> _pickGroup({bool remove = false}) {
    final names = remove
        ? {for (final i in _chosen) ...i.group.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)}.toList()
        : _groups.where((g) => g != allGroups && g != noGroup && g != sgGroup && g != bqGroup).toList();
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(remove ? '移除分组' : '选择或输入分组'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final g in names) ListTile(dense: true, title: Text(g), onTap: () => Navigator.of(ctx).pop(g)),
              if (!remove)
                TextField(
                  key: const Key('group_input'),
                  controller: c,
                  decoration: const InputDecoration(labelText: '输入新分组', hintText: '输入新的分组名称', border: OutlineInputBorder()),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          if (!remove)
            TextButton(
              key: const Key('group_ok'),
              onPressed: () {
                if (c.text.trim().isEmpty) {
                  Toast.show('分组名称不能为空！');
                  return;
                }
                Navigator.of(ctx).pop(c.text.trim());
              },
              child: const Text('确定'),
            ),
        ],
      ),
    );
  }

  Future<void> _editGroup(bool remove) async {
    final g = await _pickGroup(remove: remove);
    if (g == null || g.isEmpty) return;
    final local = [for (final i in _chosen) if (!i.remote) i.url];
    final remote = [for (final i in _chosen) if (i.remote) i.url];
    try {
      if (local.isNotEmpty) await (remove ? Sources.removeGroup(local, g) : Sources.addGroup(local, g));
      if (remote.isNotEmpty) {
        await QSourceApi.editGroup(remote, g, st: remove ? 0 : 1);
        await QSourceApi.refresh();
      }
      Toast.show('操作成功');
    } catch (e) {
      Toast.show('操作失败: $e', iserror: true);
    }
    await _reload();
  }

  /// `_showMoreActions` (actions of 0x544a14).
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
              ('enableExplore', '启用发现'),
              ('disableExplore', '禁用发现'),
              ('addGroup', '加入分组'),
              ('removeGroup', '移除分组'),
              ('top', '置顶所选'),
              ('bottom', '置底所选'),
              ('export', '导出所选'),
              ('check', '检验所选'),
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
      case 'enableExplore':
        await _setEnabled(items, true, explore: true);
      case 'disableExplore':
        await _setEnabled(items, false, explore: true);
      case 'addGroup':
        await _editGroup(false);
      case 'removeGroup':
        await _editGroup(true);
      case 'top':
      case 'bottom':
        final top = v == 'top';
        if (!await _confirm(top ? '置顶确认' : '置底确认', '确定要${top ? '置顶' : '置底'}这些书源吗？')) return;
        try {
          await _move([for (final i in items) if (!i.remote) i.url], top: top);
          Toast.show(top ? '置顶成功' : '置底成功');
        } catch (e) {
          Toast.show('${top ? '置顶' : '置底'}失败: $e');
        }
      case 'export':
        await _export(items);
      case 'check':
        await _check(items);
    }
  }

  Future<void> _delall() async {
    if (_selected.isEmpty) {
      Toast.show('请先选择规则!');
      return;
    }
    if (await _confirm('删除确认', '确定要删除这些书源吗？')) await _delete(_chosen);
  }

  // ------------------------------------------------------------------------------------------------------------------- check

  /// 0xf83ec8: checks the chosen sources, a few at a time (`startNextTask`).
  Future<void> _check(List<_Item> items) async {
    final local = items.where((i) => !i.remote && i.kind == SourceKind.bq).toList();
    if (local.isEmpty) {
      Toast.show('请选择要检验的书源');
      return;
    }
    if (!await _confirm('操作确认', '确定要检验选中的书源吗？')) return;
    for (final i in local) {
      (_status[i.url] ??= ValueNotifier<String>('')).value = '检验中';
    }
    var next = 0;
    Future<void> startNextTask() async {
      while (next < local.length) {
        final i = local[next++];
        final n = _status[i.url]!;
        try {
          n.value = await checkSource(i.raw, onStep: (s) => n.value = '检验中 $s');
        } catch (e) {
          debugPrint('${i.name}, 错误: $e');
          n.value = '检验失败:$e';
        }
      }
    }

    await Future.wait([for (var k = 0; k < 4; k++) startNextTask()]);
    Toast.show('检验完成');
  }

  // ---------------------------------------------------------------------------------------------------------------------- UI

  Widget _itemTile(_Item i, int index) {
    final cs = Theme.of(context).colorScheme;
    final mark = sourceMark(i.kind);
    final title = '$mark${i.name}${i.group.trim().isEmpty ? '' : ' [${i.group}]'}';
    final status = _status[i.url];
    final exists = _importing && Sourcedata.byUrl(i.url) != null;
    return Material(
      key: ValueKey('src_${i.url}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selected.contains(i.url) ? _selected.remove(i.url) : _selected.add(i.url)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(children: [
            Checkbox(value: _selected.contains(i.url), onChanged: (v) => setState(() => v == true ? _selected.add(i.url) : _selected.remove(i.url))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (status != null)
                  ValueListenableBuilder<String>(
                    valueListenable: status,
                    builder: (c, s, _) => Tooltip(
                      message: s,
                      child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: s.startsWith('检验失败') ? cs.error : cs.primary)),
                    ),
                  )
                else
                  Text(i.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.outline)),
              ]),
            ),
            if (_importing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(exists ? '已有' : '新增', style: TextStyle(color: exists ? cs.outline : cs.primary)),
              )
            else if (_sorting)
              ReorderableDragStartListener(index: index, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle)))
            else ...[
              Switch(key: Key('enable_${i.url}'), value: i.enabled, onChanged: (v) => _setEnabled([i], v)),
              IconButton(tooltip: '编辑', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(i)),
              PopupMenuButton<String>(
                key: Key('menu_${i.url}'),
                tooltip: '更多',
                onSelected: (v) => _onItemMenu(i, v),
                itemBuilder: (c) => [
                  if (!i.remote) const PopupMenuItem(value: 'top', child: Text('置顶')),
                  if (!i.remote) const PopupMenuItem(value: 'bottomSource', child: Text('置底')),
                  const PopupMenuItem(value: 'search', child: Text('搜索')),
                  const PopupMenuItem(value: 'found', child: Text('发现')),
                  const PopupMenuItem(value: 'debug', child: Text('调试')),
                  const PopupMenuItem(value: 're', child: Text('重载')),
                  if ('${i.raw['loginUrl'] ?? ''}'.trim().isNotEmpty || (i.kind == SourceKind.sg && ts.BaseSource.fromJson(i.raw).login))
                    const PopupMenuItem(value: 'login', child: Text('登录')),
                  if (i.kind == SourceKind.sg && ts.BaseSource.fromJson(i.raw).help) const PopupMenuItem(value: 'help', child: Text('帮助')),
                  const PopupMenuItem(value: 'setVariable', child: Text('设置源变量')),
                  const PopupMenuItem(value: 'del', child: Text('删除')),
                ],
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _bottomBar(List<_Item> shown) {
    final cs = Theme.of(context).colorScheme;
    final allSel = shown.isNotEmpty && shown.every((i) => _selected.contains(i.url));
    // 0x5439e4: the bar is a QGlassContainer (沉浸光感)
    return QGlassContainer(
      borderRadius: 0,
      color: ImmersiveLight.level.value == ImmersiveLight.off ? cs.surfaceContainer : null,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            TextButton(
              key: const Key('select_all'),
              onPressed: () => setState(() => allSel ? _selected.removeAll(shown.map((e) => e.url)) : _selected.addAll(shown.map((e) => e.url))),
              child: Text('全选 (${_selected.length}/${_items.length})'),
            ),
            TextButton(
              key: const Key('invert'),
              onPressed: () => setState(() {
                for (final i in shown) {
                  _selected.contains(i.url) ? _selected.remove(i.url) : _selected.add(i.url);
                }
              }),
              child: const Text('反选'),
            ),
            if (_importing)
              ElevatedButton(
                key: const Key('import_ok'),
                onPressed: () => Navigator.of(context).pop([for (final i in _items) if (_selected.contains(i.url)) i.raw]),
                child: const Text('确定'),
              )
            else ...[
              TextButton(key: const Key('delete_selected'), onPressed: _delall, child: Text('删除', style: TextStyle(color: cs.error))),
              TextButton(key: const Key('more_actions'), onPressed: _showMoreActions, child: const Text('更多')),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_importing ? '导入' : '书源管理'),
        actions: _importing
            ? null
            : [
                IconButton(
                  key: const Key('toggle_sort'),
                  tooltip: '排序',
                  icon: Icon(_sorting ? Icons.check : Icons.sort),
                  onPressed: () => setState(() {
                    _sorting = !_sorting;
                    if (_sorting) {
                      _group = allGroups;
                      _search.clear();
                    }
                  }),
                ),
                PopupMenuButton<String>(
                  key: const Key('group_menu'),
                  tooltip: '分组列表',
                  icon: const Icon(Icons.folder_outlined),
                  onSelected: (g) => setState(() => _group = g),
                  itemBuilder: (c) => [
                    for (final g in _groups)
                      PopupMenuItem(
                        value: g,
                        child: Row(children: [Icon(g == _group ? Icons.check_circle : Icons.circle_outlined, size: 18), const SizedBox(width: 8), Text(g)]),
                      ),
                  ],
                ),
                PopupMenuButton<String>(
                  key: const Key('source_menu'),
                  tooltip: '更多',
                  onSelected: _onSelected,
                  itemBuilder: (c) => const [
                    PopupMenuItem(value: 'add', child: Text('新建书源')),
                    PopupMenuItem(value: 'addsource', child: Text('本地导入')),
                    PopupMenuItem(value: 'urladd', child: Text('网络导入')),
                    PopupMenuItem(value: 'clipboard', child: Text('剪贴板导入')),
                    PopupMenuItem(value: 'maadd', child: Text('扫码导入')),
                    PopupMenuItem(value: 'exportall', child: Text('导出书源')),
                    PopupMenuItem(value: 'qread', child: Text('轻阅读后端绑定')),
                    PopupMenuItem(value: 'refresh', child: Text('刷新')),
                    PopupMenuItem(value: 'help', child: Text('书源帮助')),
                  ],
                ),
              ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (!_sorting)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                key: const Key('source_search'),
                controller: _search,
                decoration: InputDecoration(
                  hintText: '搜索书源',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
          if (!_importing && _group != allGroups)
            Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Chip(label: Text(_group), onDeleted: () => setState(() => _group = allGroups)))),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.source_outlined, size: 56, color: cs.outline),
                          const SizedBox(height: 8),
                          const Text('还没有添加书源'),
                          TextButton(onPressed: _add, child: const Text('点击添加书源开始使用')),
                        ]),
                      )
                    : _sorting
                        ? ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            itemCount: shown.length,
                            itemBuilder: (c, i) => _itemTile(shown[i], i),
                            onReorderItem: (from, to) async {
                              final moved = shown[from];
                              if (moved.remote) return;
                              await Sourcedata.store.run((list) {
                                final a = list.indexWhere((e) => '${e['bookSourceUrl']}' == moved.url);
                                if (a < 0) return;
                                final m = list.removeAt(a);
                                list.insert(to.clamp(0, list.length), m);
                              });
                              await _reload();
                            },
                          )
                        : Scrollbar(
                            child: ListView.builder(itemCount: shown.length, itemBuilder: (c, i) => _itemTile(shown[i], i)),
                          ),
          ),
        ]),
      ),
      bottomNavigationBar: _items.isEmpty || _sorting ? null : _bottomBar(shown),
    );
  }
}
