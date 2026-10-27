// widget/discovery/discovery_right.dart — `DiscoveryRightPage`: the explore categories of one source as tags and the endless
// book list of the selected tag (used by both discovery layouts).
//
// Explore kinds come from the engine (`exploreKinds`). Kinds with a url are list categories; the other Legado kind types (button
// / text / select / toggle with `action`, 「执行操作」 「点击按钮执行相关操作」, `findAction`) need the source's JS bridge.
// TODO(asm 0xfb87b4 / 0xfb824c): those run `/findaction` on the bound 轻阅读 backend in the original and are not wired here.
import 'package:flutter/material.dart';

import '../../models/explore.dart';
import '../../models/source.dart';
import '../../pages/book/book_detail_page.dart';
import '../../pages/search/book_search_service.dart';
import '../../pages/search/search_page.dart';
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

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant DiscoveryRightPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.bookSourceUrl != widget.source.bookSourceUrl) reload();
  }

  static bool isList(Explore k) => k.url.trim().isNotEmpty && k.type_ == 0;

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
    if (!isList(k)) {
      Toast.show('发现按钮错误: ${k.title}');
      return;
    }
    final p = FoundPager(widget.source, k.url);
    update(() {
      _selected = i;
      _pager = p;
    });
    await p.next();
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
                    child: ChoiceChip(key: Key('kind_$i'), label: Text(kinds[i].title), selected: i == _selected, onSelected: (_) => select(i)),
                  ),
            ]),
          ),
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
