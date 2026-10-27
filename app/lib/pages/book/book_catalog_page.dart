// pages/book/book_catalog_page.dart — 目录 (`BookCatalogPage`): three tabs 目录 / 书签 / 笔记.
//
// Original strings in code order: 「正序」/「倒序」 (the book's `reverseCatalog`), 「刷新」 → 「刷新成功」 / 「刷新失败:」, 「导出」 →
// 「是否将《…》的缓存导出为txt？」 「确认导出」 (CacheTxtProgressDialog), search fields 「搜索标题」 / 「搜索笔记」, 「加载失败」 + 「重试」,
// 「暂无章节」, 「暂无书签」, 「还没有笔记」, 「共 n 章」, 「未知章节」, bookmark long press 「书签操作」 「确定要删除当前书签吗？」 (「删除失败:」).
// Cached chapters are marked (BookContent file exists); the current chapter is highlighted and scrolled into view. A tap opens
// the reader at that chapter through `Nav.openReader(chapterIndex:)`.
import 'package:flutter/material.dart';

import '../../common/nav.dart';
import '../../data/bookself.dart';
import '../../data/note_data_n.dart';
import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../models/note.dart';
import '../../read/api/book_content.dart';
import '../../util/toast.dart';
import '../../widget/base_page.dart';
import '../../widget/book/booktxt.dart';
import '../../widget/book/toc_cache.dart';
import '../../widget/book_page.dart';
import 'book_notes_page.dart';

class BookCatalogPage extends StatefulWidget {
  final Book book;

  /// Already loaded chapters (skips the cache / engine).
  final List<BookChapter>? chapters;

  const BookCatalogPage({super.key, required this.book, this.chapters});

  @override
  State<BookCatalogPage> createState() => _BookCatalogPageState();
}

class _BookCatalogPageState extends BasePage<BookCatalogPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _search = TextEditingController();
  List<BookChapter>? _chapters;
  List<BookNote>? _marks;
  String _error = '';
  bool _reverse = false;
  Set<int> _cached = {};
  final ScrollController _scroll = ScrollController();

  Book get book => BookSelfN.get(widget.book.bookUrl) ?? widget.book;

  @override
  void initState() {
    super.initState();
    _reverse = book.reverseCatalog;
    _tabs.addListener(() => update(() => _search.clear()));
    _load(initial: widget.chapters);
    _loadMarks();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({List<BookChapter>? initial, bool refresh = false}) async {
    update(() => _error = '');
    try {
      final list = initial ?? await TocCache.load(book, refresh: refresh);
      final cached = <int>{};
      if (!isLocalShelfBook(book)) {
        for (var i = 0; i < list.length; i++) {
          if (const BookContent().existsSync(book.bookUrl, i)) cached.add(i);
        }
      }
      update(() {
        _chapters = list;
        _cached = cached;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
      if (refresh) Toast.show('刷新成功');
    } catch (e) {
      update(() => _error = '$e');
      if (refresh) Toast.show('刷新失败:$e', iserror: true);
    }
  }

  Future<void> _loadMarks() async {
    final m = await NoteDataN.bookmarksOfBook(book.bookUrl);
    update(() => _marks = m);
  }

  void _jumpToCurrent() {
    final n = _chapters?.length ?? 0;
    if (n == 0 || !_scroll.hasClients) return;
    final i = _reverse ? n - 1 - book.durChapterIndex : book.durChapterIndex;
    final off = (i.clamp(0, n - 1) * 48.0 - 200).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(off);
  }

  Future<void> _toggleOrder() async {
    setState(() => _reverse = !_reverse);
    if (BookSelfN.contains(book.bookUrl)) await BookSelfN.setReverseCatalog(book.bookUrl, _reverse);
  }

  Future<void> _export() async {
    final list = _chapters;
    if (list == null) return;
    if (!await confirm('确认导出', '是否将《${book.name}》的缓存导出为txt？')) return;
    if (!mounted) return;
    await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => CacheTxtProgressDialog(book: book, chapters: list));
  }

  void _open(int index) => Nav.openReader(context, book, chapterIndex: index, chapters: _chapters);

  Future<void> _deleteMark(BookNote m) async {
    if (!await confirm('书签操作', '确定要删除当前书签吗？')) return;
    try {
      await NoteDataN.delete(m.id);
      await _loadMarks();
    } catch (e) {
      Toast.show('删除失败:$e', iserror: true);
    }
  }

  Widget _chapterTab() {
    final all = _chapters;
    if (_error.isNotEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('加载失败'),
          Text(_error, style: const TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
          TextButton(onPressed: () => _load(refresh: true), child: const Text('重试')),
        ]),
      );
    }
    if (all == null) return const Center(child: CircularProgressIndicator());
    if (all.isEmpty) return const Center(child: Text('暂无章节'));
    final key = _search.text.trim();
    var list = [for (var i = 0; i < all.length; i++) (i, all[i])];
    if (_reverse) list = list.reversed.toList();
    if (key.isNotEmpty) list = list.where((e) => e.$2.name.contains(key)).toList();
    final cur = book.durChapterIndex;
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: Row(children: [
          Text('共 ${all.length} 章', key: const Key('catalog_count'), style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          TextButton.icon(key: const Key('catalog_order'), onPressed: _toggleOrder, icon: const Icon(Icons.swap_vert, size: 18), label: Text(_reverse ? '倒序' : '正序')),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          itemExtent: 48,
          itemCount: list.length,
          itemBuilder: (c, i) {
            final (idx, ch) = list[i];
            final current = idx == cur;
            return ListTile(
              key: Key('chapter_$idx'),
              dense: true,
              contentPadding: EdgeInsets.only(left: ch.isVolume ? 12 : 24, right: 16),
              title: Text(ch.name.isEmpty ? '未知章节' : ch.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: ch.isVolume || current ? FontWeight.bold : FontWeight.normal,
                    color: current ? scheme.primary : null,
                  )),
              trailing: _cached.contains(idx)
                  ? Icon(Icons.download_done, key: Key('cached_$idx'), size: 16, color: scheme.primary)
                  : (ch.isPay || ch.isVip ? const Icon(Icons.lock_outline, size: 16) : null),
              onTap: ch.isVolume ? null : () => _open(idx),
            );
          },
        ),
      ),
    ]);
  }

  Widget _markTab() {
    final marks = _marks;
    if (marks == null) return const Center(child: CircularProgressIndicator());
    final key = _search.text.trim();
    final list = key.isEmpty ? marks : marks.where((m) => m.chapterName.contains(key) || m.selectedText.contains(key)).toList();
    if (list.isEmpty) return const Center(child: Text('暂无书签'));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (c, i) {
        final m = list[i];
        return ListTile(
          title: Text(m.chapterName.isEmpty ? '未知章节' : m.chapterName),
          subtitle: Text(m.selectedText, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Text(noteTime(m.updateTime), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          onTap: () => _open(m.chapterIndex),
          onLongPress: () => _deleteMark(m),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hint = _tabs.index == 2 ? '搜索笔记' : '搜索标题';
    return Scaffold(
      appBar: AppBar(
        title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        actions: [
          IconButton(key: const Key('catalog_refresh'), tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: () => _load(refresh: true)),
          IconButton(tooltip: '导出', icon: const Icon(Icons.outbond_outlined), onPressed: isLocalShelfBook(book) ? null : _export),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: '目录'), Tab(text: '书签'), Tab(text: '笔记')]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            key: const Key('catalog_search'),
            controller: _search,
            onChanged: (_) => update(),
            decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            _chapterTab(),
            _markTab(),
            BookNotesView(book: book, filter: _search.text),
          ]),
        ),
      ]),
    );
  }
}
