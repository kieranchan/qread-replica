// api/sourceapi.dart - the entry points UI code calls to run book sources: search (single/many sources with a small result cache),
// explore, book info, table of contents, chapter content, image/cover decoding.
//
// Typical use:
//   final source = BookSource.fromJsonString(json);
//   final hits = await SourceApi.search(source, '斗破');           // List<SearchBook>
//   final book = hits.first.toBook();
//   await SourceApi.bookInfo(source, book);
//   final chapters = await SourceApi.chapters(source, book);       // List<BookChapter>
//   final text = await SourceApi.content(source, book, chapters[0], nextChapterUrl: chapters[1].getAbsoluteURL());
// Persisted/UI models: `book.toModel()`, `chapter.toModel()`, `kind.toExplore()`.
import 'dart:async';
import 'dart:typed_data';

import '../util/webbook/debug.dart';
import '../util/webbook/model/book.dart';
import '../util/webbook/model/book_chapter.dart';
import '../util/webbook/model/book_source.dart';
import '../util/webbook/model/search_book.dart';
import '../util/webbook/web_book.dart';

/// Result of one source in a multi-source search.
class SourceSearchResult {
  final BookSource source;
  final List<SearchBook> books;
  final Object? error;
  SourceSearchResult(this.source, this.books, [this.error]);
  bool get ok => error == null;
}

/// Short-lived cache of search results (the original keeps a `SearchCache`).
class SearchCache {
  final Duration ttl;
  final Map<String, (DateTime, List<SearchBook>)> _m = {};
  SearchCache({this.ttl = const Duration(minutes: 5)});

  List<SearchBook>? get(String key) {
    final e = _m[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.$1) > ttl) {
      _m.remove(key);
      return null;
    }
    return e.$2;
  }

  void put(String key, List<SearchBook> v) {
    if (_m.length > 200) _m.clear();
    _m[key] = (DateTime.now(), v);
  }

  void clear() => _m.clear();
}

abstract class SourceApi {
  static final SearchCache cache = SearchCache();

  /// A source JSON file may hold one source or an array.
  static List<BookSource> parseSources(String json) => BookSource.listFromJsonString(json);

  static WebBook webBook(BookSource source, {DebugLog? debug}) => WebBook(source, debug: debug);

  static String _cacheKey(BookSource s, String key, int page) => '${s.bookSourceUrl}\u0001$page\u0001$key';

  /// Searches [key] in [source]. Results are cached for a few minutes unless [useCache] is false.
  static Future<List<SearchBook>> search(BookSource source, String key, {int page = 1, bool useCache = true, DebugLog? debug}) async {
    final ck = _cacheKey(source, key, page);
    if (useCache) {
      final hit = cache.get(ck);
      if (hit != null) return hit;
    }
    final r = await WebBook(source, debug: debug).searchBook(key, page: page);
    if (useCache) cache.put(ck, r);
    return r;
  }

  /// Searches many sources with at most [concurrency] running at once; results arrive as each source finishes. Cancel the
  /// subscription to stop starting new sources. A failing source yields a result with `error` set instead of failing the stream.
  static Stream<SourceSearchResult> searchAll(List<BookSource> sources, String key, {int page = 1, int concurrency = 4, bool onlyEnabled = true}) {
    final list = onlyEnabled ? sources.where((s) => s.enabled).toList() : List<BookSource>.from(sources);
    final controller = StreamController<SourceSearchResult>();
    var next = 0;
    var running = 0;
    var cancelled = false;
    void pump() {
      while (!cancelled && running < concurrency && next < list.length) {
        final s = list[next++];
        running++;
        search(s, key, page: page).then((books) {
          if (!controller.isClosed) controller.add(SourceSearchResult(s, books));
        }).catchError((Object e) {
          if (!controller.isClosed) controller.add(SourceSearchResult(s, const [], e));
        }).whenComplete(() {
          running--;
          if (next >= list.length && running == 0) {
            if (!controller.isClosed) controller.close();
          } else {
            pump();
          }
        });
      }
      if (list.isEmpty && !controller.isClosed) controller.close();
    }

    controller.onListen = pump;
    controller.onCancel = () => cancelled = true;
    return controller.stream;
  }

  /// The discovery entries of [source] (`exploreUrl`, evaluated once and cached for JS rules).
  static Future<List<ExploreKind>> exploreKinds(BookSource source, {bool refresh = false}) => source.exploreKinds(refresh: refresh);

  /// One discovery page: [url] is an [ExploreKind.url].
  static Future<List<SearchBook>> explore(BookSource source, String url, {int page = 1, DebugLog? debug}) =>
      WebBook(source, debug: debug).exploreBook(url, page: page);

  /// Loads the detail page and fills [book] (returns the same object).
  static Future<Book> bookInfo(BookSource source, Book book, {bool canReName = true, DebugLog? debug}) =>
      WebBook(source, debug: debug).getBookInfo(book, canReName: canReName);

  /// The table of contents in reading order (apply `book.reverseCatalog` in the UI if the reader offers it).
  static Future<List<BookChapter>> chapters(BookSource source, Book book, {bool runPreUpdateJs = false, DebugLog? debug}) =>
      WebBook(source, debug: debug).getChapterList(book, runPreUpdate: runPreUpdateJs);

  /// Chapter text with paragraphs separated by newlines (and `<img src="...">` tags for images).
  static Future<String> content(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl, DebugLog? debug}) =>
      WebBook(source, debug: debug).getContent(book, chapter, nextChapterUrl: nextChapterUrl);

  /// Applies the content rule's `imageDecode` script to downloaded image [bytes].
  static Future<Uint8List> decodeImage(BookSource source, Book book, BookChapter? chapter, String imageUrl, Uint8List bytes) =>
      WebBook(source).decodeImage(book, chapter, imageUrl, bytes);

  /// Applies `coverDecodeJs` to downloaded cover [bytes].
  static Future<Uint8List> decodeCover(BookSource source, String coverUrl, Uint8List bytes, {Book? book}) =>
      WebBook(source).decodeCover(book, coverUrl, bytes);

  /// Runs the content rule's `payAction` script for a paid chapter (login/payment flows live in the script).
  static Future<Object?> payAction(BookSource source, Book book, BookChapter chapter) => WebBook(source).payAction(book, chapter);
}
