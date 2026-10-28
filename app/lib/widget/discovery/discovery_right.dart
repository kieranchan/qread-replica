// widget/discovery/discovery_right.dart — `DiscoveryRightPage`: the explore categories of one source as tags and the endless
// book list of the selected tag (used by both discovery layouts).
//
// Explore kinds come from the engine (`exploreKinds`). Kinds with a url are list categories; the other kinds (button / text
// 「点击输入」 / select / toggle with an `action`) run the action (0xfb87b4): backend sources (`isqread`) POST `/findaction`
// `{bookSourceUrl, action, key, value}` to the bound 轻阅读 backend (0xfb824c), local sources run the action JavaScript in the engine
// with Legado's semantics (`key` = the kind title, `value` = the input, kept with `source.put`). The result is an explore url shown
// in the found page (`SearchPage(source, url)`), or, for kinds with `useShouldOverrideUrlLoading`, a page opened in the web view
// (the two outcomes of 0xfb87b4); errors `发现按钮错误: `. 时光源 entries come from the page's `getfinds()` (util/source/run.dart maps
// their kinds: drop-downs and inputs store the value with `cache.set(title, value)` before the action runs, type 1 opens its url in
// the source's browser page), and the page's `refreshExplore` reloads them.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/sourceapi.dart';
import '../../data/source.dart';
import '../../models/explore.dart';
import '../../models/source.dart';
import '../../pages/book/book_detail_page.dart';
import '../../pages/search/book_search_service.dart';
import '../../pages/search/search_page.dart';
import '../../pages/search/source_filter.dart';
import '../../pages/web/webview.dart';
import '../../qread/qread.dart';
import '../../qread/qread_jobs.dart';
import '../../util/source/baswebview.dart';
import '../../util/source/source.dart' as ts;
import '../../util/webbook/model/book_source.dart';
import '../../util/toast.dart';
import '../base_page.dart';
import '../book/booklist.dart';

class DiscoveryRightPage extends StatefulWidget {
  final Source source;

  /// Show the books as a list (true) or as a cover grid.
  final bool islist;

  const DiscoveryRightPage({super.key, required this.source, this.islist = true});

  @override
  State<DiscoveryRightPage> createState() => DiscoveryRightPageState();
}

class DiscoveryRightPageState extends BasePage<DiscoveryRightPage> {
  List<Explore>? _kinds;
  String _error = '';
  int _selected = -1;
  FoundPager? _pager;
  String _filter = '';

  List<Explore> get kinds => _kinds ?? const [];

  StreamSubscription<String>? _refresh;

  @override
  void initState() {
    super.initState();
    // a 时光源 page asked for fresh entries (`refreshExplore`, 0xea822c)
    _refresh = ExploreRefresh.stream.listen((url) {
      if (mounted && url == widget.source.bookSourceUrl) reload();
    });
    // the 轻阅读 backend's `refreshExplore` job (0xf1ab48, hook 0x1ea4) reloads the open backend source's entries
    QreadHooks.refreshExplore = _backendRefresh;
    reload();
  }

  Future<void> _backendRefresh() async {
    if (mounted && widget.source.isqread) await reload();
  }

  @override
  void dispose() {
    if (QreadHooks.refreshExplore == _backendRefresh) QreadHooks.refreshExplore = null;
    _refresh?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DiscoveryRightPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.bookSourceUrl != widget.source.bookSourceUrl) reload();
  }

  static bool isList(Explore k) => k.url.trim().isNotEmpty && k.type_ == ExploreKind.typeUrl;

  /// Kinds that run an action instead of listing books (and 时光源 entries that open their url in the web view).
  static bool isAction(Explore k) =>
      const {ExploreKind.typeButton, ExploreKind.typeText, ExploreKind.typeSelect, ExploreKind.typeToggle, ExploreKind.typeWeb}.contains(k.type_);

  /// Values of the input kinds (text / select / toggle), per kind title.
  final Map<String, String> _values = {};

  String _valueOf(Explore k) {
    final v = _values[k.title];
    if (v != null) return v;
    final raw = Sourcedata.byUrl(widget.source.bookSourceUrl);
    final stored = raw == null ? null : BookSource.fromJson(Map<String, dynamic>.from(raw)).get(k.title);
    if (stored != null && stored.isNotEmpty) return stored;
    if (k.default_.isNotEmpty) return k.default_;
    return k.type_ == ExploreKind.typeText ? '' : (k.chars.isEmpty ? '' : '${k.chars.first}');
  }

  /// 0xfb87b4: runs [k]'s action with [value]; the result opens the web view (a url) or the search page (other text).
  Future<void> runAction(Explore k, {String? value}) async {
    try {
      String result;
      Map<String, dynamic>? raw;
      if (widget.source.isqread) {
        final r = await Qread.post('/findaction', {'bookSourceUrl': widget.source.bookSourceUrl, 'action': k.action, 'key': k.title, 'value': value ?? ''});
        result = r == null ? '' : '$r';
      } else {
        raw = Sourcedata.byUrl(widget.source.bookSourceUrl);
        if (raw == null) throw StateError('书源不存在');
        result = await SourceApi.exploreAction(BookSource.fromJson(Map<String, dynamic>.from(raw)), k.action.isNotEmpty ? k.action : k.js, key: k.title, value: value);
      }
      if (!mounted) return;
      final t = result.trim();
      if (t.isEmpty) return;
      if (ts.BaseSource.isTimeSource(raw)) {
        // 时光源 actions do their work in the page (cache.set, refreshExplore …); only an url they answer is opened
        if (t.startsWith('http://') || t.startsWith('https://')) {
          await SourceUi.openBrowser?.call(SourceBrowserRequest(
            url: t,
            title: k.title,
            source: ts.BaseSource.fromJson(raw!),
            overrideUrlLoading: k.useShouldOverrideUrlLoading,
          ));
        }
        return;
      }
      if (k.useShouldOverrideUrlLoading && (t.startsWith('http://') || t.startsWith('https://'))) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WebviewPage(url: t, title: k.title)));
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchPage(source: widget.source, url: t, title: k.title)));
      }
    } catch (e) {
      Toast.show('发现按钮错误: $e', iserror: true);
    }
  }

  /// A 时光源 entry of type 1: its url in the source's browser page (with the page's shouldOverrideUrlLoading when asked).
  Future<void> _openWeb(Explore k) async {
    final raw = Sourcedata.byUrl(widget.source.bookSourceUrl);
    if (raw == null || k.url.trim().isEmpty) return;
    await SourceUi.openBrowser?.call(SourceBrowserRequest(
      url: k.url.trim(),
      title: k.title,
      source: ts.BaseSource.fromJson(raw),
      overrideUrlLoading: k.useShouldOverrideUrlLoading,
    ));
  }

  Future<void> _tapAction(Explore k) async {
    switch (k.type_) {
      case ExploreKind.typeWeb:
        await _openWeb(k);
      case ExploreKind.typeButton:
        await runAction(k);
      case ExploreKind.typeText:
        final ctl = TextEditingController(text: _valueOf(k));
        final v = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(k.title),
            content: TextField(key: const Key('kind_input'), controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: '点击输入')),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
              ElevatedButton(key: const Key('kind_input_ok'), onPressed: () => Navigator.of(c).pop(ctl.text), child: const Text('确定')),
            ],
          ),
        );
        ctl.dispose();
        if (v == null) return;
        update(() => _values[k.title] = v);
        if (k.action.isNotEmpty || k.js.isNotEmpty || widget.source.isqread) await runAction(k, value: v);
      case ExploreKind.typeSelect:
        final v = await showModalBottomSheet<String>(
          context: context,
          builder: (c) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
              for (final ch in k.chars)
                ListTile(title: Text('$ch'), trailing: '$ch' == _valueOf(k) ? const Icon(Icons.check) : null, onTap: () => Navigator.of(c).pop('$ch')),
            ]),
          ),
        );
        if (v == null) return;
        update(() => _values[k.title] = v);
        await runAction(k, value: v);
      case ExploreKind.typeToggle:
        if (k.chars.isEmpty) return;
        final cur = k.chars.map((e) => '$e').toList().indexOf(_valueOf(k));
        final v = '${k.chars[(cur + 1) % k.chars.length]}';
        update(() => _values[k.title] = v);
        await runAction(k, value: v);
    }
  }

  String _label(Explore k) {
    if (k.type_ == ExploreKind.typeText) {
      final v = _valueOf(k);
      return v.isEmpty ? '${k.title}: 点击输入' : '${k.title}: $v';
    }
    if (k.type_ == ExploreKind.typeSelect || k.type_ == ExploreKind.typeToggle) return '${k.title}: ${_valueOf(k)}';
    return k.title;
  }

  Future<void> reload() async {
    update(() {
      _kinds = null;
      _error = '';
      _pager = null;
      _selected = -1;
    });
    try {
      final list = await BookSearchService.instance.exploreKinds(widget.source);
      update(() => _kinds = list);
      final first = list.indexWhere(isList);
      if (first >= 0) await select(first);
    } catch (e) {
      update(() {
        _kinds = [];
        _error = '$e';
      });
    }
  }

  Future<void> select(int i) async {
    final k = kinds[i];
    if (isAction(k)) return _tapAction(k);
    if (!isList(k)) {
      Toast.show('发现按钮错误: ${k.title}');
      return;
    }
    final p = FoundPager(widget.source, k.url);
    update(() {
      _selected = i;
      _pager = p;
      _findFilter = '';
    });
    // a 时光源 list asks `findfilter(url)` first (0x1058850); a page answer shows the filter button
    if (SourceFilter.supports(widget.source)) {
      final f = await SourceFilter.findFilter(widget.source, k.url);
      if (!identical(_pager, p)) return;
      update(() => _findFilter = f);
    }
    await p.next();
    update();
  }

  /// The `findfilter` answer of the list shown.
  String _findFilter = '';

  /// 0x10591a4: the filter page, then the list from its first page.
  Future<void> _openFilter() async {
    final p = _pager;
    if (p == null) return;
    await SourceFilter.open(widget.source, _findFilter);
    update();
    await p.reset();
    update();
  }

  Future<void> _more() async {
    final p = _pager;
    if (p == null) return;
    update();
    await p.next();
    update();
  }

  Future<void> _allKinds() async {
    final i = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final shown = [for (var i = 0; i < kinds.length; i++) if (_filter.isEmpty || kinds[i].title.contains(_filter)) i];
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(c).size.height * 0.7,
            child: Column(children: [
              const Padding(padding: EdgeInsets.all(12), child: Text('所有发现', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  decoration: const InputDecoration(hintText: '搜索标签...', prefixIcon: Icon(Icons.search), isDense: true),
                  onChanged: (v) => set(() => _filter = v.trim()),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final i in shown) ChoiceChip(label: Text(kinds[i].title), selected: i == _selected, onSelected: (_) => Navigator.of(c).pop(i)),
                  ]),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (i != null) await select(i);
  }

  @override
  Widget build(BuildContext context) {
    if (_kinds == null) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error), TextButton(onPressed: reload, child: const Text('重载'))]));
    }
    final p = _pager;
    return Column(children: [
      SizedBox(
        height: 48,
        child: Row(children: [
          Expanded(
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              for (var i = 0; i < kinds.length; i++)
                if (kinds[i].title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                    child: kinds[i].type_ == ExploreKind.typeTitle
                        ? Center(child: Text(kinds[i].title, style: const TextStyle(fontWeight: FontWeight.w600)))
                        : isAction(kinds[i])
                            ? ActionChip(key: Key('kind_$i'), label: Text(_label(kinds[i])), onPressed: () => select(i))
                            : ChoiceChip(key: Key('kind_$i'), label: Text(kinds[i].title), selected: i == _selected, onSelected: (_) => select(i)),
                  ),
            ]),
          ),
          if (SourceFilter.isPage(_findFilter))
            IconButton(key: const Key('found_filter'), tooltip: '筛选', icon: const Icon(Icons.filter_list_alt), onPressed: _openFilter),
          IconButton(tooltip: '所有发现', icon: const Icon(Icons.apps), onPressed: kinds.isEmpty ? null : _allKinds),
        ]),
      ),
      Expanded(
        child: p == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: () async {
                  await p.reset();
                  update();
                },
                child: p.books.isEmpty && !p.loading
                    ? ListView(children: [SizedBox(height: 160, child: Center(child: Text(p.error.isNotEmpty ? p.error : '没有下一页了')))])
                    : BookList(
                        key: Key('found_list_$_selected'),
                        books: p.books,
                        islist: widget.islist,
                        hasMore: p.hasMore,
                        isLoading: p.loading,
                        onLoadMore: _more,
                        onTap: (b) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: b))),
                      ),
              ),
      ),
    ]);
  }
}
