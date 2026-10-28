// pages/discovery_page_new.dart — 发现 (`DiscoveryPageNew`, the default layout: `discoveryStyle` == 0 in main_page 0x50d4b4).
//
// One source at a time (prefs `selectedDiscoverySource` = JSON `{bookSourceUrl, isqread}`, read error 「读取选中书源失败: 」); the
// title opens the source chooser (「搜索书源」); the source menu offers 刷新 / 登录 / 编辑 (「当前用户无法编辑轻阅读书源…」 for bound-
// backend sources) and 变量 (`setVariable`); the body is the source's explore tags with the book list (DiscoveryRightPage).
// Empty states: 「还没有添加书源」 + 「请先前往书源管理中添加书源并启用发现」, 「未选择书源」. The search button opens SearchBookPage.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../common/nav.dart';
import '../data/source.dart';
import '../models/source.dart';
import '../storage/storage.dart';
import '../widget/base_page.dart';
import '../widget/discovery/discovery_right.dart';
import '../widget/ui/q_popup_menu_button.dart';
import 'search/search_book_page.dart';

abstract class DiscoveryPrefs {
  static const String selectedKey = 'selectedDiscoverySource';
  static const String groupKey = 'discoverySelectedGroup';

  static String get selectedUrl {
    final t = Storage.getString(selectedKey);
    if (t.isEmpty) return '';
    try {
      final j = jsonDecode(t);
      return j is Map ? '${j['bookSourceUrl'] ?? ''}' : '';
    } catch (e) {
      debugPrint('读取选中书源失败: $e');
      return '';
    }
  }

  static Future<void> setSelected(Source s) =>
      Storage.setString(selectedKey, jsonEncode({'bookSourceUrl': s.bookSourceUrl, 'isqread': s.isqread}));
}

/// Sources with explore rules (enabled + enabledExplore + exploreUrl).
List<Source> exploreSources() => [for (final m in Sourcedata.exploreRaw) Source.fromJson(m)];

class DiscoveryPageNew extends StatefulWidget {
  /// The source to show first (the source manager's 「发现」 on one source, 0xf8bc70); null = the saved choice.
  final Source? source;

  const DiscoveryPageNew({super.key, this.source});

  @override
  State<DiscoveryPageNew> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends BasePage<DiscoveryPageNew> with AutomaticKeepAliveClientMixin {
  List<Source>? _sources;
  Source? _source;
  final GlobalKey<DiscoveryRightPageState> _right = GlobalKey();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Sourcedata.load();
    final list = exploreSources();
    final given = widget.source;
    final url = given?.bookSourceUrl ?? DiscoveryPrefs.selectedUrl;
    update(() {
      _sources = given == null || list.any((s) => s.bookSourceUrl == given.bookSourceUrl) ? list : [given, ...list];
      _source = _sources!.where((s) => s.bookSourceUrl == url).firstOrNull ?? _sources!.firstOrNull;
    });
  }

  Future<void> _chooseSource() async {
    final list = _sources ?? const <Source>[];
    var filter = '';
    final s = await showModalBottomSheet<Source>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final shown = list.where((s) => filter.isEmpty || s.bookSourceName.contains(filter) || s.bookSourceGroup.contains(filter)).toList();
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(c).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  key: const Key('disc_source_filter'),
                  decoration: const InputDecoration(hintText: '搜索书源', prefixIcon: Icon(Icons.search), isDense: true),
                  onChanged: (v) => set(() => filter = v.trim()),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (c, i) => ListTile(
                    key: Key('disc_src_${shown[i].bookSourceUrl}'),
                    title: Text(shown[i].bookSourceName),
                    subtitle: shown[i].bookSourceGroup.isEmpty ? null : Text(shown[i].bookSourceGroup),
                    trailing: shown[i].bookSourceUrl == _source?.bookSourceUrl ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(c).pop(shown[i]),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (s == null) return;
    await DiscoveryPrefs.setSelected(s);
    update(() => _source = s);
  }

  Future<void> _menu(String v) async {
    final s = _source;
    if (s == null) return;
    switch (v) {
      case 're':
        await Sourcedata.load(force: true);
        await _load();
        await _right.currentState?.reload();
      case 'login':
        await Nav.openNamed(context, 'source_login', arguments: s.bookSourceUrl);
      case 'edit':
        await Nav.openSourceEdit(context, s);
        await _load();
      case 'setVariable':
        await Nav.openNamed(context, 'source_variable', arguments: s.bookSourceUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _sources;
    final s = _source;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          key: const Key('disc_title'),
          onTap: list == null || list.isEmpty ? null : _chooseSource,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(s?.bookSourceName ?? '发现', overflow: TextOverflow.ellipsis)),
            if (list != null && list.isNotEmpty) const Icon(Icons.keyboard_arrow_down),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchBookPage(sources: s == null ? null : [s]))),
          ),
          if (s != null)
            QPopupMenuButton<String>(
              items: [
                const QPopupMenuItem(value: 're', title: '刷新', icon: Icons.refresh, sfSymbol: 'arrow.clockwise'),
                if (s.loginUrl.isNotEmpty) const QPopupMenuItem(value: 'login', title: '登录', icon: Icons.login, sfSymbol: 'arrow.right.square'),
                const QPopupMenuItem(value: 'setVariable', title: '变量', icon: Icons.settings, sfSymbol: 'gear'),
                const QPopupMenuItem(value: 'edit', title: '编辑', icon: Icons.edit, sfSymbol: 'pencil'),
              ],
              onSelected: _menu,
            ),
        ],
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.explore_outlined, size: 56, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('还没有添加书源', key: Key('disc_empty'), style: TextStyle(fontSize: 16)),
                    SizedBox(height: 6),
                    Text('请先前往书源管理中添加书源并启用发现', style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : s == null
                  ? const Center(child: Text('未选择书源'))
                  : DiscoveryRightPage(key: _right, source: s),
    );
  }
}
