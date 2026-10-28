// util/source/time_source_api.dart — not a file of the original: the 时光源 branch of `api/sourceapi.dart`. `SourceApi` hands every
// call for a 时光源 here, so search, discovery, detail, change source, the reader, downloads and the debugger use these sources
// exactly like Legado sources. This file converts between the page's JSON (models/book.dart, models/bookchapter.dart — the
// original's own models) and the engine models the rest of the app uses (util/webbook/model/*).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../models/book.dart' as m;
import '../../storage/storage.dart';
import '../legado/html_formatter.dart';
import '../webbook/debug.dart';
import '../webbook/model/book.dart';
import '../webbook/model/book_chapter.dart';
import '../webbook/model/book_source.dart';
import '../webbook/model/search_book.dart';
import 'baswebview.dart';
import 'cache.dart';
import 'run.dart';
import 'source.dart';

abstract class TimeSourceApi {
  static Future<SourceRun> runOf(BookSource s) => SourceRun.of(s.toBaseSource());

  /// The step names of the debugger (util/webbook/debug.dart) for the page's `text(type, html)` output.
  static const List<String> _steps = ['search', 'book', 'toc', 'content'];

  static void Function(int, String)? _text(DebugLog? d) =>
      d == null ? null : (t, html) => d.body(t >= 0 && t < _steps.length ? _steps[t] : 'search', html);

  static void Function(String)? _log(DebugLog? d) => d?.log;

  static SearchBook _searchBook(BookSource s, m.Book b) {
    final e = Book.fromModel(b)
      ..origin = s.bookSourceUrl
      ..originName = s.bookSourceName;
    return e.toSearchBook();
  }

  /// `search(key, page, env)`: [env] `search`, or `searchone` when this is the only source searched (筛选 applies then).
  static Future<List<SearchBook>> search(BookSource s, String key, {int page = 1, String env = 'search', DebugLog? debug}) async {
    final run = await runOf(s);
    final list = await run.search(key, page, env: env, log: _log(debug), text: _text(debug));
    return [for (final b in list) _searchBook(s, b)];
  }

  /// 筛选 (`filter()` 0xfdb268 for the single-source search, `findfilter(url)` 0x1058fa4 for a discovery list): the page answers
  /// an http url or a `data:` html page that lets the user choose (it keeps the choice with `cache.set`), or nothing.
  static Future<String> filter(BookSource s) async => (await runOf(s)).filter();

  static Future<String> findFilter(BookSource s, String url) async => (await runOf(s)).findfilter(url);

  /// A filter answer that is a page to open (0xfdbecc / 0x746e28 test `http` / `data` at the start).
  static bool isFilterPage(String v) => v.startsWith('http') || v.startsWith('data');

  static Future<List<SearchBook>> explore(BookSource s, String url, {int page = 1, DebugLog? debug}) async {
    final run = await runOf(s);
    final list = await run.find(url, page, log: _log(debug), text: _text(debug));
    return [for (final b in list) _searchBook(s, b)];
  }

  /// 0xfb9864: the discovery entries, cached as text under `ExploreUrl<bookSourceUrl>` until the page calls `refreshExplore` or
  /// [refresh] is set. Drop-downs and inputs show the value last chosen (`cache.get(title)`) or their `default`.
  static Future<List<ExploreKind>> exploreKinds(BookSource s, {bool refresh = false}) async {
    final key = Baswebview.exploreKey(s.bookSourceUrl);
    var text = refresh ? '' : (await Storage.read(key)).trim();
    var kinds = SourceParse.explores(text);
    if (text.isEmpty || kinds.isEmpty) {
      try {
        text = await (await runOf(s)).getfinds();
      } catch (e) {
        throw Exception('${s.bookSourceName}运行find出错: $e');
      }
      kinds = SourceParse.explores(text);
      if (kinds.isNotEmpty) await Storage.write(key, text);
    }
    final cache = Cache(s.bookSourceUrl);
    for (final k in kinds) {
      if (k.type == ExploreKind.typeSelect || k.type == ExploreKind.typeText) {
        final v = await cache.get(k.title);
        if (v.isNotEmpty) k.defaultValue = v;
      }
    }
    return kinds;
  }

  /// An explore drop-down / input / button: the chosen value is stored first (`cache.set(title, value)`, template pp+0x530b0),
  /// then the entry's `action` runs in the page. Returns its value as text.
  static Future<String> exploreAction(BookSource s, String action, {String key = '', String? value}) async {
    if (value != null && key.isNotEmpty) await Cache(s.bookSourceUrl).set(key, value);
    if (action.trim().isEmpty) return '';
    return (await runOf(s)).runJs(action);
  }

  /// `info(bookurl)`: fills [book] (its `bookUrl` stays the key of the book).
  static Future<Book> bookInfo(BookSource s, Book book, {DebugLog? debug}) async {
    final r = await (await runOf(s)).info(book.bookUrl, log: _log(debug), text: _text(debug));
    if (r.name.isNotEmpty) book.name = r.name;
    if (r.author.isNotEmpty) book.author = r.author;
    if (r.kind.isNotEmpty) book.kind = r.kind;
    if (r.coverUrl.isNotEmpty) book.coverUrl = r.coverUrl;
    if (r.intro.isNotEmpty) book.intro = r.intro;
    if (r.wordCount.isNotEmpty) book.wordCount = r.wordCount;
    if (r.latestChapterTitle.isNotEmpty) book.latestChapterTitle = r.latestChapterTitle;
    if (r.downloadUrls.isNotEmpty) book.downloadUrls = r.downloadUrls;
    if (r.type_ != 0) book.type = r.type_;
    book.tocUrl = r.tocUrl.isNotEmpty ? r.tocUrl : (book.tocUrl.isNotEmpty ? book.tocUrl : book.bookUrl);
    book.origin = s.bookSourceUrl;
    book.originName = s.bookSourceName;
    return book;
  }

  /// `chapter(tocUrl, bookurl)`. A book whose toc url is not known yet (empty, or still the book url a search result carries) gets
  /// its `info()` first, as the detail page would: pages often hand the real toc url out of `info()` only.
  static Future<List<BookChapter>> chapters(BookSource s, Book book, {DebugLog? debug}) async {
    if (book.tocUrl.isEmpty || book.tocUrl == book.bookUrl) await bookInfo(s, book, debug: debug);
    final tocUrl = book.tocUrl.isNotEmpty ? book.tocUrl : book.bookUrl;
    final list = await (await runOf(s)).chapter(tocUrl, book.bookUrl, log: _log(debug), text: _text(debug));
    return [
      for (final c in list)
        BookChapter(
          url: c.chapterId,
          title: c.name,
          isVolume: c.isVolume,
          baseUrl: tocUrl,
          bookUrl: book.bookUrl,
          index: c.index,
          isVip: c.isVip,
          isPay: c.isPay,
          tag: c.tag.isEmpty ? null : c.tag,
          start: c.start,
          end: c.end,
          chapterId: c.chapterId,
        ),
    ];
  }

  static const Map<String, String> _entities = {'&nbsp;': ' ', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&#160;': ' ', '&amp;': '&'};

  /// The chapter text as the reader takes it: paragraphs on lines, only `<img>` tags kept (template: 正文文本不支持除了img 以外的标签).
  /// Audio books and short dramas (type 1 / 4) return a media url, which is passed through.
  static String formatContent(String text, int type) {
    final t = text.trim();
    if (type == 1 || type == 4 || !t.contains('<')) return t;
    var out = HtmlFormatter.formatKeepImg(t);
    _entities.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  /// `content(url, bookurl, index)` with the chapter's `chapterId` as url.
  static Future<String> content(BookSource s, Book book, BookChapter chapter, {DebugLog? debug}) async {
    final url = chapter.chapterId.isNotEmpty ? chapter.chapterId : chapter.url;
    final text = await (await runOf(s)).content(url, book.bookUrl, chapter.index, log: _log(debug), text: _text(debug));
    return formatContent(text, book.type);
  }

  /// `pay(bookurl, url)` with the chapter's `chapterId` (the reader reloads the toc and the chapter afterwards).
  static Future<String> payAction(BookSource s, Book book, BookChapter chapter) async =>
      (await runOf(s)).pay(book.bookUrl, chapter.chapterId.isNotEmpty ? chapter.chapterId : chapter.url);

  /// `imagedecrypt(url, base64)` for images whose options ask for it.
  static Future<Uint8List> decodeImage(BookSource s, String imageUrl, Uint8List bytes) async => (await runOf(s)).imagedecrypt(imageUrl, bytes);

  /// `getloginurl()`: an http url (opened in the browser) or the JSON of the login form.
  static Future<String> loginUrl(BaseSource s) async => (await SourceRun.of(s)).getloginurl();

  /// `login()` after the login form was saved.
  static Future<String> login(BaseSource s) async => (await SourceRun.of(s)).login();

  /// `gethelp()`: an http url, plain text, or `@html:` html.
  static Future<String> help(BaseSource s) async => (await SourceRun.of(s)).gethelp();

  /// Drops the running page and the cached discovery entries (重载书源线程, source edited).
  static Future<void> reload(String sourceUrl) async {
    await SourceRun.remove(sourceUrl);
    await Storage.delete(Baswebview.exploreKey(sourceUrl));
  }

  /// The source debugger chain (same keys as `SourceApi.debug`): a keyword searches, an http url starts at the detail page,
  /// `title::url` at a discovery page, `++url` at a toc url, `--url` fetches one chapter.
  static Future<DebugLog> debug(BookSource s, String key, {void Function(String line)? onLine, void Function(String step, String body)? onBody}) async {
    final log = DebugLog(onLine: onLine, onBody: onBody);
    try {
      if (key.startsWith('--')) {
        final url = key.substring(2);
        final b = Book(bookUrl: url, origin: s.bookSourceUrl);
        final text = await content(s, b, BookChapter(url: url, title: '调试', bookUrl: url, chapterId: url), debug: log);
        log.body('content', text);
        log.log('︽正文页解析完成 ${text.length}');
        return log;
      }
      Book book;
      if (key.startsWith('++')) {
        book = Book(bookUrl: key.substring(2), origin: s.bookSourceUrl)..tocUrl = key.substring(2);
      } else if (RegExp(r'^https?://', caseSensitive: false).hasMatch(key)) {
        book = await bookInfo(s, Book(bookUrl: key, origin: s.bookSourceUrl, originName: s.bookSourceName), debug: log);
        log.log('︽详情页解析完成');
      } else {
        final List<SearchBook> list;
        if (key.contains('::')) {
          list = await explore(s, key.substring(key.indexOf('::') + 2), debug: log);
          log.log('︽发现页解析完成 ${list.length}');
        } else {
          list = await search(s, key, debug: log);
          log.log('︽搜索页解析完成 ${list.length}');
        }
        if (list.isEmpty) {
          log.log('≡未获取到书籍');
          return log;
        }
        log.body('search', const JsonEncoder.withIndent('  ').convert([for (final b in list) b.toBook().toModel().toJson()]));
        book = await bookInfo(s, list.first.toBook(), debug: log);
        log.log('︽详情页解析完成');
      }
      final chapters = await TimeSourceApi.chapters(s, book, debug: log);
      log.log('︽目录页解析完成 ${chapters.length}');
      if (chapters.isEmpty) return log;
      final first = chapters.firstWhere((c) => !c.isVolume, orElse: () => chapters.first);
      final text = await content(s, book, first, debug: log);
      log.body('content', text);
      log.log('︽正文页解析完成 ${text.length}');
    } catch (e) {
      log.log('error: $e');
    }
    return log;
  }
}
