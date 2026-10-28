// pages/book/book_change_yuan.dart — 换源 (`BookChangeYuan`, `_BookChangeYuanPageState`).
//
// Original (build 0x7ab140, tabs 0x7ada38 / 0x7adc14, menu 0x7adfa8 -> 0x107ae80): app bar 「切换书源」 with a 「菜单」 holding 「加载目录」
// (`loadDirectory`: the latest chapter of every candidate is fetched again), a progress bar while the sources are searched and the
// tab row 「匹配书籍」 · 「不同作者」 · 「相近名称」 over the candidates: the same book (name and author), the same name by another
// author, and similar names. (These strings sit next to rss_webview.dart in the binary, which is why the screen list puts them
// there; the functions belong to this page.) The candidates are the search results of the book name in every source; each row
// shows the cover, the name (` * ` marks the book's current source), 「来源：」 the source and 「最新：」 the latest chapter, loaded per
// candidate (「加载中」 / 「加载失败」 / 「未知」). Tapping a candidate pops it (book info filled); the caller replaces the shelf entry
// keeping the progress (`replaceShelfBook`). A long press opens the candidate's detail page.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/source.dart';
import '../../models/book.dart';
import '../../models/source.dart';
import '../../util/toast.dart';
import '../../widget/base_page.dart';
import '../../widget/book/booklist.dart';
import '../../widget/image/cached_cover_image.dart';
import '../../widget/ui/q_popup_menu_button.dart';
import '../search/book_search_service.dart';
import 'book_detail_page.dart';

/// The tab of the 换源 page a search result belongs to: 0 匹配书籍 (same name, same author or no author known), 1 不同作者 (same
/// name), 2 相近名称 (one name contains the other); null for other results.
int? changeSourceTab(Book book, Book found) {
  final a = book.name.trim(), b = found.name.trim();
  if (a.isEmpty || b.isEmpty) return null;
  if (a == b) return book.author.trim().isEmpty || book.author.trim() == found.author.trim() ? 0 : 1;
  return a.contains(b) || b.contains(a) ? 2 : null;
}

class BookChangeYuan extends StatefulWidget {
  final Book book;

  /// Sources to try (null = every enabled source).
  final List<Source>? sources;

  const BookChangeYuan({super.key, required this.book, this.sources});

  @override
  State<BookChangeYuan> createState() => _BookChangeYuanPageState();
}

class _BookChangeYuanPageState extends BasePage<BookChangeYuan> {
  static const List<String> tabs = ['匹配书籍', '不同作者', '相近名称'];

  final List<Book> _found = [];
  final Map<String, Future<String>> _latest = {};
  StreamSubscription<List<Book>>? _sub;
  int _done = 0;
  int _total = 0;
  bool _running = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    await Sourcedata.load();
    final sources = widget.sources ?? Sourcedata.enabledRaw.map(Source.fromJson).toList();
    await _sub?.cancel();
    update(() {
      _found.clear();
      _done = 0;
      _total = sources.length;
      _running = true;
    });
    _sub = BookSearchService.instance.search(widget.book.name, sources: sources).listen(
      (list) => update(() {
        _done++;
        for (final b in list) {
          if (changeSourceTab(widget.book, b) == null) continue;
          if (!_found.any((x) => x.bookUrl == b.bookUrl && x.origin == b.origin)) _found.add(b);
        }
      }),
      onError: (Object e) => Toast.show('$e', iserror: true),
      onDone: () => update(() => _running = false),
    );
  }

  void _stop() {
    _sub?.cancel();
    update(() => _running = false);
  }

  Future<String> _loadLatest(Book b, {bool reload = false}) async {
    if (b.latestChapterTitle.isNotEmpty && !reload) return b.latestChapterTitle;
    final list = await BookSearchService.instance.chapters(b);
    return list.isEmpty ? '未知' : list.last.name;
  }

  static String _key(Book b) => '${b.origin}|${b.bookUrl}';

  /// 加载目录 (0x107ae80): the latest chapter of every candidate is fetched again.
  void _loadDirectory() {
    update(() {
      for (final b in _found) {
        _latest[_key(b)] = _loadLatest(b, reload: true);
      }
    });
  }

  Future<void> _choose(Book b) async {
    Book chosen = b;
    try {
      chosen = await withLoading(() => BookSearchService.instance.bookInfo(b), message: '加载中');
    } catch (e) {
      debugPrint('换源详情失败 $e');
    }
    if (mounted) Navigator.of(context).pop(chosen);
  }

  /// 0x7adc14: one tab of the row (bold and underlined when selected).
  Widget _tabItem(int i, ColorScheme scheme) {
    final on = i == _tab;
    final n = _found.where((b) => changeSourceTab(widget.book, b) == i).length;
    return Expanded(
      child: InkWell(
        key: Key('change_tab_$i'),
        onTap: () => update(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            n == 0 ? tabs[i] : '${tabs[i]}($n)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: on ? FontWeight.w600 : FontWeight.normal,
              color: on ? scheme.primary : null,
              decoration: on ? TextDecoration.underline : null,
              decorationThickness: 2,
              decorationColor: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = [for (final b in _found) if (changeSourceTab(widget.book, b) == _tab) b];
    return Scaffold(
      appBar: AppBar(
        title: const Text('切换书源', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          _running
              ? IconButton(key: const Key('change_stop'), icon: const Icon(Icons.stop), onPressed: _stop)
              : IconButton(key: const Key('change_retry'), icon: const Icon(Icons.refresh), onPressed: _start),
          QPopupMenuButton<String>(
            key: const Key('change_menu'),
            tooltip: '菜单',
            items: const [QPopupMenuItem(value: 'loadDirectory', title: '加载目录', icon: Icons.list)],
            onSelected: (v) {
              if (v == 'loadDirectory') _loadDirectory();
            },
          ),
        ],
        bottom: _running
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2, value: _total == 0 ? null : _done / _total),
              )
            : null,
      ),
      body: Column(children: [
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
          child: Row(children: [for (var i = 0; i < tabs.length; i++) _tabItem(i, scheme)]),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(_running ? '加载中' : '未知'))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (c, i) {
                    final b = shown[i];
                    final current = b.origin == widget.book.origin;
                    final latest = _latest.putIfAbsent(_key(b), () => _loadLatest(b));
                    return ListTile(
                      key: Key('cand_${b.bookUrl}'),
                      leading: CachedCoverImage(url: b.coverUrl, title: b.name, width: 42, height: 56, borderRadius: BorderRadius.circular(4)),
                      title: Text('${b.name}${current ? ' * ' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.author.isEmpty ? '来源：${sourceName(b)}' : '${b.author} · 来源：${sourceName(b)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        FutureBuilder<String>(
                          future: latest,
                          builder: (c, s) => Text(
                            '最新：${s.hasError ? '加载失败' : (s.data ?? '加载中')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ]),
                      onTap: () => _choose(b),
                      onLongPress: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: b))),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
