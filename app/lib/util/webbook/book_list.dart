// util/webbook/book_list.dart - search / explore result parsing (Legado `BookList.analyzeBookList`). The list rule may start with `-`
// (reverse), `+` (ignored) or `:` (all-in-one regex); when the response is itself a detail page (`bookUrlPattern` matches, or the list
// is empty) it is parsed as a single book.
import '../format.dart';
import '../legado/html_formatter.dart';
import 'analyze_rule/analyze_rule.dart';
import 'analyze_rule/analyze_url.dart';
import 'analyze_rule/rule_data.dart';
import 'book_info.dart';
import 'debug.dart';
import 'model/book.dart';
import 'model/book_source.dart';
import 'model/rule.dart';
import 'model/search_book.dart';

abstract class BookList {
  static Future<List<SearchBook>> analyzeBookList(
    BookSource bookSource,
    RuleData ruleData,
    AnalyzeUrl analyzeUrl,
    String baseUrl,
    String? body,
    bool isSearch, {
    DebugLog? debug,
  }) async {
    final bookList = <SearchBook>[];
    if (body == null) throw WebBookException('error getting web content: ${analyzeUrl.ruleUrl}');
    debug?.log('≡获取成功:${analyzeUrl.ruleUrl}');
    final analyzeRule = AnalyzeRule(ruleData, bookSource);
    analyzeRule.setContent(body).setBaseUrl(baseUrl);
    analyzeRule.setRedirectUrl(baseUrl);

    final pattern = bookSource.bookUrlPattern;
    if (pattern != null && pattern.isNotEmpty) {
      bool isDetail;
      try {
        isDetail = RegExp('^(?:$pattern)\$').hasMatch(baseUrl);
      } on FormatException {
        isDetail = false;
      }
      if (isDetail) {
        debug?.log('≡链接为详情页');
        final sb = await _getInfoItem(bookSource, analyzeRule, analyzeUrl, body, baseUrl, ruleData, debug);
        if (sb != null) {
          sb.infoHtml = body;
          bookList.add(sb);
        }
        return bookList;
      }
    }

    var reverse = false;
    final BookListRule bookListRule = isSearch ? bookSource.getSearchRule() : bookSource.getExploreRule();
    var ruleList = bookListRule.bookList ?? '';
    if (ruleList.startsWith('-')) {
      reverse = true;
      ruleList = ruleList.substring(1);
    }
    if (ruleList.startsWith('+')) ruleList = ruleList.substring(1);
    debug?.log('┌获取书籍列表');
    final collections = await analyzeRule.getElements(ruleList);
    if (collections.isEmpty && (pattern == null || pattern.isEmpty)) {
      debug?.log('└列表为空,按详情页解析');
      final sb = await _getInfoItem(bookSource, analyzeRule, analyzeUrl, body, baseUrl, ruleData, debug);
      if (sb != null) {
        sb.infoHtml = body;
        bookList.add(sb);
      }
      return bookList;
    }
    debug?.log('└列表大小:${collections.length}');
    final ruleName = analyzeRule.splitSourceRule(bookListRule.name);
    final ruleBookUrl = analyzeRule.splitSourceRule(bookListRule.bookUrl);
    final ruleAuthor = analyzeRule.splitSourceRule(bookListRule.author);
    final ruleCoverUrl = analyzeRule.splitSourceRule(bookListRule.coverUrl);
    final ruleIntro = analyzeRule.splitSourceRule(bookListRule.intro);
    final ruleKind = analyzeRule.splitSourceRule(bookListRule.kind);
    final ruleLastChapter = analyzeRule.splitSourceRule(bookListRule.lastChapter);
    final ruleWordCount = analyzeRule.splitSourceRule(bookListRule.wordCount);
    for (var index = 0; index < collections.length; index++) {
      final sb = await _getSearchItem(bookSource, analyzeRule, collections[index], baseUrl, ruleData.variableMap, index == 0 ? debug : null, ruleName,
          ruleBookUrl, ruleAuthor, ruleKind, ruleCoverUrl, ruleWordCount, ruleIntro, ruleLastChapter);
      if (sb != null) {
        if (baseUrl == sb.bookUrl) sb.infoHtml = body;
        bookList.add(sb);
      }
    }
    final unique = <SearchBook>{...bookList}.toList();
    return reverse ? unique.reversed.toList() : unique;
  }

  static Future<SearchBook?> _getInfoItem(
    BookSource bookSource,
    AnalyzeRule analyzeRule,
    AnalyzeUrl analyzeUrl,
    String body,
    String baseUrl,
    RuleData ruleData,
    DebugLog? debug,
  ) async {
    final book = Book(bookUrl: analyzeUrl.ruleUrl, origin: bookSource.bookSourceUrl, originName: bookSource.bookSourceName, type: bookSource.bookSourceType);
    book.originOrder = bookSource.customOrder;
    ruleData.variableMap.forEach((k, v) => book.putVariable(k, v));
    analyzeRule.setRuleData(book);
    await BookInfo.analyzeBookInfo(book, body, bookSource, baseUrl, baseUrl, false, debug: debug);
    if (book.name.trim().isNotEmpty) return _toSearchBook(book);
    return null;
  }

  static SearchBook _toSearchBook(Book b) {
    final s = SearchBook(bookUrl: b.bookUrl, origin: b.origin, originName: b.originName, type: b.type, name: b.name, author: b.author, variable: b.variable);
    s.kind = b.kind;
    s.coverUrl = b.coverUrl;
    s.intro = b.intro;
    s.wordCount = b.wordCount;
    s.latestChapterTitle = b.latestChapterTitle;
    s.tocUrl = b.tocUrl;
    s.originOrder = b.originOrder;
    s.tocHtml = b.tocHtml;
    return s;
  }

  static Future<SearchBook?> _getSearchItem(
    BookSource bookSource,
    AnalyzeRule analyzeRule,
    Object item,
    String baseUrl,
    Map<String, String> variable,
    DebugLog? debug,
    List<SourceRule> ruleName,
    List<SourceRule> ruleBookUrl,
    List<SourceRule> ruleAuthor,
    List<SourceRule> ruleKind,
    List<SourceRule> ruleCoverUrl,
    List<SourceRule> ruleWordCount,
    List<SourceRule> ruleIntro,
    List<SourceRule> ruleLastChapter,
  ) async {
    final sb = SearchBook(origin: bookSource.bookSourceUrl, originName: bookSource.bookSourceName, type: bookSource.bookSourceType);
    sb.originOrder = bookSource.customOrder;
    variable.forEach((k, v) => sb.putVariable(k, v));
    analyzeRule.setRuleData(sb);
    analyzeRule.setContent(item);
    debug?.log('┌获取书名');
    sb.name = Book.formatBookName(await analyzeRule.getString(ruleName));
    debug?.log('└${sb.name}');
    if (sb.name.isEmpty) return null;
    debug?.log('┌获取作者');
    sb.author = Book.formatBookAuthor(await analyzeRule.getString(ruleAuthor));
    debug?.log('└${sb.author}');
    debug?.log('┌获取分类');
    sb.kind = (await analyzeRule.getStringList(ruleKind))?.join(',');
    debug?.log('└${sb.kind ?? ''}');
    debug?.log('┌获取字数');
    sb.wordCount = Format.wordCountFormat(await analyzeRule.getString(ruleWordCount));
    debug?.log('└${sb.wordCount}');
    debug?.log('┌获取最新章节');
    sb.latestChapterTitle = await analyzeRule.getString(ruleLastChapter);
    debug?.log('└${sb.latestChapterTitle}');
    debug?.log('┌获取简介');
    final intro = await analyzeRule.getString(ruleIntro);
    sb.intro = intro.contains('<') ? HtmlFormatter.format(intro) : intro;
    debug?.log('└${sb.intro}');
    debug?.log('┌获取封面链接');
    sb.coverUrl = await analyzeRule.getString(ruleCoverUrl, isUrl: true);
    debug?.log('└${sb.coverUrl}');
    debug?.log('┌获取详情页链接');
    sb.bookUrl = await analyzeRule.getString(ruleBookUrl, isUrl: true);
    if (sb.bookUrl.isEmpty) sb.bookUrl = baseUrl;
    debug?.log('└${sb.bookUrl}');
    return sb;
  }
}
