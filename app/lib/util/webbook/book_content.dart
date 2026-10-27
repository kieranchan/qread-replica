// util/webbook/book_content.dart - chapter text (Legado `BookContent.analyzeContent`): `content` rule, `nextContentUrl` paging (one
// url: followed until it repeats or reaches the next chapter; several urls: all fetched in order), `replaceRegex`, `title`.
import '../legado/html_formatter.dart';
import 'analyze_rule/analyze_rule.dart';
import 'analyze_rule/analyze_url.dart';
import 'debug.dart';
import 'model/book.dart';
import 'model/book_chapter.dart';
import 'model/book_source.dart';
import 'model/rule.dart';
import 'util/network_utils.dart';

abstract class BookContent {
  static Future<String> analyzeContent(
    BookSource bookSource,
    Book book,
    BookChapter bookChapter,
    String baseUrl,
    String redirectUrl,
    String? body,
    String? nextChapterUrl, {
    DebugLog? debug,
  }) async {
    if (body == null) throw WebBookException('error get web content: $baseUrl');
    debug?.log('≡获取成功:$baseUrl');
    final content = StringBuffer();
    final nextUrlList = <String>[redirectUrl];
    final contentRule = bookSource.getContentRule();
    final mNext = (nextChapterUrl == null || nextChapterUrl.isEmpty) ? null : nextChapterUrl;
    final analyzeRule = AnalyzeRule(book, bookSource)..setContent(body, baseUrl);
    analyzeRule.setRedirectUrl(baseUrl);
    analyzeRule.setChapter(bookChapter);
    analyzeRule.nextChapterUrl = mNext;
    var data = await _analyzePage(book, baseUrl, redirectUrl, body, contentRule, bookChapter, bookSource, mNext, debug, true);
    content.write(data.$1);
    if (data.$2.length == 1) {
      var nextUrl = data.$2[0];
      while (nextUrl.isNotEmpty && !nextUrlList.contains(nextUrl)) {
        if (mNext != null && NetworkUtils.getAbsoluteURL(baseUrl, nextUrl) == NetworkUtils.getAbsoluteURL(baseUrl, mNext)) break;
        nextUrlList.add(nextUrl);
        debug?.log('≡获取下一页正文:$nextUrl');
        final au = await AnalyzeUrl.create(nextUrl, source: bookSource, ruleData: book, chapter: bookChapter, headerMapF: await bookSource.getHeaderMap(true));
        final res = await au.getStrResponse();
        data = await _analyzePage(book, nextUrl, res.url, res.body ?? '', contentRule, bookChapter, bookSource, mNext, debug, false);
        nextUrl = data.$2.isEmpty ? '' : data.$2.first;
        content.write('\n');
        content.write(data.$1);
      }
    } else if (data.$2.length > 1) {
      for (final u in data.$2) {
        if (nextUrlList.contains(u)) continue;
        nextUrlList.add(u);
        debug?.log('≡获取下一页正文:$u');
        final au = await AnalyzeUrl.create(u, source: bookSource, ruleData: book, chapter: bookChapter, headerMapF: await bookSource.getHeaderMap(true));
        final res = await au.getStrResponse();
        final d = await _analyzePage(book, u, res.url, res.body ?? '', contentRule, bookChapter, bookSource, mNext, debug, false);
        content.write('\n');
        content.write(d.$1);
      }
    }
    var contentStr = content.toString();
    final replaceRegex = contentRule.replaceRegex;
    if (replaceRegex != null && replaceRegex.isNotEmpty) {
      debug?.log('┌执行正文替换规则');
      contentStr = await analyzeRule.getString(replaceRegex, mContent: contentStr);
      debug?.log('└替换完成');
    }
    return contentStr;
  }

  static Future<(String, List<String>)> _analyzePage(
    Book book,
    String baseUrl,
    String redirectUrl,
    String body,
    ContentRule contentRule,
    BookChapter chapter,
    BookSource bookSource,
    String? nextChapterUrl,
    DebugLog? debug,
    bool first,
  ) async {
    final analyzeRule = AnalyzeRule(book, bookSource);
    analyzeRule.setContent(body, baseUrl);
    analyzeRule.setRedirectUrl(redirectUrl);
    analyzeRule.setChapter(chapter);
    analyzeRule.nextChapterUrl = nextChapterUrl;
    final nextUrlList = <String>[];
    debug?.log('┌获取正文内容');
    var content = await analyzeRule.getString(contentRule.content);
    content = HtmlFormatter.formatKeepImg(content, redirectUrl: analyzeRule.redirectUrl ?? redirectUrl);
    debug?.log('└长度:${content.length}');
    final titleRule = contentRule.title;
    if (first && titleRule != null && titleRule.isNotEmpty) {
      final t = await analyzeRule.getString(titleRule);
      if (t.isNotEmpty) chapter.title = t;
    }
    final nextRule = contentRule.nextContentUrl;
    if (nextRule != null && nextRule.isNotEmpty) {
      debug?.log('┌获取正文下一页链接');
      final urls = await analyzeRule.getStringList(nextRule, isUrl: true);
      if (urls != null) nextUrlList.addAll(urls);
      debug?.log('└${nextUrlList.join(',')}');
    }
    return (content, nextUrlList);
  }
}
