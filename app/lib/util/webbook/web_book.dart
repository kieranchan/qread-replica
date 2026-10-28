// util/webbook/web_book.dart - the flows of one book source: search, explore, book info, table of contents, chapter content, plus the
// source hooks (`loginCheckJs`, `preUpdateJs`, `imageDecode`, `coverDecodeJs`, `payAction`, `callBackJs`). Mirrors Legado's `WebBook`
// object; the original's `WebBook` class wraps a `WBook` worker (see w_book.dart).
import 'dart:convert';
import 'dart:typed_data';

import 'analyze_rule/analyze_rule.dart';
import 'analyze_rule/analyze_url.dart';
import 'analyze_rule/rule_data.dart';
import 'book_chapter_list.dart';
import 'book_content.dart';
import 'book_info.dart';
import 'book_list.dart';
import 'debug.dart';
import 'model/book.dart';
import 'model/book_chapter.dart';
import 'model/book_source.dart';
import 'model/rss_article.dart';
import 'model/rss_source.dart';
import 'model/search_book.dart';
import 'rss/rss.dart';
import 'util/str_response.dart';

/// RSS counterpart of [WebBook] (the original's `WebBookRss` wraps a `Rss`).
class WebBookRss {
  final RssSource source;
  final Rss _rss;

  WebBookRss(this.source, {DebugLog? debug}) : _rss = Rss(source, debug: debug);

  Future<(List<RssArticle>, String?)> getArticles(String sortName, String sortUrl, {int page = 1}) => _rss.getArticles(sortName, sortUrl, page: page);

  Future<String> getContent(RssArticle article) => _rss.getContent(article);
}

class WebBook {
  final BookSource source;
  final DebugLog? debug;

  WebBook(this.source, {this.debug});

  /// Runs `loginCheckJs` over the response (the script receives `result` = response and returns it, possibly rewritten).
  Future<StrResponse> _checkLogin(AnalyzeUrl au, StrResponse res) async {
    final js = source.loginCheckJs;
    if (js == null || js.trim().isEmpty) return res;
    final r = await au.evalJS(js, res.toPlain());
    if (r is Map && r['body'] != null) {
      return StrResponse('${r['url'] ?? res.url}', '${r['body']}', code: (r['code'] as num?)?.toInt() ?? res.code, message: '${r['message'] ?? res.message}', headers: res.headers);
    }
    if (r is String && r.isNotEmpty) return StrResponse(res.url, r, code: res.code, message: res.message, headers: res.headers);
    return res;
  }

  // search / explore -----------------------------------------------------------------------------------------------------------
  Future<List<SearchBook>> searchBook(String key, {int page = 1}) async {
    final searchUrl = source.searchUrl;
    if (searchUrl == null || searchUrl.trim().isEmpty) throw WebBookException('搜索url不能为空');
    final ruleData = RuleData();
    debug?.log('︾开始解析搜索页');
    final au = await AnalyzeUrl.create(searchUrl,
        key: key, page: page, baseUrl: source.bookSourceUrl, source: source, ruleData: ruleData, headerMapF: await source.getHeaderMap(true));
    debug?.log('≡请求:${au.requestUrl}');
    var res = await au.getStrResponse();
    res = await _checkLogin(au, res);
    debug?.body('search', res.body);
    return BookList.analyzeBookList(source, ruleData, au, res.url, res.body, true, debug: debug);
  }

  /// [url] is one entry's url rule (`exploreKinds()` -> `ExploreKind.url`).
  Future<List<SearchBook>> exploreBook(String url, {int page = 1}) async {
    final ruleData = RuleData();
    debug?.log('︾开始解析发现页');
    final au = await AnalyzeUrl.create(url,
        page: page, baseUrl: source.bookSourceUrl, source: source, ruleData: ruleData, headerMapF: await source.getHeaderMap(true));
    debug?.log('≡请求:${au.requestUrl}');
    var res = await au.getStrResponse();
    res = await _checkLogin(au, res);
    debug?.body('explore', res.body);
    return BookList.analyzeBookList(source, ruleData, au, res.url, res.body, false, debug: debug);
  }

  // detail ---------------------------------------------------------------------------------------------------------------------
  /// Fills [book] from its detail page ([Book.infoHtml] is used when already fetched, e.g. by a search that landed on a detail page).
  Future<Book> getBookInfo(Book book, {bool canReName = true}) async {
    book.type = source.bookSourceType;
    final html = book.infoHtml;
    if (html != null && html.isNotEmpty) {
      await BookInfo.analyzeBookInfo(book, html, source, book.bookUrl, book.bookUrl, canReName, debug: debug);
    } else {
      debug?.log('︾开始解析详情页');
      final au = await AnalyzeUrl.create(book.bookUrl, source: source, ruleData: book, headerMapF: await source.getHeaderMap(true));
      var res = await au.getStrResponse();
      res = await _checkLogin(au, res);
      debug?.body('book', res.body);
      await BookInfo.analyzeBookInfo(book, res.body, source, book.bookUrl, res.url, canReName, debug: debug);
    }
    return book;
  }

  // toc ------------------------------------------------------------------------------------------------------------------------
  Future<void> runPreUpdateJs(Book book) async {
    final js = source.getTocRule().preUpdateJs;
    if (js != null && js.trim().isNotEmpty) {
      debug?.log('≡执行目录预更新JS');
      await AnalyzeRule(book, source).evalJS(js);
    }
  }

  /// Chapters in reading order. `Book.reverseCatalog` (the reader's own "reverse toc" switch) is *not* applied here.
  Future<List<BookChapter>> getChapterList(Book book, {bool runPreUpdate = false}) async {
    book.type = source.bookSourceType;
    if (runPreUpdate) await runPreUpdateJs(book);
    final tocUrl = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl;
    List<BookChapter> list;
    final tocHtml = book.tocHtml;
    if (book.bookUrl == tocUrl && tocHtml != null && tocHtml.isNotEmpty) {
      list = await BookChapterList.analyzeChapterList(source, book, tocUrl, tocUrl, tocHtml, debug: debug);
    } else {
      debug?.log('︾开始解析目录页');
      final au = await AnalyzeUrl.create(tocUrl, source: source, ruleData: book, headerMapF: await source.getHeaderMap(true));
      var res = await au.getStrResponse();
      res = await _checkLogin(au, res);
      debug?.body('toc', res.body);
      list = await BookChapterList.analyzeChapterList(source, book, tocUrl, res.url, res.body, debug: debug);
    }
    if (list.isEmpty) throw WebBookException('目录为空');
    book.totalChapterNum = list.length;
    final lastReal = list.lastWhere((c) => !c.isVolume, orElse: () => list.last);
    book.latestChapterTitle = lastReal.title;
    return list;
  }

  // content --------------------------------------------------------------------------------------------------------------------
  Future<String> getContent(Book book, BookChapter chapter, {String? nextChapterUrl}) async {
    final contentRule = source.getContentRule();
    if (contentRule.content == null || contentRule.content!.isEmpty) {
      debug?.log('⇒正文规则为空,使用章节链接:${chapter.url}');
      return chapter.url;
    }
    if (chapter.isVolume && chapter.url.startsWith(chapter.title)) {
      debug?.log('⇒一级目录正文不解析规则');
      return chapter.tag ?? '';
    }
    final abs = chapter.getAbsoluteURL();
    String text;
    if (chapter.url == book.bookUrl && (book.tocHtml ?? '').isNotEmpty) {
      text = await BookContent.analyzeContent(source, book, chapter, abs, abs, book.tocHtml, nextChapterUrl, debug: debug);
    } else {
      debug?.log('︾开始解析正文页');
      final au = await AnalyzeUrl.create(abs,
          baseUrl: book.tocUrl, source: source, ruleData: book, chapter: chapter, headerMapF: await source.getHeaderMap(true));
      var res = await au.getStrResponse(jsStr: contentRule.webJs, sourceRegex: contentRule.sourceRegex);
      res = await _checkLogin(au, res);
      debug?.body('content', res.body);
      text = await BookContent.analyzeContent(source, book, chapter, abs, res.url, res.body, nextChapterUrl, debug: debug);
    }
    if (text.trim().isEmpty) throw WebBookException('内容为空');
    return text;
  }

  // hooks ----------------------------------------------------------------------------------------------------------------------
  /// Runs a source script ([script] = `payAction`, `callBackJs`, ...) with `book` and `chapter` bound; returns its value.
  Future<Object?> runScript(String? script, Book book, {BookChapter? chapter, Map<String, Object?>? values}) async {
    if (script == null || script.trim().isEmpty) return null;
    var js = script.trim();
    final lower = js.toLowerCase();
    if (lower.startsWith('<js>')) {
      js = js.substring(4, js.lastIndexOf('<') > 4 ? js.lastIndexOf('<') : js.length);
    } else if (lower.startsWith('@js:')) {
      js = js.substring(4);
    }
    final a = AnalyzeRule(book, source)..setChapter(chapter);
    a.baseUrl = chapter?.getAbsoluteURL() ?? book.bookUrl;
    return a.runJs(js, values: values);
  }

  Future<Object?> payAction(Book book, BookChapter chapter) => runScript(source.getContentRule().payAction, book, chapter: chapter);

  Future<Object?> callBack(Book book, BookChapter chapter, {Map<String, Object?>? values}) =>
      runScript(source.getContentRule().callBackJs, book, chapter: chapter, values: values);

  /// Content rule `imageDecode`: [bytes] of the downloaded image -> decoded bytes (the script returns a byte list or base64 text).
  Future<Uint8List> decodeImage(Book book, BookChapter? chapter, String imageUrl, Uint8List bytes) async {
    final js = source.getContentRule().imageDecode;
    if (js == null || js.trim().isEmpty) return bytes;
    final r = await runScript(js, book, chapter: chapter, values: {'src': imageUrl, 'result': bytes.toList()});
    return _asBytes(r) ?? bytes;
  }

  /// `coverDecodeJs`: same contract as [decodeImage] for cover images.
  Future<Uint8List> decodeCover(Book? book, String coverUrl, Uint8List bytes) async {
    final js = source.coverDecodeJs;
    if (js == null || js.trim().isEmpty) return bytes;
    final r = await runScript(js, book ?? Book(origin: source.bookSourceUrl), values: {'src': coverUrl, 'result': bytes.toList()});
    return _asBytes(r) ?? bytes;
  }

  static Uint8List? _asBytes(Object? r) {
    if (r is List) return Uint8List.fromList(r.map((e) => (e as num).toInt() & 0xff).toList());
    if (r is String && r.isNotEmpty) {
      try {
        return base64.decode(r.replaceAll(RegExp(r'\s'), ''));
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}
