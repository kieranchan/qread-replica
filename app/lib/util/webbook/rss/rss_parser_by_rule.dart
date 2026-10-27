// util/webbook/rss/rss_parser_by_rule.dart - RSS list parsing by rules (Legado `RssParserByRule`): `ruleArticles` (leading `-` reverses),
// `ruleNextPage` (`PAGE` = the same url again), `ruleTitle/rulePubDate/ruleDescription/ruleImage/ruleLink`.
import '../../legado/rss_parser_default.dart';
import '../analyze_rule/analyze_rule.dart';
import '../analyze_rule/rule_data.dart';
import '../debug.dart';
import '../model/rss_article.dart';
import '../model/rss_source.dart';
import '../util/network_utils.dart';

abstract class RssParserByRule {
  /// Returns the articles and the url of the next page (null when there is none).
  static Future<(List<RssArticle>, String?)> parseXML(
    String sortName,
    String sortUrl,
    String? body,
    RssSource rssSource,
    RuleData ruleData, {
    DebugLog? debug,
  }) async {
    final sourceUrl = rssSource.sourceUrl;
    if (body == null || body.trim().isEmpty) throw WebBookException('获取网页内容为空');
    debug?.log('≡获取成功:$sourceUrl');
    var ruleArticles = rssSource.ruleArticles;
    if (ruleArticles == null || ruleArticles.trim().isEmpty) {
      return (RssParserDefault.parseXML(body, sortName, sourceUrl), null);
    }
    final articleList = <RssArticle>[];
    final analyzeRule = AnalyzeRule(ruleData, rssSource);
    analyzeRule.setContent(body).setBaseUrl(sortUrl);
    analyzeRule.setRedirectUrl(sortUrl);
    var reverse = false;
    if (ruleArticles.startsWith('-')) {
      reverse = true;
      ruleArticles = ruleArticles.substring(1);
    }
    debug?.log('┌获取列表');
    final collections = await analyzeRule.getElements(ruleArticles);
    debug?.log('└列表大小:${collections.length}');
    String? nextUrl;
    final nextRule = rssSource.ruleNextPage;
    if (nextRule != null && nextRule.isNotEmpty) {
      debug?.log('┌获取下一页链接');
      nextUrl = nextRule.toUpperCase() == 'PAGE' ? sortUrl : await analyzeRule.getString(nextRule);
      if (nextUrl.isNotEmpty) nextUrl = NetworkUtils.getAbsoluteURL(sortUrl, nextUrl);
      debug?.log('└$nextUrl');
    }
    final ruleTitle = analyzeRule.splitSourceRule(rssSource.ruleTitle);
    final rulePubDate = analyzeRule.splitSourceRule(rssSource.rulePubDate);
    final ruleDescription = analyzeRule.splitSourceRule(rssSource.ruleDescription);
    final ruleImage = analyzeRule.splitSourceRule(rssSource.ruleImage);
    final ruleLink = analyzeRule.splitSourceRule(rssSource.ruleLink);
    var order = 0;
    for (final item in collections) {
      final a = RssArticle(origin: sourceUrl, sort: sortName);
      ruleData.variableMap.forEach((k, v) => a.putVariable(k, v));
      analyzeRule.setRuleData(a);
      analyzeRule.setContent(item);
      a.title = await analyzeRule.getString(ruleTitle);
      a.pubDate = await analyzeRule.getString(rulePubDate);
      a.description = await analyzeRule.getString(ruleDescription);
      a.image = await analyzeRule.getString(ruleImage, isUrl: true);
      a.link = NetworkUtils.getAbsoluteURL(sortUrl, await analyzeRule.getString(ruleLink));
      if (a.title.trim().isEmpty) continue;
      a.order = order++;
      articleList.add(a);
    }
    return (reverse ? articleList.reversed.toList() : articleList, nextUrl);
  }
}
