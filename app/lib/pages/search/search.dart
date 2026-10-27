// pages/search/search.dart — `Search`: one multi-source search run (original class `Search`: 「开始搜索 」 / 「结束搜索 」 /
// 「搜索错误: 」 logs, pool size `Common.qreadpool`). Results of all sources are merged by name + author into [SearchHit]s (the
// first copy found is shown, the others are alternative origins); progress = sources finished / sources searched.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/book.dart';
import '../../models/source.dart';
import 'book_search_service.dart';

class SearchHit {
  final Book book;

  /// Every copy found (first = [book]).
  final List<Book> origins;

  SearchHit(this.book) : origins = [book];

  String get key => mergeKey(book);

  static String mergeKey(Book b) => '${b.name.trim()}|${b.author.trim()}';
}

/// Word count of a result for the 字数 sorts: `12.5万字` → 125000, `3千` → 3000, `12345字` → 12345 (0xfdb42c).
int wordCountValue(String s) {
  final m = RegExp(r'(\d+\.?\d*)').firstMatch(s);
  if (m == null) return 0;
  final v = double.tryParse(m.group(1)!) ?? 0;
  if (s.contains('万')) return (v * 10000).round();
  if (s.contains('千')) return (v * 1000).round();
  return v.round();
}

class Search {
  final String key;
  final List<Source>? sources;
  final BookSearchService service;

  final List<SearchHit> hits = [];
  final Map<String, SearchHit> _byKey = {};
  int done = 0;
  int total = 0;
  bool running = false;
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  StreamSubscription<List<Book>>? _sub;
  final Completer<void> _finished = Completer<void>();

  Search(this.key, {this.sources, BookSearchService? service}) : service = service ?? BookSearchService.instance;

  /// Completes when every source answered or the search was cancelled.
  Future<void> get finished => _finished.future;

  void start() {
    total = sources?.length ?? total;
    running = true;
    debugPrint('开始搜索 $key');
    _sub = service.search(key, sources: sources).listen(
      _add,
      onError: (Object e) => debugPrint('搜索错误: $e'),
      onDone: _end,
    );
    revision.value++;
  }

  void _add(List<Book> list) {
    done++;
    for (final b in list) {
      final k = SearchHit.mergeKey(b);
      final hit = _byKey[k];
      if (hit == null) {
        final h = SearchHit(b);
        _byKey[k] = h;
        hits.add(h);
      } else if (!hit.origins.any((x) => x.origin == b.origin && x.bookUrl == b.bookUrl)) {
        hit.origins.add(b);
      }
    }
    revision.value++;
  }

  void _end() {
    running = false;
    debugPrint('结束搜索 $key');
    revision.value++;
    if (!_finished.isCompleted) _finished.complete();
  }

  Future<void> cancel() async {
    await _sub?.cancel();
    _end();
  }

  /// 包含匹配: name or author contains the key.
  List<SearchHit> get contains => hits.where((h) => h.book.name.contains(key) || h.book.author.contains(key)).toList();

  /// 精确匹配: name or author equals the key.
  List<SearchHit> get exact => hits.where((h) => h.book.name.trim() == key || h.book.author.trim() == key).toList();
}
