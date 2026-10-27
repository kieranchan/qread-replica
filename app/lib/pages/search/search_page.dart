// pages/search/search_page.dart — `SearchPage`: the book list of one explore category (发现 → a tag), paged without end.
//
// Original (`_SearchPageState`, closure 0x7476e8): loads page n+1 when the list nears its end; stops with 「没有下一页了」 when a
// page is empty (「空」) or repeats the previous page (「和前面一样」); errors 「搜索错误: 」 / 「书元不存在,或者已经搜索结束」. Tapping a
// book opens its detail page.
import 'package:flutter/material.dart';

import '../../models/book.dart';
import '../../models/source.dart';
import '../../widget/base_page.dart';
import '../../widget/book/booklist.dart';
import '../book/book_detail_page.dart';
import 'book_search_service.dart';

/// Paging state of an explore list (shared by SearchPage, the discovery pages and the exploration components).
class FoundPager {
  final Source source;
  final String url;
  final List<Book> books = [];
  int page = 0;
  bool hasMore = true;
  bool loading = false;
  String error = '';
  String _lastSignature = '';

  FoundPager(this.source, this.url);

  /// Loads the next page; returns false when nothing more came.
  Future<bool> next() async {
    if (loading || !hasMore) return false;
    loading = true;
    error = '';
    try {
      final list = await BookSearchService.instance.explore(source, url, page + 1);
      final sig = list.map((b) => b.bookUrl).join('\n');
      if (list.isEmpty || sig == _lastSignature) {
        debugPrint(list.isEmpty ? '空' : '和前面一样');
        hasMore = false;
        return false;
      }
      _lastSignature = sig;
      page++;
      final known = books.map((b) => b.bookUrl).toSet();
      books.addAll(list.where((b) => known.add(b.bookUrl)));
      return true;
    } catch (e) {
      error = '搜索错误: $e';
      hasMore = false;
      return false;
    } finally {
      loading = false;
    }
  }

  Future<void> reset() async {
    books.clear();
    page = 0;
    hasMore = true;
    _lastSignature = '';
    await next();
  }
}

class SearchPage extends StatefulWidget {
  final Source source;
  final String url;
  final String title;

  const SearchPage({super.key, required this.source, required this.url, this.title = '发现'});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends BasePage<SearchPage> with AutomaticKeepAliveClientMixin {
  late final FoundPager _pager = FoundPager(widget.source, widget.url);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    update();
    await _pager.next();
    update();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = _pager;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async {
          await p.reset();
          update();
        },
        child: p.books.isEmpty && !p.loading
            ? ListView(children: [
                SizedBox(height: 200, child: Center(child: Text(p.error.isNotEmpty ? p.error : '没有下一页了', key: const Key('found_empty')))),
              ])
            : BookList(
                key: const Key('found_list'),
                books: p.books,
                islist: true,
                hasMore: p.hasMore,
                isLoading: p.loading,
                onLoadMore: _more,
                onTap: (b) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: b))),
              ),
      ),
    );
  }
}
