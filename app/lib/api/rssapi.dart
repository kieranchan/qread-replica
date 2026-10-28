// api/rssapi.dart - entry points for RSS/subscription sources (`RssRunapi` in the original): sort tabs, article lists with paging,
// article content.
import '../util/webbook/analyze_rule/js_extensions.dart';
import '../util/webbook/debug.dart';
import '../util/webbook/model/rss_article.dart';
import '../util/webbook/model/rss_source.dart';
import '../util/webbook/web_book.dart';

abstract class RssRunapi {
  /// A subscription-source file may hold one source or an array.
  static List<RssSource> parseSources(String json) => RssSource.listFromJsonString(json);

  /// The sort tabs (`name`, `url`) of [source]; a source without `sortUrl` has one entry with an empty name.
  static Future<List<(String, String)>> sorts(RssSource source) => source.sortUrls();

  /// One page of articles of a sort and the url of the next page (null at the end).
  static Future<(List<RssArticle>, String?)> articles(RssSource source, String sortName, String sortUrl, {int page = 1, DebugLog? debug}) =>
      WebBookRss(source, debug: debug).getArticles(sortName, sortUrl, page: page);

  /// The article body as HTML (or its description/link when the source has no `ruleContent`).
  /// Legado `shouldOverrideUrlLoading` of an RSS source: runs its JavaScript with `url`; true (any text but empty / null / false /
  /// no / not / 0) means the app handles the navigation and the web view must not load [url].
  static Future<bool> shouldOverrideUrlLoading(RssSource source, String url) async {
    final js = source.shouldOverrideUrlLoading;
    if (js == null || js.trim().isEmpty) return false;
    final r = await SourceJsExtensions(source).runJs(js, values: {'url': url, 'result': url});
    if (r == null) return false;
    if (r is bool) return r;
    final t = '$r'.trim();
    if (t.isEmpty || t == 'null' || t == 'undefined') return false;
    return !RegExp(r'^(false|no|not|0)$', caseSensitive: false).hasMatch(t);
  }

  static Future<String> content(RssSource source, RssArticle article, {DebugLog? debug}) => WebBookRss(source, debug: debug).getContent(article);
}
