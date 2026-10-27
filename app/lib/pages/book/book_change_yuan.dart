// pages/book/book_change_yuan.dart — 换源 (`BookChangeYuan`, `_BookChangeYuanPageState`).
//
// Candidates come from the engine (same name, author when known) while the search runs; each row shows the cover, the name,
// 「来源：」 the source and 「最新：」 the latest chapter, which is loaded per candidate (`loadDirectory`: 「加载中」 / 「加载失败」 /
// 「未知」). Tapping a candidate pops it (book info filled); the caller replaces the shelf entry keeping the progress
// (`replaceShelfBook`). A long press opens the candidate's detail page.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/source.dart';
import '../../models/book.dart';
import '../../models/source.dart';
import '../../util/toast.dart';
import '../../widget/base_page.dart';
import '../../widget/book/booklist.dart';
import '../../widget/image/cached_cover_image.dart';
import '../search/book_search_service.dart';
import 'book_detail_page.dart';

class BookChangeYuan extends StatefulWidget {
  final Book book;

  /// Sources to try (null = every enabled source).
  final List<Source>? sources;

  const BookChangeYuan({super.key, required this.book, this.sources});

  @override
  State<BookChangeYuan> createState() => _BookChangeYuanPageState();
}

class _BookChangeYuanPageState extends BasePage<BookChangeYuan> {
  final List<Book> _found = [];
  final Map<String, Future<String>> _latest = {};
  StreamSubscription<List<Book>>? _sub;
  int _done = 0;
  int _total = 0;
  bool _running = false;

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
    _sub = BookSearchService.instance.changeSourceCandidates(widget.book, sources: sources).listen(
      (list) => update(() {
        _done++;
        for (final b in list) {
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

  Future<String> _loadLatest(Book b) async {
    if (b.latestChapterTitle.isNotEmpty) return b.latestChapterTitle;
    final list = await BookSearchService.instance.chapters(b);
    return list.isEmpty ? '未知' : list.last.name;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.book.name}${_total > 0 ? ' ($_done/$_total)' : ''}'),
        centerTitle: true,
        actions: [
          _running
              ? IconButton(key: const Key('change_stop'), icon: const Icon(Icons.stop), onPressed: _stop)
              : IconButton(key: const Key('change_retry'), icon: const Icon(Icons.refresh), onPressed: _start),
        ],
        bottom: _running ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: _found.isEmpty
          ? Center(child: Text(_running ? '加载中' : '未知'))
          : ListView.builder(
              itemCount: _found.length,
              itemBuilder: (c, i) {
                final b = _found[i];
                final current = b.origin == widget.book.origin;
                final latest = _latest.putIfAbsent('${b.origin}|${b.bookUrl}', () => _loadLatest(b));
                return ListTile(
                  key: Key('cand_${b.bookUrl}'),
                  leading: CachedCoverImage(url: b.coverUrl, title: b.name, width: 42, height: 56, borderRadius: BorderRadius.circular(4)),
                  title: Text('${b.name}${current ? ' * ' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('来源：${sourceName(b)}', maxLines: 1, overflow: TextOverflow.ellipsis),
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
    );
  }
}
