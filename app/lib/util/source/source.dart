// util/source/source.dart — `BaseSource` (class 1222, five fields: url, name, html, …): the view of a 时光源 (轻悦时光书源) that the
// web-view runtime needs. A 时光源 is a source JSON whose `html` field holds an HTML page (code, or an http(s) URL of the page) that
// defines the async functions search / info / chapter / content / getfinds / find / getloginurl / login / pay / imagedecrypt …
// (template strings pp+0x52e50..0x53298 of the original); the app runs the page in a web view and calls those functions
// (util/source/run.dart).
//
// The replica stores every source as its raw JSON map (data/source.dart). A map is a 时光源 when it has an `html` engine that is not a
// 阅读源 marker (`@yuedu…`), no Legado rules and is not a source of the bound 轻阅读 backend (`isqread`); pages/source/edit_source.dart
// (`sourceKindOf`) uses the same rule.
import '../webbook/model/book_source.dart';

class BaseSource {
  final String bookSourceUrl;
  final String bookSourceName;

  /// The page: HTML code, or the http(s) URL of the page.
  final String html;

  /// 需要登录 / 启用帮助 / 定制按钮 / 事件监听 / 启用发现 (the editor's switches, pages/source/edit_sgsource.dart).
  final bool login;
  final bool help;
  final bool customButton;
  final bool eventListener;
  final bool enabledExplore;

  const BaseSource({
    required this.bookSourceUrl,
    this.bookSourceName = '',
    this.html = '',
    this.login = false,
    this.help = false,
    this.customButton = false,
    this.eventListener = false,
    this.enabledExplore = true,
  });

  static bool _flag(Object? v, bool def) => v == null ? def : (v is bool ? v : '$v' == 'true' || '$v' == '1');

  factory BaseSource.fromJson(Map<String, dynamic> m) => BaseSource(
        bookSourceUrl: '${m['bookSourceUrl'] ?? ''}'.trim(),
        bookSourceName: '${m['bookSourceName'] ?? ''}',
        html: m['html'] is String ? m['html'] as String : '',
        login: _flag(m['login'], false),
        help: _flag(m['help'], false),
        customButton: _flag(m['customButton'], false),
        eventListener: _flag(m['eventListener'], false),
        enabledExplore: _flag(m['enabledExplore'], true),
      );

  /// Keys whose presence makes a map a Legado (阅读) source.
  static const Set<String> legadoKeys = {'searchUrl', 'exploreUrl', 'ruleSearch', 'ruleExplore', 'ruleBookInfo', 'ruleToc', 'ruleContent', 'bookSourceType'};

  /// Whether the stored source map [raw] is a 时光源.
  static bool isTimeSource(Map<String, dynamic>? raw) {
    if (raw == null) return false;
    if (raw['isqread'] == true || '${raw['isqread']}' == 'true') return false;
    final html = raw['html'];
    if (html is! String) return false;
    final t = html.trim();
    return t.isNotEmpty && !t.startsWith('@yuedu') && !raw.keys.any(legadoKeys.contains);
  }

  /// The page is fetched from a URL (instead of being the HTML itself).
  bool get htmlIsUrl {
    final t = html.trim().toLowerCase();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  @override
  String toString() => '$bookSourceName($bookSourceUrl)';
}

extension TimeSourceBookSource on BookSource {
  /// The engine source is a 时光源 (its `html` and the editor's switches are kept in [BookSource.extra]).
  bool get isTimeSource {
    final hasRules = (searchUrl ?? '').isNotEmpty ||
        (exploreUrl ?? '').isNotEmpty ||
        ruleSearch != null ||
        ruleExplore != null ||
        ruleBookInfo != null ||
        ruleToc != null ||
        ruleContent != null;
    return !hasRules && BaseSource.isTimeSource({...extra, 'bookSourceUrl': bookSourceUrl});
  }

  BaseSource toBaseSource() => BaseSource.fromJson({
        ...extra,
        'bookSourceUrl': bookSourceUrl,
        'bookSourceName': bookSourceName,
        'enabledExplore': enabledExplore,
        'customButton': customButton,
        'eventListener': eventListener,
      });
}
