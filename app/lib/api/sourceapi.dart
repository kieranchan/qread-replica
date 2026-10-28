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
// 时光源 (sources whose `html` page runs in a web view, util/source/) take the same entry points: every call below hands them to
// util/source/time_source_api.dart.
import 'dart:async';
import 'dart:typed_data';

import '../util/http.dart';
import '../util/source/source.dart';
import '../util/source/time_source_api.dart';
import '../util/webbook/debug.dart';
import '../util/webbook/model/book.dart';
import '../util/webbook/model/book_chapter.dart';
import '../util/webbook/analyze_rule/js_extensions.dart';
import '../util/webbook/model/book_source.dart';
import '../util/webbook/model/shared_js_scope.dart';
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

  /// Drops the cached results of one source (keys start with its url).
  void removeSource(String sourceUrl) => _m.removeWhere((k, _) => k.startsWith('$sourceUrl\u0001'));
}

abstract class SourceApi {
  static final SearchCache cache = SearchCache();

  /// 重载书源线程 (0xe77e8c removes the source's runner from `sourcerun`): the replica has no long-lived runner per source, so the
  /// source's runtime state is dropped instead (cached search results, the resolved `jsLib`); the next call starts fresh.
  static void reloadSource(String sourceUrl) {
    cache.removeSource(sourceUrl);
    SharedJsScope.forget(sourceUrl);
    TimeSourceApi.reload(sourceUrl);
  }

  /// A source JSON file may hold one source or an array.
  static List<BookSource> parseSources(String json) => BookSource.listFromJsonString(json);

  static WebBook webBook(BookSource source, {DebugLog? debug}) => WebBook(source, debug: debug);

  static String _cacheKey(BookSource s, String key, int page) => '${s.bookSourceUrl}\u0001$page\u0001$key';

  /// Searches [key] in [source]. Results are cached for a few minutes unless [useCache] is false.
  /// [env] goes to a 时光源's `search(key, page, env)` (`searchone` for a single-source search).
  static Future<List<SearchBook>> search(BookSource source, String key, {int page = 1, bool useCache = true, DebugLog? debug, String env = 'search'}) async {
    final ck = _cacheKey(source, key, page);
    if (useCache) {
      final hit = cache.get(ck);
      if (hit != null) return hit;
    }
    final r = source.isTimeSource
        ? await TimeSourceApi.search(source, key, page: page, debug: debug, env: env)
        : await WebBook(source, debug: debug).searchBook(key, page: page);
    if (useCache) cache.put(ck, r);
    return r;
  }

  /// Searches many sources with at most [concurrency] running at once; results arrive as each source finishes. Cancel the
  /// subscription to stop starting new sources. A failing source yields a result with `error` set instead of failing the stream.
  static Stream<SourceSearchResult> searchAll(List<BookSource> sources, String key,
      {int page = 1, int concurrency = 4, bool onlyEnabled = true, String env = 'search'}) {
    final list = onlyEnabled ? sources.where((s) => s.enabled).toList() : List<BookSource>.from(sources);
    final controller = StreamController<SourceSearchResult>();
    var next = 0;
    var running = 0;
    var cancelled = false;
    void pump() {
      while (!cancelled && running < concurrency && next < list.length) {
        final s = list[next++];
        running++;
        search(s, key, page: page, env: env).then((books) {
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
  static Future<List<ExploreKind>> exploreKinds(BookSource source, {bool refresh = false}) =>
      source.isTimeSource ? TimeSourceApi.exploreKinds(source, refresh: refresh) : source.exploreKinds(refresh: refresh);

  /// Runs the `action` JavaScript of an explore kind (button / text / select / toggle) with `key` (the kind title) and `value`
  /// (what the user typed or chose; also stored with `source.put(key, value)` so rules read it back with `source.get(key)`).
  /// Returns the script result as text ('' for null / undefined).
  static Future<String> exploreAction(BookSource source, String action, {String key = '', String? value}) async {
    if (source.isTimeSource) return TimeSourceApi.exploreAction(source, action, key: key, value: value);
    if (value != null && key.isNotEmpty) source.put(key, value);
    final r = await SourceJsExtensions(source).runJs(action, values: {'key': key, 'value': value, 'result': value});
    if (r == null) return '';
    final s = r is String ? r : '$r';
    return s == 'undefined' || s == 'null' ? '' : s;
  }

  /// One discovery page: [url] is an [ExploreKind.url].
  static Future<List<SearchBook>> explore(BookSource source, String url, {int page = 1, DebugLog? debug}) => source.isTimeSource
      ? TimeSourceApi.explore(source, url, page: page, debug: debug)
      : WebBook(source, debug: debug).exploreBook(url, page: page);

  /// Loads the detail page and fills [book] (returns the same object).
  static Future<Book> bookInfo(BookSource source, Book book, {bool canReName = true, DebugLog? debug}) => source.isTimeSource
      ? TimeSourceApi.bookInfo(source, book, debug: debug)
      : WebBook(source, debug: debug).getBookInfo(book, canReName: canReName);

  /// The table of contents in reading order (apply `book.reverseCatalog` in the UI if the reader offers it).
  static Future<List<BookChapter>> chapters(BookSource source, Book book, {bool runPreUpdateJs = false, DebugLog? debug}) => source.isTimeSource
      ? TimeSourceApi.chapters(source, book, debug: debug)
      : WebBook(source, debug: debug).getChapterList(book, runPreUpdate: runPreUpdateJs);

  /// Chapter text with paragraphs separated by newlines (and `<img src="...">` tags for images).
  static Future<String> content(BookSource source, Book book, BookChapter chapter, {String? nextChapterUrl, DebugLog? debug}) => source.isTimeSource
      ? TimeSourceApi.content(source, book, chapter, debug: debug)
      : WebBook(source, debug: debug).getContent(book, chapter, nextChapterUrl: nextChapterUrl);

  /// Applies the content rule's `imageDecode` script to downloaded image [bytes].
  static Future<Uint8List> decodeImage(BookSource source, Book book, BookChapter? chapter, String imageUrl, Uint8List bytes) => source.isTimeSource
      ? TimeSourceApi.decodeImage(source, imageUrl, bytes)
      : WebBook(source).decodeImage(book, chapter, imageUrl, bytes);

  /// Applies `coverDecodeJs` to downloaded cover [bytes].
  static Future<Uint8List> decodeCover(BookSource source, String coverUrl, Uint8List bytes, {Book? book}) =>
      WebBook(source).decodeCover(book, coverUrl, bytes);

  /// Runs the content rule's `payAction` script for a paid chapter (login/payment flows live in the script).
  static Future<Object?> payAction(BookSource source, Book book, BookChapter chapter) =>
      source.isTimeSource ? TimeSourceApi.payAction(source, book, chapter) : WebBook(source).payAction(book, chapter);

  /// Downloads a source file (JSON object or array) from [url] and parses it.
  static Future<List<BookSource>> importFromUrl(String url) async {
    final res = await AppHttp.send(HttpRequest(url: url, useCookieJar: false));
    if (!res.isSuccessful) throw WebBookException('下载书源失败: HTTP ${res.statusCode}');
    return parseSources(AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType).trim());
  }

  /// The source debugger (Legado `Debug.startDebug`): [key] selects where the chain starts and it then runs down to the content of
  /// the first chapter, logging every step:
  ///   * a keyword -> search, then the first result's details, toc and first chapter
  ///   * an absolute url -> that book's detail page, toc, first chapter
  ///   * `title::url` -> that explore page, then the first result as above
  ///   * `++url` -> that toc url, then the first chapter
  ///   * `--url` -> that chapter url only
  /// Errors end the run and are logged; the returned [DebugLog] holds all lines.
  static Future<DebugLog> debug(BookSource source, String key, {void Function(String line)? onLine, void Function(String step, String body)? onBody}) async {
    if (source.isTimeSource) return TimeSourceApi.debug(source, key, onLine: onLine, onBody: onBody);
    final log = DebugLog(onLine: onLine, onBody: onBody);
    final web = WebBook(source, debug: log);
    try {
      Book? book;
      if (key.startsWith('--')) {
        final url = key.substring(2);
        final b = Book(bookUrl: url, origin: source.bookSourceUrl);
        final ch = BookChapter(url: url, title: '调试', baseUrl: url, bookUrl: url);
        final text = await web.getContent(b, ch);
        log.log('︽正文页解析完成 ${text.length}');
        return log;
      }
      if (key.startsWith('++')) {
        book = Book(bookUrl: key.substring(2), origin: source.bookSourceUrl)..tocUrl = key.substring(2);
      } else if (RegExp(r'^https?://', caseSensitive: false).hasMatch(key)) {
        book = Book(bookUrl: key, origin: source.bookSourceUrl, originName: source.bookSourceName);
        await web.getBookInfo(book);
        log.log('︽详情页解析完成');
      } else {
        final List<SearchBook> list;
        if (key.contains('::')) {
          list = await web.exploreBook(key.substring(key.indexOf('::') + 2));
          log.log('︽发现页解析完成 ${list.length}');
        } else {
          list = await web.searchBook(key);
          log.log('︽搜索页解析完成 ${list.length}');
        }
        if (list.isEmpty) {
          log.log('≡未获取到书籍');
          return log;
        }
        book = list.first.toBook();
        await web.getBookInfo(book);
        log.log('︽详情页解析完成');
      }
      final chapters = await web.getChapterList(book);
      log.log('︽目录页解析完成 ${chapters.length}');
      final first = chapters.firstWhere((c) => !c.isVolume, orElse: () => chapters.first);
      final idx = chapters.indexOf(first);
      final next = idx + 1 < chapters.length ? chapters[idx + 1].getAbsoluteURL() : null;
      final text = await web.getContent(book, first, nextChapterUrl: next);
      log.log('︽正文页解析完成 ${text.length}');
    } catch (e) {
      log.log('error: $e');
    }
    return log;
  }
}
