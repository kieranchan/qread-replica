// util/webbook/book_info.dart - detail page parsing (Legado `BookInfo.analyzeBookInfo`): optional `init` rule narrows the content, then
// name/author/kind/wordCount/lastChapter/coverUrl/intro/tocUrl/downloadUrls rules fill the [Book].
import '../format.dart';
import '../legado/html_formatter.dart';
import 'analyze_rule/analyze_rule.dart';
import 'debug.dart';
import 'model/book.dart';
import 'model/book_source.dart';

abstract class BookInfo {
  static Future<void> analyzeBookInfo(
    Book book,
    String? body,
    BookSource bookSource,
    String baseUrl,
    String redirectUrl,
    bool canReName, {
    DebugLog? debug,
  }) async {
    if (body == null) throw WebBookException('error get web content: $baseUrl');
    final analyzeRule = AnalyzeRule(book, bookSource);
    analyzeRule.setContent(body).setBaseUrl(baseUrl);
    analyzeRule.setRedirectUrl(redirectUrl);
    await analyzeBookInfoWith(book, body, analyzeRule, bookSource, baseUrl, redirectUrl, canReName, debug: debug);
  }

  static Future<void> analyzeBookInfoWith(
    Book book,
    String body,
    AnalyzeRule analyzeRule,
    BookSource bookSource,
    String baseUrl,
    String redirectUrl,
    bool canReName, {
    DebugLog? debug,
  }) async {
    final infoRule = bookSource.getBookInfoRule();
    final init = infoRule.init;
    if (init != null && init.isNotEmpty) {
      debug?.log('≡执行详情页初始化规则');
      final e = await analyzeRule.getElement(init);
      if (e != null) analyzeRule.setContent(e);
    }
    final mCanReName = canReName && (infoRule.canReName ?? '').trim().isNotEmpty;

    debug?.log('┌获取书名');
    final name = await analyzeRule.getString(infoRule.name);
    if (name.isNotEmpty && (mCanReName || book.name.isEmpty)) book.name = Book.formatBookName(name);
    debug?.log('└${book.name}');

    debug?.log('┌获取作者');
    final author = await analyzeRule.getString(infoRule.author);
    if (author.isNotEmpty && (mCanReName || book.author.isEmpty)) book.author = Book.formatBookAuthor(author);
    debug?.log('└${book.author}');

    debug?.log('┌获取分类');
    final kind = (await analyzeRule.getStringList(infoRule.kind))?.join(',');
    if (kind != null && kind.isNotEmpty) book.kind = kind;
    debug?.log('└${book.kind ?? ''}');

    final wc = await analyzeRule.getString(infoRule.wordCount);
    if (wc.isNotEmpty) book.wordCount = Format.wordCountFormat(wc);

    debug?.log('┌获取最新章节');
    final last = await analyzeRule.getString(infoRule.lastChapter);
    if (last.isNotEmpty) book.latestChapterTitle = last;
    debug?.log('└${book.latestChapterTitle ?? ''}');

    debug?.log('┌获取封面链接');
    final cover = await analyzeRule.getString(infoRule.coverUrl, isUrl: true);
    if (cover.isNotEmpty) book.coverUrl = cover;
    debug?.log('└${book.coverUrl ?? ''}');

    debug?.log('┌获取简介');
    final intro = await analyzeRule.getString(infoRule.intro);
    if (intro.isNotEmpty) book.intro = HtmlFormatter.format(intro);
    debug?.log('└${book.intro ?? ''}');

    debug?.log('┌获取目录链接');
    final toc = await analyzeRule.getString(infoRule.tocUrl, isUrl: true);
    book.tocUrl = toc.isEmpty ? baseUrl : toc;
    if (book.tocUrl == baseUrl) book.tocHtml = body;
    debug?.log('└${book.tocUrl}');

    final dl = infoRule.downloadUrls;
    if (dl != null && dl.isNotEmpty) {
      final urls = await analyzeRule.getStringList(dl, isUrl: true);
      if (urls != null && urls.isNotEmpty) book.downloadUrls = urls.join(',');
    }
  }
}
