// pages/search/engine_book_search_service.dart — [BookSearchService] on top of the book-source engine (`api/sourceapi.dart`).
//
// Sources come from the source store (`Sourcedata`, full Legado maps) and are turned into engine `BookSource`s; engine books and
// chapters are converted to the persisted models with `toModel()` / `fromModel()`. Shelf-only fields (group, progress, flags)
// are carried over from the input book, because the engine model has no string groups.
//
// Wiring (lead): `BookSearchService.instance = EngineBookSearchService();` at start-up, after `Sourcedata.load()`.
import 'dart:async';

import '../../api/sourceapi.dart';
import '../../data/source.dart';
import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../models/explore.dart';
import '../../models/source.dart';
import '../../storage/storage.dart';
import '../../widget/book_page.dart' show BookVariables;
import '../../util/webbook/model/book.dart' as wb;
import '../../util/webbook/model/book_chapter.dart' as wb;
import '../../util/webbook/model/book_source.dart';
import 'book_search_service.dart';

class EngineBookSearchService implements BookSearchService {
  /// Prefs key of the search thread count (搜索线程, default 6).
  static const String threadsKey = 'searchpppl';

  /// Number of sources searched at once (`searchpppl`, clamped 1..32).
  int get concurrency => Storage.getString(threadsKey).isEmpty ? 6 : Storage.getInt(threadsKey, 6).clamp(1, 32);

  /// The engine source of a store entry (null when the source is unknown).
  BookSource? sourceOf(String url) {
    final raw = Sourcedata.byUrl(url);
    if (raw == null) return null;
    return BookSource.fromJson(Map<String, dynamic>.from(raw));
  }

  BookSource _engineSource(Source s) => sourceOf(s.bookSourceUrl) ?? BookSource.fromJson(s.toJson());

  BookSource _sourceForBook(Book b) {
    final s = sourceOf(b.origin);
    if (s == null) throw StateError('书源不存在: ${b.origin}');
    return s;
  }

  List<BookSource> _sources(List<Source>? sources) {
    if (sources != null) return [for (final s in sources) _engineSource(s)];
    return [for (final m in Sourcedata.enabledRaw) BookSource.fromJson(Map<String, dynamic>.from(m))];
  }

  /// Engine books seen in search / explore / info results, keyed by origin + bookUrl. `models/book.dart` has no `variable`
  /// field, so the `@put` variables a search rule stores (e.g. `{bid}` used by `@get:{bid}` in the toc url) would be lost by the
  /// model round trip; the next engine call for the same book starts from the cached engine object instead.
  /// TODO: persist `variable` with the shelf book (needs a field in models/book.dart, data area).
  final Map<String, wb.Book> _engineBooks = {};

  static String _key(String origin, String bookUrl) => '$origin\u0001$bookUrl';

  Book _remember(wb.Book b) {
    if (_engineBooks.length > 500) _engineBooks.clear();
    _engineBooks[_key(b.origin, b.bookUrl)] = b;
    return _model(b);
  }

  wb.Book _engineBook(Book b) {
    final cached = _engineBooks[_key(b.origin, b.bookUrl)];
    if (cached == null) return wb.Book.fromModel(b);
    // shelf fields may have changed since the engine object was cached
    cached
      ..durChapterIndex = b.durChapterIndex
      ..durChapterTitle = b.durChapterTitle.isEmpty ? cached.durChapterTitle : b.durChapterTitle
      ..reverseCatalog = b.reverseCatalog;
    if (b.tocUrl.isNotEmpty) cached.tocUrl = b.tocUrl;
    return cached;
  }

  static Book _model(wb.Book b) => b.toModel()..bookgroup = '';

  /// Copies the shelf-only fields of [from] onto the fresh engine result [to].
  static Book _keepShelfFields(Book from, Book to) => to
    ..bookgroup = from.bookgroup
    ..durChapterIndex = from.durChapterIndex
    ..durChapterPos = from.durChapterPos
    ..durChapterTitle = from.durChapterTitle.isNotEmpty ? from.durChapterTitle : to.durChapterTitle
    ..durChapterTime = from.durChapterTime
    ..readchapter = from.readchapter
    ..update = from.update
    ..isredupdate = from.isredupdate
    ..useReplaceRule = from.useReplaceRule
    ..useai = from.useai
    ..lastCheckTime = from.lastCheckTime
    ..latestChapterTime = to.latestChapterTime == 0 ? from.latestChapterTime : to.latestChapterTime;

  Stream<List<Book>> _searchMany(List<BookSource> list, String key, bool Function(Book b) keep, {String env = 'search'}) {
    return SourceApi.searchAll(list, key, concurrency: concurrency, onlyEnabled: false, env: env)
        .map((r) => [for (final s in r.books) _remember(s.toBook())].where(keep).toList());
  }

  @override
  Stream<List<Book>> search(String key, {List<Source>? sources, String env = 'search'}) => _searchMany(_sources(sources), key, (_) => true, env: env);

  @override
  Future<List<Explore>> exploreKinds(Source source) async {
    final kinds = await SourceApi.exploreKinds(_engineSource(source));
    return [for (final k in kinds) k.toExplore()];
  }

  @override
  Future<List<Book>> explore(Source source, String url, int page) async {
    final list = await SourceApi.explore(_engineSource(source), url, page: page);
    return [for (final s in list) _remember(s.toBook())];
  }

  /// The engine copy of [b] with the user's book variable (「设置书籍变量」, `custom`) loaded from the file store.
  Future<wb.Book> _engineBookWithVariable(Book b) async {
    final eb = _engineBook(b);
    if (!b.isqread && eb.getVariable('custom') == null) {
      final v = await BookVariables.custom(b.bookUrl);
      if (v.isNotEmpty) eb.putVariable('custom', v);
    }
    return eb;
  }

  @override
  Future<Book> bookInfo(Book book) async {
    final src = _sourceForBook(book);
    final r = await SourceApi.bookInfo(src, await _engineBookWithVariable(book));
    return _keepShelfFields(book, _remember(r));
  }

  @override
  Future<List<BookChapter>> chapters(Book book) async {
    final src = _sourceForBook(book);
    var eb = await _engineBookWithVariable(book);
    if (eb.tocUrl.isEmpty || eb.tocUrl.contains('@get:')) eb = await SourceApi.bookInfo(src, eb);
    _engineBooks[_key(eb.origin, eb.bookUrl)] = eb;
    final list = await SourceApi.chapters(src, eb);
    return [for (final c in list) c.toModel()];
  }

  @override
  Future<String> content(Book book, BookChapter chapter) async {
    final src = _sourceForBook(book);
    return SourceApi.content(src, await _engineBookWithVariable(book), wb.BookChapter.fromModel(chapter, bookUrl: book.bookUrl));
  }

  @override
  Stream<List<Book>> changeSourceCandidates(Book book, {List<Source>? sources}) {
    return _searchMany(_sources(sources), book.name,
        (b) => b.name == book.name && (book.author.isEmpty || b.author == book.author) && b.bookUrl != book.bookUrl);
  }
}
