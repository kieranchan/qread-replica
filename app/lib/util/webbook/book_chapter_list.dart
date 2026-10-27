// util/webbook/book_chapter_list.dart - table-of-contents parsing (Legado `BookChapterList.analyzeChapterList`): the list rule (`-` prefix
// reverses), per-item name/url/updateTime/isVolume/isVip/isPay rules, `formatJs` post-processing, `nextTocUrl` paging.
import '../format.dart';
import 'analyze_rule/analyze_rule.dart';
import 'analyze_rule/analyze_url.dart';
import 'debug.dart';
import 'model/book.dart';
import 'model/book_chapter.dart';
import 'model/book_source.dart';
import 'model/rule.dart';

abstract class BookChapterList {
  static Future<List<BookChapter>> analyzeChapterList(
    BookSource bookSource,
    Book book,
    String baseUrl,
    String redirectUrl,
    String? body, {
    DebugLog? debug,
  }) async {
    if (body == null) throw WebBookException('error get web content: $baseUrl');
    final chapterList = <BookChapter>[];
    debug?.log('≡获取成功:$baseUrl');
    final tocRule = bookSource.getTocRule();
    final nextUrlList = <String>[redirectUrl];
    var reverse = false;
    var listRule = tocRule.chapterList ?? '';
    if (listRule.startsWith('-')) {
      reverse = true;
      listRule = listRule.substring(1);
    }
    if (listRule.startsWith('+')) listRule = listRule.substring(1);

    var chapterData = await _analyzePage(book, baseUrl, redirectUrl, body, tocRule, listRule, bookSource, debug);
    chapterList.addAll(chapterData.$1);
    final nexts = chapterData.$2;
    if (nexts.length == 1) {
      var nextUrl = nexts[0];
      while (nextUrl.isNotEmpty && !nextUrlList.contains(nextUrl)) {
        nextUrlList.add(nextUrl);
        debug?.log('≡获取目录下一页:$nextUrl');
        final au = await AnalyzeUrl.create(nextUrl, source: bookSource, ruleData: book, headerMapF: await bookSource.getHeaderMap(true));
        final res = await au.getStrResponse();
        chapterData = await _analyzePage(book, nextUrl, nextUrl, res.body, tocRule, listRule, bookSource, null);
        nextUrl = chapterData.$2.isEmpty ? '' : chapterData.$2.first;
        chapterList.addAll(chapterData.$1);
      }
    } else if (nexts.length > 1) {
      nextUrlList.addAll(nexts);
      for (final u in nexts) {
        debug?.log('≡获取目录下一页:$u');
        final au = await AnalyzeUrl.create(u, source: bookSource, ruleData: book, headerMapF: await bookSource.getHeaderMap(true));
        final res = await au.getStrResponse();
        final d = await _analyzePage(book, u, u, res.body, tocRule, listRule, bookSource, null);
        chapterList.addAll(d.$1);
      }
    }
    // de-duplicate by url, keeping the first occurrence
    var list = <BookChapter>{...chapterList}.toList();
    if (reverse) list = list.reversed.toList();
    for (var i = 0; i < list.length; i++) {
      list[i].index = i;
    }
    debug?.log('◇目录总数:${list.length}');
    return list;
  }

  static Future<(List<BookChapter>, List<String>)> _analyzePage(
    Book book,
    String baseUrl,
    String redirectUrl,
    String? body,
    TocRule tocRule,
    String listRule,
    BookSource bookSource,
    DebugLog? debug,
  ) async {
    final analyzeRule = AnalyzeRule(book, bookSource);
    analyzeRule.setContent(body ?? '').setBaseUrl(baseUrl);
    analyzeRule.setRedirectUrl(redirectUrl);
    final chapterList = <BookChapter>[];
    debug?.log('┌获取目录列表');
    final elements = await analyzeRule.getElements(listRule);
    debug?.log('└列表大小:${elements.length}');
    final nextTocUrlList = <String>[];
    final nextRule = tocRule.nextTocUrl;
    if (nextRule != null && nextRule.isNotEmpty) {
      debug?.log('┌获取目录下一页网址');
      final urls = await analyzeRule.getStringList(nextRule, isUrl: true);
      if (urls != null) {
        for (final u in urls) {
          if (u != redirectUrl) nextTocUrlList.add(u);
        }
      }
      debug?.log('└${nextTocUrlList.join(',')}');
    }
    if (elements.isNotEmpty) {
      final nameRule = analyzeRule.splitSourceRule(tocRule.chapterName);
      final urlRule = analyzeRule.splitSourceRule(tocRule.chapterUrl);
      final vipRule = analyzeRule.splitSourceRule(tocRule.isVip);
      final payRule = analyzeRule.splitSourceRule(tocRule.isPay);
      final upTimeRule = analyzeRule.splitSourceRule(tocRule.updateTime);
      final isVolumeRule = analyzeRule.splitSourceRule(tocRule.isVolume);
      for (var index = 0; index < elements.length; index++) {
        analyzeRule.setContent(elements[index]);
        final ch = BookChapter(bookUrl: book.bookUrl, baseUrl: redirectUrl);
        analyzeRule.setChapter(ch);
        ch.title = await analyzeRule.getString(nameRule);
        ch.url = await analyzeRule.getString(urlRule);
        final tag = await analyzeRule.getString(upTimeRule);
        ch.tag = tag.isEmpty ? null : tag;
        final isVolume = await analyzeRule.getString(isVolumeRule);
        ch.isVolume = Format.isTrue(isVolume);
        if (ch.url.isEmpty) {
          ch.url = ch.isVolume ? '${ch.title}$index' : baseUrl;
        }
        if (ch.title.isNotEmpty) {
          final isVip = await analyzeRule.getString(vipRule);
          final isPay = await analyzeRule.getString(payRule);
          if (Format.isTrue(isVip)) ch.isVip = true;
          if (Format.isTrue(isPay)) ch.isPay = true;
          chapterList.add(ch);
        }
        if (index == 0 && debug != null) {
          debug.log('◇首章:${ch.title} ${ch.url}');
        }
      }
    }
    final formatJs = tocRule.formatJs;
    if (formatJs != null && formatJs.trim().isNotEmpty) {
      analyzeRule.setRuleData(book);
      var index = 1;
      for (final ch in chapterList) {
        analyzeRule.setChapter(ch);
        try {
          final r = await analyzeRule.runJs(formatJs, values: {'gInt': 0, 'index': index, 'title': ch.title, 'result': ch.title});
          if (r != null) ch.title = r.toString();
        } catch (e) {
          debug?.log('格式化标题出错 ${e.toString()}');
        }
        index++;
      }
    }
    return (chapterList, nextTocUrlList);
  }
}
