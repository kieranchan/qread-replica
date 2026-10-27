// pages/rss_page.dart — `RssPage`, the 订阅 tab of the main page: a grid of the enabled RSS sources (icon, name, `📶` for backend
// sources), group filter (`全部分组` / `未分组` / groups, `分组列表`), search (`搜索书本或者作者`), refresh, `编辑订阅源` -> RssSettingPage;
// tap opens the source (RssOpen), long press offers open / variable / edit / login / del.
//
// Original `_RssPageState` (app bar 0x52ac94 `订阅`, grid 0x52b6a0 / 0x52bd0c with `lib/assets/images/logo.png` as the fallback icon,
// search 0x52de48 / `filterSources`, group menu 0x52e670 / 0x52e524, group filter 0x1c5ab4, settings 0x52e47c, long-press menu
// 0xf68dc8, edit permission 0xf6975c, variable dialog 0x52c704, login `_showLogin` 0x8ed61c, sorting `_sortingsource` 0x8ed5c8).
import 'package:flutter/material.dart';

import '../data/rss.dart';
import '../qread/qread.dart';
import '../qread/rssdata.dart';
import '../util/toast.dart';
import '../util/webbook/model/rss_source.dart';
import 'rss/edit.dart';
import 'rss/open.dart';
import 'rss/rss_setting.dart';
import 'source/login_dialog.dart';

class RssPage extends StatefulWidget {
  const RssPage({super.key});

  @override
  State<RssPage> createState() => _RssPageState();
}

class _RssPageState extends State<RssPage> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _sources = [];
  String _group = rssAllGroups;
  bool _refreshing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Rssdata.load();
    final remote = <Map<String, dynamic>>[];
    if (Qread.isbind) {
      for (final s in await QRssSources.load()) {
        remote.add({...s.toJson(), 'isqread': true});
      }
    }
    if (!mounted) return;
    setState(() => _sources = [...Rssdata.enabledRaw, ...remote.where((m) => m['enabled'] != false)]);
  }

  /// The refresh button: backend list (when bound) and the local store.
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      if (Qread.isbind) await QRssSources.refresh();
      await Rssdata.load(force: true);
    } catch (e) {
      Toast.show('$e', iserror: true);
    }
    if (mounted) setState(() => _refreshing = false);
    await _load();
  }

  List<String> get _groups {
    final set = <String>{};
    for (final m in _sources) {
      for (final g in '${m['sourceGroup'] ?? ''}'.split(',')) {
        if (g.trim().isNotEmpty) set.add(g.trim());
      }
    }
    return [rssAllGroups, rssNoGroup, ...(set.toList()..sort())];
  }

  /// 0x1c5ab4 + `filterSources`.
  List<Map<String, dynamic>> get _shown {
    final q = _search.text.trim().toLowerCase();
    return _sources.where((m) {
      final g = '${m['sourceGroup'] ?? ''}';
      final ok = _group == rssAllGroups || (_group == rssNoGroup ? g.trim().isEmpty : g.split(',').map((e) => e.trim()).contains(_group));
      return ok && (q.isEmpty || '${m['sourceName'] ?? ''}'.toLowerCase().contains(q));
    }).toList();
  }

  bool _remote(Map<String, dynamic> m) => m['isqread'] == true || '${m['isqread']}' == 'true';

  Future<void> _open(Map<String, dynamic> m) => Navigator.of(context).push(MaterialPageRoute(builder: (c) => RssOpen(source: m)));

  Future<void> _settings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (c) => const RssSettingPage()));
    await _load();
  }

  /// 0xf68dc8.
  Future<void> _longPress(Map<String, dynamic> m, Offset at) async {
    final size = MediaQuery.of(context).size;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy),
      items: [
        const PopupMenuItem(value: 'open', child: Text('打开')),
        const PopupMenuItem(value: 'variable', child: Text('设置变量')),
        const PopupMenuItem(value: 'edit', child: Text('编辑')),
        if ('${m['loginUrl'] ?? ''}'.trim().isNotEmpty) const PopupMenuItem(value: 'login', child: Text('登录')),
        const PopupMenuItem(value: 'del', child: Text('删除')),
      ],
    );
    if (!mounted || v == null) return;
    final src = RssSource.fromJson(m);
    switch (v) {
      case 'open':
        await _open(m);
      case 'variable':
        await showSourceVariableDialog(context, src);
      case 'edit':
        if (_remote(m) && !Qread.requireEdit()) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => EditRssSourcePage(source: m)));
        await _load();
      case 'login':
        await showSourceLogin(context, src);
      case 'del':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('删除确认'),
            content: Text('确定要删除《${m['sourceName']}》吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
            ],
          ),
        );
        if (ok != true) return;
        if (_remote(m)) {
          Toast.show('请在订阅源管理中删除后端订阅源');
          return;
        }
        await RssSources.delete(['${m['sourceUrl']}']);
        Toast.show('删除成功');
        await _load();
    }
  }

  Widget _icon(Map<String, dynamic> m) {
    final url = '${m['sourceIcon'] ?? ''}';
    final fallback = Image.asset('lib/assets/images/logo.png', width: 44, height: 44, errorBuilder: (c, e, s) => const Icon(Icons.rss_feed, size: 40));
    if (!url.startsWith('http')) return fallback;
    return Image.network(url, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (c, e, s) => fallback);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final shown = _shown;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅'),
        actions: [
          _refreshing
              ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(key: const Key('rss_refresh'), tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _refresh),
          PopupMenuButton<String>(
            key: const Key('rss_group_menu'),
            tooltip: '分组列表',
            icon: const Icon(Icons.folder_outlined),
            onSelected: (g) => setState(() => _group = g),
            itemBuilder: (c) => [
              for (final g in _groups)
                PopupMenuItem(value: g, child: Row(children: [Icon(g == _group ? Icons.check_circle : Icons.circle_outlined, size: 18), const SizedBox(width: 8), Text(g)])),
            ],
          ),
          IconButton(key: const Key('rss_edit_sources'), tooltip: '编辑订阅源', icon: const Icon(Icons.tune), onPressed: _settings),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              key: const Key('rss_search'),
              controller: _search,
              decoration: InputDecoration(
                hintText: '搜索书本或者作者',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.rss_feed, size: 56, color: cs.outline),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _settings, child: const Text('编辑订阅源')),
                    ]),
                  )
                : LayoutBuilder(
                    builder: (c, box) => GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: (box.maxWidth / 90).floor().clamp(3, 10), childAspectRatio: 0.85),
                      itemCount: shown.length,
                      itemBuilder: (c, i) {
                        final m = shown[i];
                        return GestureDetector(
                          key: ValueKey('rss_tile_${m['sourceUrl']}'),
                          onTap: () => _open(m),
                          onLongPressStart: (d) => _longPress(m, d.globalPosition),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            ClipRRect(borderRadius: BorderRadius.circular(10), child: _icon(m)),
                            const SizedBox(height: 6),
                            Text('${_remote(m) ? '📶' : ''}${m['sourceName'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          ]),
                        );
                      },
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
