// qread/api/rssapi.dart — RSS calls of the bound 轻阅读 backend (`RssApi` in the original).
//
// Original: /getRsssortUrls 0x10c89f0 (`id`; reply list of {sortName, sortUrl} -> `ArticleTab`), /getArticles 0xfae340 (`id`,
// `page`, `sortUrl`, `sortName`; reply {articles, next} -> `ArticleJson`), /getRssContent 0xfbc530, /editRssSources 0xfaa854,
// /saveRssSources 0xe73c6c, /delRssSource(s), /startRssSources 0xf91ecc, /stopRssSources 0xf91d44, /stopRssSource 0xf94f18,
// /editrsssourcegroup 0xf900d0, /getRssSourcejson, /getRssSources 0x10c7fb0, /setRssVariable 0xf69c44, /getRssVariable 0xf69a0c.
import 'dart:convert';

import '../../models/article.dart';
import '../../models/article_tab.dart';
import '../qread.dart';

/// One page of articles (`ArticleJson`): the articles and whether there is a next page.
class ArticleJson {
  final List<Article> articles;
  final bool next;
  const ArticleJson(this.articles, this.next);
}

abstract class RssApi {
  static Map<String, dynamic> _map(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.trim().startsWith('{')) return Map<String, dynamic>.from(jsonDecode(v) as Map);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _list(Object? v) {
    if (v is String && v.trim().startsWith('[')) v = jsonDecode(v);
    return [for (final e in (v is List ? v : const [])) if (e is Map) Map<String, dynamic>.from(e)];
  }

  static Future<List<ArticleTab>> sorts(String sourceUrl) async =>
      [for (final m in _list(await Qread.post('/getRsssortUrls', {'id': sourceUrl}))) ArticleTab(sortName: '${m['sortName'] ?? ''}', sortUrl: '${m['sortUrl'] ?? ''}')];

  static Future<ArticleJson> articles(String sourceUrl, String sortName, String sortUrl, int page) async {
    final m = _map(await Qread.post('/getArticles', {'id': sourceUrl, 'page': page, 'sortUrl': sortUrl, 'sortName': sortName}));
    return ArticleJson([for (final a in _list(m['articles'])) Article.fromJson(a)], m['next'] == true || '${m['next']}' == 'true');
  }

  static Future<String> content(String sourceUrl, Article article) async =>
      '${await Qread.post('/getRssContent', {'id': sourceUrl, 'link': article.link, 'article': article.toJson()}) ?? ''}';

  static Future<Map<String, dynamic>> sourceJson(String url) async => _map(await Qread.post('/getRssSourcejson', {'id': url}));

  static Future<void> save(String oldUrl, Map<String, dynamic> json) async => Qread.post('/editRssSources', {'id': oldUrl, 'json': jsonEncode(json)});

  static Future<void> saveAll(List<Map<String, dynamic>> sources) async => Qread.post('/saveRssSources', {'source': jsonEncode(sources)});

  static Future<void> delete(Iterable<String> urls) async => Qread.post('/delRssSources', {'id': urls.toList()});

  static Future<void> setEnabled(Iterable<String> urls, bool on) async => Qread.post(on ? '/startRssSources' : '/stopRssSources', {'id': urls.toList()});

  static Future<void> editGroup(Iterable<String> urls, String group, {int st = 1}) async =>
      Qread.post('/editrsssourcegroup', {'id': urls.toList()}, '&st=$st&group=${Uri.encodeQueryComponent(group)}');

  static Future<void> setVariable(String url, String variable) async => Qread.post('/setRssVariable', {'id': url, 'variable': variable});

  static Future<String> getVariable(String url) async => '${await Qread.post('/getRssVariable', {'id': url}) ?? ''}';
}
