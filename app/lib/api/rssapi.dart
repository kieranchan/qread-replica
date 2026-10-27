// api/rssapi.dart - entry points for RSS/subscription sources (`RssRunapi` in the original): sort tabs, article lists with paging,
// article content.
import '../util/webbook/debug.dart';
import '../util/webbook/model/rss_article.dart';
import '../util/webbook/model/rss_source.dart';
import '../util/webbook/web_book.dart';

abstract class RssRunapi {
  /// The sort tabs (`name`, `url`) of [source]; a source without `sortUrl` has one entry with an empty name.
  static Future<List<(String, String)>> sorts(RssSource source) => source.sortUrls();

  /// One page of articles of a sort and the url of the next page (null at the end).
  static Future<(List<RssArticle>, String?)> articles(RssSource source, String sortName, String sortUrl, {int page = 1, DebugLog? debug}) =>
      WebBookRss(source, debug: debug).getArticles(sortName, sortUrl, page: page);

  /// The article body as HTML (or its description/link when the source has no `ruleContent`).
  static Future<String> content(RssSource source, RssArticle article, {DebugLog? debug}) => WebBookRss(source, debug: debug).getContent(article);
}
