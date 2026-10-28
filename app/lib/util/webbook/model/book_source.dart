// util/webbook/model/book_source.dart - Legado `BookSource` (30 slots, JSON keys in constructor order of 0x185ff4) and the explore
// entries (`exploreUrl`: `title::url` lists, JSON arrays, or JS producing either).
import 'dart:convert';

import '../../../models/explore.dart' as m;
import '../../json.dart';
import '../util/cache_manager.dart';
import 'base_source.dart';
import 'rule.dart';

/// Flexbox hints of an explore button (`layout_flexGrow` ... as in upstream Legado's `ExploreKind.Style`).
class ExploreKindStyle {
  double layoutFlexGrow;
  double layoutFlexShrink;
  String layoutAlignSelf;
  double layoutFlexBasisPercent;
  bool layoutWrapBefore;

  ExploreKindStyle({
    this.layoutFlexGrow = 0,
    this.layoutFlexShrink = 1,
    this.layoutAlignSelf = 'auto',
    this.layoutFlexBasisPercent = -1,
    this.layoutWrapBefore = false,
  });

  factory ExploreKindStyle.fromJson(Map<String, dynamic> j) => ExploreKindStyle(
        layoutFlexGrow: jsonutil.asDouble(j['layout_flexGrow'], 0),
        layoutFlexShrink: jsonutil.asDouble(j['layout_flexShrink'], 1),
        layoutAlignSelf: jsonutil.asString(j['layout_alignSelf'], 'auto'),
        layoutFlexBasisPercent: jsonutil.asDouble(j['layout_flexBasisPercent'], -1),
        layoutWrapBefore: jsonutil.asBool(j['layout_wrapBefore']),
      );

  Map<String, dynamic> toJson() => {
        'layout_flexGrow': layoutFlexGrow,
        'layout_flexShrink': layoutFlexShrink,
        'layout_alignSelf': layoutAlignSelf,
        'layout_flexBasisPercent': layoutFlexBasisPercent,
        'layout_wrapBefore': layoutWrapBefore,
      };
}

/// One entry of the discovery page: a title (button label) and the URL rule to load. The app's `models/explore.dart` `Explore`
/// carries the additional keys `type width default js chars action useShouldOverrideUrlLoading`, kept here as well.
class ExploreKind {
  /// Kind types (`type` is a number in the app's models; Legado writes the names): a list url, a section title, a button that
  /// runs `action`, a text input, a choice from `chars`, a toggle through `chars`.
  static const int typeUrl = 0, typeTitle = 1, typeButton = 2, typeText = 3, typeSelect = 4, typeToggle = 5;
  static const Map<String, int> typeNames = {
    'url': typeUrl, 'title': typeTitle, 'button': typeButton, 'text': typeText, 'select': typeSelect, 'toggle': typeToggle,
  };

  static int parseType(Object? v) {
    if (v is String && typeNames.containsKey(v.trim().toLowerCase())) return typeNames[v.trim().toLowerCase()]!;
    return jsonutil.asInt(v);
  }

  String title;
  String? url;
  ExploreKindStyle? style;
  int type;
  int width;
  String defaultValue;
  List<dynamic> chars;
  String action;
  String js;
  bool useShouldOverrideUrlLoading;

  ExploreKind(this.title, [this.url, this.style])
      : type = 0,
        width = 0,
        defaultValue = '',
        chars = [],
        action = '',
        js = '',
        useShouldOverrideUrlLoading = false;

  factory ExploreKind.fromJson(Map<String, dynamic> j) {
    final k = ExploreKind(jsonutil.asString(j['title']), jsonutil.optString(j['url']));
    final st = jsonutil.asMap(j['style']);
    if (st != null) k.style = ExploreKindStyle.fromJson(st);
    k.type = parseType(j['type']);
    k.width = jsonutil.asInt(j['width']);
    k.defaultValue = jsonutil.asString(j['default']);
    k.chars = jsonutil.asList(j['chars']) ?? [];
    k.action = jsonutil.asString(j['action']);
    k.js = jsonutil.asString(j['js']);
    k.useShouldOverrideUrlLoading = jsonutil.asBool(j['useShouldOverrideUrlLoading']);
    return k;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        if (style != null) 'style': style!.toJson(),
        'type': type,
        'width': width,
        'default': defaultValue,
        'chars': chars,
        'action': action,
        'js': js,
        'useShouldOverrideUrlLoading': useShouldOverrideUrlLoading,
      };

  /// The app model (`lib/models/explore.dart`).
  m.Explore toExplore() => m.Explore(
        title: title,
        url: url ?? '',
        js: js,
        type_: type,
        width: width,
        default_: defaultValue,
        chars: chars,
        action: action,
        useShouldOverrideUrlLoading: useShouldOverrideUrlLoading,
      );
}

class BookSource extends BaseSource {
  String bookSourceName;
  String? bookSourceGroup;
  @override
  String? loginUi;
  String bookSourceUrl;

  /// 0 text, 1 audio, 2 image, 3 file.
  int bookSourceType;
  String? bookUrlPattern;
  int customOrder;
  bool enabled;
  bool enabledExplore;
  bool customButton;
  bool eventListener;
  @override
  String? concurrentRate;
  @override
  String? header;
  @override
  String? loginUrl;
  @override
  String? loginCheckJs;
  int lastUpdateTime;
  int weight;
  String? exploreUrl;
  ExploreRule? ruleExplore;
  String? searchUrl;
  SearchRule? ruleSearch;
  BookInfoRule? ruleBookInfo;
  TocRule? ruleToc;
  ContentRule? ruleContent;
  String? bookSourceComment;
  String? coverDecodeJs;
  int respondTime;
  @override
  String? jsLib;
  @override
  bool enabledCookieJar;
  @override
  String? variableComment;

  /// Keys the engine does not know (kept so that exporting a source does not lose data).
  Map<String, dynamic> extra;

  BookSource({
    this.bookSourceName = '',
    this.bookSourceGroup,
    this.loginUi,
    this.bookSourceUrl = '',
    this.bookSourceType = 0,
    this.bookUrlPattern,
    this.customOrder = 0,
    this.enabled = true,
    this.enabledExplore = true,
    this.customButton = false,
    this.eventListener = false,
    this.concurrentRate,
    this.header,
    this.loginUrl,
    this.loginCheckJs,
    this.lastUpdateTime = 0,
    this.weight = 0,
    this.exploreUrl,
    this.ruleExplore,
    this.searchUrl,
    this.ruleSearch,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
    this.bookSourceComment,
    this.coverDecodeJs,
    this.respondTime = 180000,
    this.jsLib,
    this.enabledCookieJar = true,
    this.variableComment,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  static const Set<String> _known = {
    'bookSourceName', 'bookSourceGroup', 'loginUi', 'bookSourceUrl', 'bookSourceType', 'bookUrlPattern', 'customOrder', 'enabled',
    'enabledExplore', 'customButton', 'eventListener', 'concurrentRate', 'header', 'loginUrl', 'loginCheckJs', 'lastUpdateTime',
    'weight', 'exploreUrl', 'ruleExplore', 'searchUrl', 'ruleSearch', 'ruleBookInfo', 'ruleToc', 'ruleContent', 'bookSourceComment',
    'coverDecodeJs', 'respondTime', 'jsLib', 'enabledCookieJar', 'variableComment',
  };

  factory BookSource.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? rule(String k) => jsonutil.asMap(j[k]);
    final re = rule('ruleExplore'), rs = rule('ruleSearch'), ri = rule('ruleBookInfo'), rt = rule('ruleToc'), rc = rule('ruleContent');
    return BookSource(
      bookSourceName: jsonutil.asString(j['bookSourceName']),
      bookSourceGroup: jsonutil.optString(j['bookSourceGroup']),
      loginUi: jsonutil.optString(j['loginUi']),
      bookSourceUrl: jsonutil.asString(j['bookSourceUrl']),
      bookSourceType: jsonutil.asInt(j['bookSourceType']),
      bookUrlPattern: jsonutil.optString(j['bookUrlPattern']),
      customOrder: jsonutil.asInt(j['customOrder']),
      enabled: jsonutil.asBool(j['enabled'], true),
      enabledExplore: jsonutil.asBool(j['enabledExplore'], true),
      customButton: jsonutil.asBool(j['customButton']),
      eventListener: jsonutil.asBool(j['eventListener']),
      concurrentRate: jsonutil.optString(j['concurrentRate']),
      header: jsonutil.optString(j['header']),
      loginUrl: jsonutil.optString(j['loginUrl']),
      loginCheckJs: jsonutil.optString(j['loginCheckJs']),
      lastUpdateTime: jsonutil.asInt(j['lastUpdateTime']),
      weight: jsonutil.asInt(j['weight']),
      exploreUrl: jsonutil.optString(j['exploreUrl']),
      ruleExplore: re == null ? null : ExploreRule.fromJson(re),
      searchUrl: jsonutil.optString(j['searchUrl']),
      ruleSearch: rs == null ? null : SearchRule.fromJson(rs),
      ruleBookInfo: ri == null ? null : BookInfoRule.fromJson(ri),
      ruleToc: rt == null ? null : TocRule.fromJson(rt),
      ruleContent: rc == null ? null : ContentRule.fromJson(rc),
      bookSourceComment: jsonutil.optString(j['bookSourceComment']),
      coverDecodeJs: jsonutil.optString(j['coverDecodeJs']),
      respondTime: jsonutil.asInt(j['respondTime'], 180000),
      jsLib: jsonutil.optString(j['jsLib']),
      enabledCookieJar: jsonutil.asBool(j['enabledCookieJar'], true),
      variableComment: jsonutil.optString(j['variableComment']),
      extra: {for (final e in j.entries) if (!_known.contains(e.key)) e.key: e.value},
    );
  }

  /// A JSON object, or a JSON array whose first element is used.
  factory BookSource.fromJsonString(String s) {
    final d = jsonDecode(s);
    if (d is List && d.isNotEmpty) return BookSource.fromJson(Map<String, dynamic>.from(d.first as Map));
    return BookSource.fromJson(Map<String, dynamic>.from(d as Map));
  }

  static List<BookSource> listFromJsonString(String s) {
    final d = jsonDecode(s);
    if (d is List) return [for (final e in d) if (e is Map) BookSource.fromJson(Map<String, dynamic>.from(e))];
    if (d is Map) return [BookSource.fromJson(Map<String, dynamic>.from(d))];
    return [];
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        'bookSourceName': bookSourceName,
        'bookSourceGroup': bookSourceGroup,
        'loginUi': loginUi,
        'bookSourceUrl': bookSourceUrl,
        'bookSourceType': bookSourceType,
        'bookUrlPattern': bookUrlPattern,
        'customOrder': customOrder,
        'enabled': enabled,
        'enabledExplore': enabledExplore,
        'customButton': customButton,
        'eventListener': eventListener,
        'concurrentRate': concurrentRate,
        'header': header,
        'loginUrl': loginUrl,
        'loginCheckJs': loginCheckJs,
        'lastUpdateTime': lastUpdateTime,
        'weight': weight,
        'exploreUrl': exploreUrl,
        'ruleExplore': ruleExplore?.toJson(),
        'searchUrl': searchUrl,
        'ruleSearch': ruleSearch?.toJson(),
        'ruleBookInfo': ruleBookInfo?.toJson(),
        'ruleToc': ruleToc?.toJson(),
        'ruleContent': ruleContent?.toJson(),
        'bookSourceComment': bookSourceComment,
        'coverDecodeJs': coverDecodeJs,
        'respondTime': respondTime,
        'jsLib': jsLib,
        'enabledCookieJar': enabledCookieJar,
        'variableComment': variableComment,
      };

  @override
  String getKey() => bookSourceUrl;

  @override
  String get sourceName => bookSourceName;

  @override
  String get sourceComment => bookSourceComment ?? '';

  SearchRule getSearchRule() => ruleSearch ??= SearchRule();
  ExploreRule getExploreRule() => ruleExplore ??= ExploreRule();
  BookInfoRule getBookInfoRule() => ruleBookInfo ??= BookInfoRule();
  TocRule getTocRule() => ruleToc ??= TocRule();
  ContentRule getContentRule() => ruleContent ??= ContentRule();

  @override
  Object? jsGet(String name) {
    switch (name) {
      case 'bookSourceName':
        return bookSourceName;
      case 'bookSourceGroup':
        return bookSourceGroup;
      case 'bookSourceType':
        return bookSourceType;
      case 'searchUrl':
        return searchUrl;
      case 'exploreUrl':
        return exploreUrl;
    }
    return super.jsGet(name);
  }

  @override
  Map<String, Object?> jsSnapshot() => {
        ...super.jsSnapshot(),
        'bookSourceGroup': bookSourceGroup,
        'bookSourceType': bookSourceType,
        'searchUrl': searchUrl,
        'exploreUrl': exploreUrl,
      };

  // explore -------------------------------------------------------------------------------------------------------------------------
  /// Legado `exploreKinds()`: `exploreUrl` may be `<js>..</js>` / `@js:..` (evaluated once and cached), a JSON array, or
  /// `title::url` entries separated by `&&` or newlines.
  Future<List<ExploreKind>> exploreKinds({bool refresh = false}) async {
    var rule = exploreUrl ?? '';
    if (rule.trim().isEmpty) return [];
    final kinds = <ExploreKind>[];
    try {
      final lower = rule.toLowerCase();
      if (lower.startsWith('<js>') || lower.startsWith('@js:')) {
        final cacheKey = 'exploreKinds_$bookSourceUrl';
        var cached = refresh ? null : CacheManager.getString(cacheKey);
        if (cached == null || cached.trim().isEmpty) {
          final js = lower.startsWith('@js:') ? rule.substring(4) : rule.substring(4, rule.lastIndexOf('<') > 4 ? rule.lastIndexOf('<') : rule.length);
          final v = await evalJS(js);
          cached = (v == null ? '' : (v is String ? v : jsonEncode(v))).trim();
          CacheManager.put(cacheKey, cached);
        }
        rule = cached;
      }
      if (jsonutil.isJsonArray(rule)) {
        final list = jsonDecode(rule) as List;
        for (final e in list) {
          if (e is Map) kinds.add(ExploreKind.fromJson(Map<String, dynamic>.from(e)));
        }
      } else {
        for (final part in rule.split(RegExp(r'(&&|\n)+'))) {
          final d = part.split('::');
          if (d.length > 1) kinds.add(ExploreKind(d[0].trim(), d[1].trim()));
        }
      }
    } catch (e) {
      kinds.add(ExploreKind('ERROR', e.toString()));
    }
    return kinds;
  }

  void clearExploreKindsCache() => CacheManager.delete('exploreKinds_$bookSourceUrl');

  @override
  String toString() => bookSourceName;

  @override
  bool operator ==(Object other) => other is BookSource && other.bookSourceUrl == bookSourceUrl;

  @override
  int get hashCode => bookSourceUrl.hashCode;
}
