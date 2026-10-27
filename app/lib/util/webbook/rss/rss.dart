// util/webbook/rss/rss.dart - RSS flows (Legado `Rss`): fetch a sort page and parse it into articles, fetch one article's content.
import 'package:html/dom.dart' as dom;

import '../../html/jsoup.dart';
import '../analyze_rule/analyze_rule.dart';
import '../analyze_rule/analyze_url.dart';
import '../analyze_rule/rule_data.dart';
import '../debug.dart';
import '../model/rss_article.dart';
import '../model/rss_source.dart';
import 'rss_parser_by_rule.dart';

class Rss {
  final RssSource source;
  final DebugLog? debug;

  Rss(this.source, {this.debug});

  Future<(List<RssArticle>, String?)> getArticles(String sortName, String sortUrl, {int page = 1}) async {
    final ruleData = RuleData();
    final au = await AnalyzeUrl.create(sortUrl,
        page: page, baseUrl: source.sourceUrl, source: source, ruleData: ruleData, headerMapF: await source.getHeaderMap(true));
    debug?.log('≡请求:${au.requestUrl}');
    final res = await au.getStrResponse();
    return RssParserByRule.parseXML(sortName, sortUrl, res.body, source, ruleData, debug: debug);
  }

  /// The article body (HTML). Without `ruleContent` the article link itself is returned so that the UI can open it as a web page.
  Future<String> getContent(RssArticle article) async {
    final rule = source.ruleContent;
    if (rule == null || rule.trim().isEmpty) {
      return article.description ?? article.link;
    }
    final au = await AnalyzeUrl.create(article.link,
        baseUrl: source.sourceUrl, source: source, ruleData: article, headerMapF: await source.getHeaderMap(true));
    final res = await au.getStrResponse();
    final analyzeRule = AnalyzeRule(article, source);
    analyzeRule.setContent(res.body ?? '').setBaseUrl(res.url);
    analyzeRule.setRedirectUrl(res.url);
    var content = await analyzeRule.getString(rule);
    content = _applyFilters(content);
    article.content = content;
    return content;
  }

  /// `contentWhitelist` / `contentBlacklist`: regexes applied to the content (whitelist keeps only matches, blacklist removes them).
  String _applyFilters(String content) {
    var c = content;
    final white = source.contentWhitelist;
    if (white != null && white.trim().isNotEmpty) {
      try {
        c = RegExp(white).allMatches(c).map((m) => m.group(0)).join('');
      } on FormatException {
        // keep content
      }
    }
    final black = source.contentBlacklist;
    if (black != null && black.trim().isNotEmpty) {
      try {
        c = c.replaceAll(RegExp(black), '');
      } on FormatException {
        // keep content
      }
    }
    return c;
  }

  /// Plain text of an HTML snippet (for list previews).
  static String htmlToText(String html) {
    final doc = parseHtml(html);
    return jText(doc.body ?? doc as dom.Node);
  }
}
