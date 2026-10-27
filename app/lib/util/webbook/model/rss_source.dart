// util/webbook/model/rss_source.dart - Legado `RssSource` (an RSS/subscription source: feed list rules + article content rule).
// `models/rsssource.dart` (`RssSource`, 10 slots) is the persisted copy that keeps the raw JSON in `json`.
import 'dart:convert';

import '../../json.dart';
import '../util/cache_manager.dart';
import 'base_source.dart';

class RssSource extends BaseSource {
  String sourceUrl;
  @override
  String sourceName;
  String sourceIcon;
  String? sourceGroup;
  @override
  String get sourceComment => _sourceComment ?? '';
  String? _sourceComment;
  bool enabled;
  @override
  String? variableComment;
  @override
  String? jsLib;
  @override
  bool enabledCookieJar;
  @override
  String? concurrentRate;
  @override
  String? header;
  @override
  String? loginUrl;
  @override
  String? loginUi;
  @override
  String? loginCheckJs;
  String? coverDecodeJs;
  String? sortUrl;
  bool singleUrl;
  int articleStyle;
  String? ruleArticles;
  String? ruleNextPage;
  String? ruleTitle;
  String? rulePubDate;
  String? ruleDescription;
  String? ruleImage;
  String? ruleLink;
  String? ruleContent;
  String? contentWhitelist;
  String? contentBlacklist;
  String? shouldOverrideUrlLoading;
  String? style;
  bool enableJs;
  bool loadWithBaseUrl;
  String? injectJs;
  int lastUpdateTime;
  int customOrder;

  Map<String, dynamic> extra;

  RssSource({
    this.sourceUrl = '',
    this.sourceName = '',
    this.sourceIcon = '',
    this.sourceGroup,
    String? sourceComment,
    this.enabled = true,
    this.variableComment,
    this.jsLib,
    this.enabledCookieJar = true,
    this.concurrentRate,
    this.header,
    this.loginUrl,
    this.loginUi,
    this.loginCheckJs,
    this.coverDecodeJs,
    this.sortUrl,
    this.singleUrl = false,
    this.articleStyle = 0,
    this.ruleArticles,
    this.ruleNextPage,
    this.ruleTitle,
    this.rulePubDate,
    this.ruleDescription,
    this.ruleImage,
    this.ruleLink,
    this.ruleContent,
    this.contentWhitelist,
    this.contentBlacklist,
    this.shouldOverrideUrlLoading,
    this.style,
    this.enableJs = true,
    this.loadWithBaseUrl = true,
    this.injectJs,
    this.lastUpdateTime = 0,
    this.customOrder = 0,
    Map<String, dynamic>? extra,
  })  : _sourceComment = sourceComment, // ignore: prefer_initializing_formals
        extra = extra ?? {};

  static const Set<String> _known = {
    'sourceUrl', 'sourceName', 'sourceIcon', 'sourceGroup', 'sourceComment', 'enabled', 'variableComment', 'jsLib', 'enabledCookieJar',
    'concurrentRate', 'header', 'loginUrl', 'loginUi', 'loginCheckJs', 'coverDecodeJs', 'sortUrl', 'singleUrl', 'articleStyle',
    'ruleArticles', 'ruleNextPage', 'ruleTitle', 'rulePubDate', 'ruleDescription', 'ruleImage', 'ruleLink', 'ruleContent',
    'contentWhitelist', 'contentBlacklist', 'shouldOverrideUrlLoading', 'style', 'enableJs', 'loadWithBaseUrl', 'injectJs',
    'lastUpdateTime', 'customOrder',
  };

  factory RssSource.fromJson(Map<String, dynamic> j) => RssSource(
        sourceUrl: jsonutil.asString(j['sourceUrl']),
        sourceName: jsonutil.asString(j['sourceName']),
        sourceIcon: jsonutil.asString(j['sourceIcon']),
        sourceGroup: jsonutil.optString(j['sourceGroup']),
        sourceComment: jsonutil.optString(j['sourceComment']),
        enabled: jsonutil.asBool(j['enabled'], true),
        variableComment: jsonutil.optString(j['variableComment']),
        jsLib: jsonutil.optString(j['jsLib']),
        enabledCookieJar: jsonutil.asBool(j['enabledCookieJar'], true),
        concurrentRate: jsonutil.optString(j['concurrentRate']),
        header: jsonutil.optString(j['header']),
        loginUrl: jsonutil.optString(j['loginUrl']),
        loginUi: jsonutil.optString(j['loginUi']),
        loginCheckJs: jsonutil.optString(j['loginCheckJs']),
        coverDecodeJs: jsonutil.optString(j['coverDecodeJs']),
        sortUrl: jsonutil.optString(j['sortUrl']),
        singleUrl: jsonutil.asBool(j['singleUrl']),
        articleStyle: jsonutil.asInt(j['articleStyle']),
        ruleArticles: jsonutil.optString(j['ruleArticles']),
        ruleNextPage: jsonutil.optString(j['ruleNextPage']),
        ruleTitle: jsonutil.optString(j['ruleTitle']),
        rulePubDate: jsonutil.optString(j['rulePubDate']),
        ruleDescription: jsonutil.optString(j['ruleDescription']),
        ruleImage: jsonutil.optString(j['ruleImage']),
        ruleLink: jsonutil.optString(j['ruleLink']),
        ruleContent: jsonutil.optString(j['ruleContent']),
        contentWhitelist: jsonutil.optString(j['contentWhitelist']),
        contentBlacklist: jsonutil.optString(j['contentBlacklist']),
        shouldOverrideUrlLoading: jsonutil.optString(j['shouldOverrideUrlLoading']),
        style: jsonutil.optString(j['style']),
        enableJs: jsonutil.asBool(j['enableJs'], true),
        loadWithBaseUrl: jsonutil.asBool(j['loadWithBaseUrl'], true),
        injectJs: jsonutil.optString(j['injectJs']),
        lastUpdateTime: jsonutil.asInt(j['lastUpdateTime']),
        customOrder: jsonutil.asInt(j['customOrder']),
        extra: {for (final e in j.entries) if (!_known.contains(e.key)) e.key: e.value},
      );

  factory RssSource.fromJsonString(String s) {
    final d = jsonDecode(s);
    if (d is List && d.isNotEmpty) return RssSource.fromJson(Map<String, dynamic>.from(d.first as Map));
    return RssSource.fromJson(Map<String, dynamic>.from(d as Map));
  }

  static List<RssSource> listFromJsonString(String s) {
    final d = jsonDecode(s);
    if (d is List) return [for (final e in d) if (e is Map) RssSource.fromJson(Map<String, dynamic>.from(e))];
    if (d is Map) return [RssSource.fromJson(Map<String, dynamic>.from(d))];
    return [];
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        'sourceUrl': sourceUrl,
        'sourceName': sourceName,
        'sourceIcon': sourceIcon,
        'sourceGroup': sourceGroup,
        'sourceComment': _sourceComment,
        'enabled': enabled,
        'variableComment': variableComment,
        'jsLib': jsLib,
        'enabledCookieJar': enabledCookieJar,
        'concurrentRate': concurrentRate,
        'header': header,
        'loginUrl': loginUrl,
        'loginUi': loginUi,
        'loginCheckJs': loginCheckJs,
        'coverDecodeJs': coverDecodeJs,
        'sortUrl': sortUrl,
        'singleUrl': singleUrl,
        'articleStyle': articleStyle,
        'ruleArticles': ruleArticles,
        'ruleNextPage': ruleNextPage,
        'ruleTitle': ruleTitle,
        'rulePubDate': rulePubDate,
        'ruleDescription': ruleDescription,
        'ruleImage': ruleImage,
        'ruleLink': ruleLink,
        'ruleContent': ruleContent,
        'contentWhitelist': contentWhitelist,
        'contentBlacklist': contentBlacklist,
        'shouldOverrideUrlLoading': shouldOverrideUrlLoading,
        'style': style,
        'enableJs': enableJs,
        'loadWithBaseUrl': loadWithBaseUrl,
        'injectJs': injectJs,
        'lastUpdateTime': lastUpdateTime,
        'customOrder': customOrder,
      };

  @override
  String getKey() => sourceUrl;

  /// Legado `sortUrls()`: `name::url` entries separated by `&&`/newlines (or `<js>`/`@js:` producing them); no sortUrl means the
  /// source url itself under an empty name.
  Future<List<(String, String)>> sortUrls() async {
    var rule = sortUrl ?? '';
    if (rule.trim().isEmpty) return [('', sourceUrl)];
    final lower = rule.toLowerCase();
    if (lower.startsWith('<js>') || lower.startsWith('@js:')) {
      final cacheKey = 'sortUrl_$sourceUrl';
      var cached = CacheManager.getString(cacheKey);
      if (cached == null || cached.trim().isEmpty) {
        final js = lower.startsWith('@js:') ? rule.substring(4) : rule.substring(4, rule.lastIndexOf('<') > 4 ? rule.lastIndexOf('<') : rule.length);
        final v = await evalJS(js);
        cached = (v == null ? '' : '$v').trim();
        CacheManager.put(cacheKey, cached);
      }
      rule = cached;
    }
    final out = <(String, String)>[];
    for (final part in rule.split(RegExp(r'(&&|\n)+'))) {
      final d = part.split('::');
      if (d.length > 1) out.add((d[0].trim(), d[1].trim()));
    }
    return out.isEmpty ? [('', sourceUrl)] : out;
  }

  @override
  bool operator ==(Object other) => other is RssSource && other.sourceUrl == sourceUrl;

  @override
  int get hashCode => sourceUrl.hashCode;
}
