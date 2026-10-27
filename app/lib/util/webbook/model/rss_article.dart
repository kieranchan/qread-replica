// util/webbook/model/rss_article.dart - one entry of an RSS list (Legado `RssArticle`). It is also the rule data object of the article
// rules, so `@put`/`@get` variables live on it. `models/article.dart` (`Article`) is the persisted/UI copy ([toModel]).
import 'dart:convert';

import '../../../models/article.dart' as m;
import '../../json.dart';
import '../analyze_rule/rule_data.dart';

class RssArticle implements RuleDataInterface {
  String origin;
  String sort;
  String title;
  int order;
  String link;
  String? pubDate;
  String? description;
  String? content;
  String? image;
  String group;
  bool read;
  String? variable;
  Map<String, String>? _vm;

  RssArticle({
    this.origin = '',
    this.sort = '',
    this.title = '',
    this.order = 0,
    this.link = '',
    this.pubDate,
    this.description,
    this.content,
    this.image,
    this.group = '默认分组',
    this.read = false,
    this.variable,
  });

  @override
  Map<String, String> get variableMap {
    final cached = _vm;
    if (cached != null) return cached;
    final d = jsonutil.tryDecode(variable);
    final map = <String, String>{};
    if (d is Map) {
      d.forEach((k, v) => map['$k'] = '$v');
    }
    return _vm = map;
  }

  @override
  bool putVariable(String key, String? value) {
    if (value == null) {
      variableMap.remove(key);
    } else {
      if (value.length > RuleData.maxValueLength) return false;
      variableMap[key] = value;
    }
    variable = variableMap.isEmpty ? null : jsonEncode(variableMap);
    return true;
  }

  @override
  String? getVariable(String key) => variableMap[key];

  m.Article toModel() => m.Article(
        origin: origin,
        title: title,
        pubDate: pubDate ?? '',
        image: image ?? '',
        description: description ?? '',
        link: link,
      );

  @override
  bool operator ==(Object other) => other is RssArticle && other.origin == origin && other.link == link;

  @override
  int get hashCode => Object.hash(origin, link);

  @override
  String toString() => title;
}
