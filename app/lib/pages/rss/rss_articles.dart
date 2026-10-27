// pages/rss/rss_articles.dart — `RssArticles` (RSS列表, `rssarticles`): the articles of an RSS source, one tab per sort, paged on
// scroll, three layouts (compact list / card list / card grid; prefs `rsstype<sourceUrl>`, default the source's `articleStyle`),
// title filter, menu (change / log / login / history / setVariable / refresh).
//
// Original `_RssArticlesState` (app bar 0x598d2c, tab bar 0x5995d8 with `ArticleTab`s, search 0x59a4f8 / 0x59ab20, layouts
// `_buildCompactListItem` 0x59beac / `_buildCardListItem` 0x59af2c / `_buildCardGridItem` 0x59b78c, paging `_scrollListener`
// 0x9046d0 + 0xfadf2c, open 0xfaed94 -> RssArtOpen, menu 0xfaf0e0, login url check 0xfaf4bc `当前登录地址不正确!` -> WebPage, login
// dialog 0x59cf04, variable dialog 0x59c508, `rsstype` 0x904684 / 0xfafe90). Local sources run in the engine (`RssRunapi`), backend
// sources through `/getRsssortUrls` + `/getArticles`.
import 'package:flutter/material.dart';

import '../../api/rssapi.dart';
import '../../models/article.dart';
import '../../qread/api/rssapi.dart';
import '../../storage/storage.dart';
import '../../util/webbook/model/rss_source.dart';
import '../source/login_dialog.dart';
import 'debug.dart';
import 'rss_art_open.dart';
import 'rss_history.dart';

/// Layouts of the list (`rsstype<url>`).
enum RssLayout { compact, card, grid }

/// Paging state of one sort tab.
class RssTabState {
  final String name;
  final String url;
  final List<Article> items = [];
  String? nextUrl;
  int page = 0;
  bool loading = false;
  bool end = false;
  String? error;
  RssTabState(this.name, this.url);
}

/// Loads pages of an RSS source: the engine for local sources, the backend for `isqread` ones. Public for tests.
class RssPager {
  final Map<String, dynamic> raw;
  late final RssSource source = RssSource.fromJson(raw);
  RssPager(this.raw);

  bool get remote => raw['isqread'] == true || '${raw['isqread']}' == 'true';

  Future<List<(String, String)>> sorts() async {
    if (remote) return [for (final t in await RssApi.sorts(source.sourceUrl)) (t.sortName, t.sortUrl)];
    return RssRunapi.sorts(source);
  }

  /// Loads the next page of [t]; marks the end when a page brings nothing new or there is no next url.
  Future<void> next(RssTabState t) async {
    if (t.loading || t.end) return;
    t.loading = true;
    t.error = null;
    try {
      final page = t.page + 1;
      List<Article> list;
      bool more;
      if (remote) {
        final r = await RssApi.articles(source.sourceUrl, t.name, t.url, page);
        list = r.articles;
        more = r.next;
      } else {
        final url = page == 1 ? t.url : (t.nextUrl ?? '');
        if (url.isEmpty) {
          t.end = true;
          return;
        }
        final r = await RssRunapi.articles(source, t.name, url, page: page);
        list = [for (final a in r.$1) a.toModel()];
        t.nextUrl = r.$2;
        more = (r.$2 ?? '').isNotEmpty;
      }
      final known = t.items.map((e) => e.link).toSet();
      final fresh = list.where((a) => !known.contains(a.link)).toList();
      t.items.addAll(fresh);
      t.page = page;
      if (fresh.isEmpty || !more) t.end = true;
    } catch (e) {
      t.error = '$e';
    } finally {
      t.loading = false;
    }
  }
}

class RssArticles extends StatefulWidget {
  /// Raw JSON of the RSS source.
  final Map<String, dynamic> source;
  const RssArticles({super.key, required this.source});

  @override
  State<RssArticles> createState() => _RssArticlesState();
}

class _RssArticlesState extends State<RssArticles> with TickerProviderStateMixin {
  late final RssPager _pager = RssPager(widget.source);
  List<RssTabState> _tabs = [];
  TabController? _tabController;
  final _filter = TextEditingController();
  String? _error;
  bool _loading = true;
  late RssLayout _layout;

  String get _typeKey => 'rsstype${_pager.source.sourceUrl}';

  @override
  void initState() {
    super.initState();
    final t = Storage.getInt(_typeKey, _pager.source.articleStyle);
    _layout = RssLayout.values[t.clamp(0, RssLayout.values.length - 1)];
    _filter.addListener(() => setState(() {}));
    _loadSorts();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _loadSorts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sorts = await _pager.sorts();
      _tabs = [for (final s in sorts) RssTabState(s.$1, s.$2)];
      _tabController?.dispose();
      _tabController = TabController(length: _tabs.length, vsync: this)..addListener(_onTab);
      _loading = false;
      if (mounted) setState(() {});
      if (_tabs.isNotEmpty) await _more(_tabs.first);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _onTab() {
    final c = _tabController;
    if (c == null || c.indexIsChanging) return;
    final t = _tabs[c.index];
    if (t.page == 0) _more(t);
  }

  Future<void> _more(RssTabState t) async {
    final f = _pager.next(t);
    setState(() {});
    await f;
    if (mounted) setState(() {});
  }

  Future<void> _refresh(RssTabState t) async {
    final fresh = RssTabState(t.name, t.url);
    final i = _tabs.indexOf(t);
    if (i >= 0) _tabs[i] = fresh;
    await _more(fresh);
  }

  Future<void> _onSelected(String v) async {
    switch (v) {
      case 'change':
        final next = RssLayout.values[(_layout.index + 1) % RssLayout.values.length];
        await Storage.setInt(_typeKey, next.index);
        setState(() => _layout = next);
      case 'log':
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => DebugRssPage(source: widget.source)));
      case 'login':
        await showSourceLogin(context, _pager.source);
      case 'history':
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => RssHistory(source: widget.source)));
      case 'setVariable':
        await showSourceVariableDialog(context, _pager.source);
      case 'refresh':
        await _loadSorts();
    }
  }

  void _open(Article a) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (c) => RssArtOpen(source: widget.source, article: a.origin.isEmpty ? (a..origin = _pager.source.sourceUrl) : a)));

  Widget _image(String url, {double? w, double? h}) => url.isEmpty
      ? const SizedBox.shrink()
      : Image.network(url, width: w, height: h, fit: BoxFit.cover, errorBuilder: (c, e, s) => SizedBox(width: w, height: h));

  /// `_buildCompactListItem`.
  Widget _compact(Article a) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _open(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
              if (a.pubDate.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(a.pubDate, style: TextStyle(fontSize: 12, color: cs.outline))),
            ]),
          ),
          if (a.image.isNotEmpty) ...[const SizedBox(width: 12), ClipRRect(borderRadius: BorderRadius.circular(6), child: _image(a.image, w: 80, h: 56))],
        ]),
      ),
    );
  }

  /// `_buildCardListItem`.
  Widget _card(Article a) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _open(a),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (a.image.isNotEmpty) AspectRatio(aspectRatio: 16 / 9, child: _image(a.image)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              if (a.description.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(a.description.replaceAll(RegExp(r'<[^>]*>'), ''), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant))),
              if (a.pubDate.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(a.pubDate, style: TextStyle(fontSize: 12, color: cs.outline))),
            ]),
          ),
        ]),
      ),
    );
  }

  /// `_buildCardGridItem`.
  Widget _gridItem(Article a) => Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () => _open(a),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a.image.isEmpty ? Container(color: Theme.of(context).colorScheme.surfaceContainerHighest) : _image(a.image)),
            Padding(padding: const EdgeInsets.all(8), child: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          ]),
        ),
      );

  Widget _footer(RssTabState t) {
    final cs = Theme.of(context).colorScheme;
    if (t.loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    if (t.error != null) {
      return TextButton(onPressed: () => _more(t), child: Text('加载失败，点击重试\n${t.error}', textAlign: TextAlign.center, style: TextStyle(color: cs.error)));
    }
    if (t.end) return Padding(padding: const EdgeInsets.all(16), child: Center(child: Text(t.items.isEmpty ? '暂无内容' : '没有更多了', style: TextStyle(color: cs.outline))));
    return const SizedBox(height: 48);
  }

  Widget _tabBody(RssTabState t) {
    final q = _filter.text.trim().toLowerCase();
    final items = q.isEmpty ? t.items : t.items.where((a) => a.title.toLowerCase().contains(q)).toList();
    final Widget list;
    if (_layout == RssLayout.grid) {
      list = LayoutBuilder(
        builder: (c, box) => GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCountDelegate((box.maxWidth / 180).floor().clamp(2, 6)),
          itemCount: items.length + 1,
          itemBuilder: (c, i) => i == items.length ? _footer(t) : _gridItem(items[i]),
        ),
      );
    } else {
      list = ListView.separated(
        key: PageStorageKey('rss_${t.url}'),
        itemCount: items.length + 1,
        separatorBuilder: (c, i) => _layout == RssLayout.compact ? const Divider(height: 1) : const SizedBox.shrink(),
        itemBuilder: (c, i) => i == items.length ? _footer(t) : (_layout == RssLayout.card ? _card(items[i]) : _compact(items[i])),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // `_scrollListener`: near the end loads the next page
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300 && !t.loading && !t.end) _more(t);
        return false;
      },
      child: RefreshIndicator(onRefresh: () => _refresh(t), child: list),
    );
  }

  @override
  Widget build(BuildContext context) {
    final src = _pager.source;
    final showTabs = _tabs.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(src.sourceName),
        actions: [
          PopupMenuButton<String>(
            key: const Key('rss_articles_menu'),
            tooltip: '更多',
            onSelected: _onSelected,
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'change', child: Text('切换布局')),
              if ((src.loginUrl ?? '').trim().isNotEmpty) const PopupMenuItem(value: 'login', child: Text('登录')),
              const PopupMenuItem(value: 'history', child: Text('历史记录')),
              const PopupMenuItem(value: 'setVariable', child: Text('设置源变量')),
              const PopupMenuItem(value: 'log', child: Text('调试')),
              const PopupMenuItem(value: 'refresh', child: Text('刷新')),
            ],
          ),
        ],
        bottom: showTabs
            ? TabBar(controller: _tabController, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in _tabs) Tab(text: t.name.isEmpty ? src.sourceName : t.name)])
            : null,
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: TextField(
              key: const Key('rss_filter'),
              controller: _filter,
              decoration: InputDecoration(
                hintText: '搜索',
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
                : _error != null
                    ? Center(child: TextButton(onPressed: _loadSorts, child: Text(_error!, textAlign: TextAlign.center)))
                    : _tabs.isEmpty
                        ? const Center(child: Text('暂无内容'))
                        : showTabs
                            ? TabBarView(controller: _tabController, children: [for (final t in _tabs) _tabBody(t)])
                            : _tabBody(_tabs.first),
          ),
        ]),
      ),
    );
  }
}

/// A fixed column count grid delegate (the original uses `SliverGridDelegateWithFixedCrossAxisCount` with a 0.7 ratio).
class SliverGridDelegateWithFixedCrossAxisCountDelegate extends SliverGridDelegateWithFixedCrossAxisCount {
  const SliverGridDelegateWithFixedCrossAxisCountDelegate(int count) : super(crossAxisCount: count, childAspectRatio: 0.75, mainAxisSpacing: 4, crossAxisSpacing: 4);
}
