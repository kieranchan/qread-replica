// util/webbook/analyze_rule/analyze_rule.dart - the rule interpreter (Legado `AnalyzeRule`). One rule string is split into steps
// (`<js>..</js>`, `@js:`, `@css:`, `@xpath:`, `@json:`, `:regex`, default) which are applied in order; `@put:{}` / `@get:{}`,
// `{{ }}` templates and `##regex##replacement###` are resolved per step. Fields of the original (names preserved where the AOT
// snapshot kept them): `_htmlEntityRe _evalPattern _regexPattern _putPattern _jsPattern _webJsPattern`, enum `Mode`, class `SourceRule`.
import 'dart:convert';

import 'package:html/dom.dart' as dom;

import '../../format.dart';
import '../../html/entities.dart';
import '../../html/jsoup.dart';
import '../../html/xpath.dart';
import '../../legado/java_regex.dart';
import '../../legado/js_bindable.dart';
import '../../legado/js_bindable_compat.dart';
import '../../legado/js_runtime.dart';
import '../model/base_source.dart';
import '../model/book.dart';
import '../model/book_chapter.dart';
import '../util/network_utils.dart';
import 'analyze_by_json_path.dart';
import 'analyze_by_jsoup.dart';
import 'analyze_by_xpath.dart';
import 'js_extensions.dart';
import 'rule_data.dart';

enum Mode { xpath, json, default_, js, regex }

final RegExp _evalPattern = RegExp(r'@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}', caseSensitive: false);
final RegExp _regexPattern = RegExp(r'\$\d{1,2}');
final RegExp _putPattern = RegExp(r'@put:(\{[^}]+?\})', caseSensitive: false);
final RegExp _jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);

class AnalyzeRule extends JsExtensions {
  RuleDataInterface? ruleData;
  final BaseSource? source;
  final bool preUpdateJs;

  BookChapter? chapter;
  String? nextChapterUrl;
  Object? content;
  String? baseUrl;
  String? redirectUrl;
  bool isJSON = false;
  bool isRegex = false;

  AnalyzeByXPath? _analyzeByXPath;
  AnalyzeByJSoup? _analyzeByJSoup;
  AnalyzeByJSonPath? _analyzeByJSonPath;
  Object? _xpContent, _jpContent, _jsonContent;

  AnalyzeRule([this.ruleData, this.source, this.preUpdateJs = false]);

  BaseBook? get book => ruleData is BaseBook ? ruleData as BaseBook : null;

  @override
  BaseSource? getSource() => source;
  @override
  RuleDataInterface? get ruleDataForJs => ruleData;
  @override
  BookChapter? get chapterForJs => chapter;
  @override
  BaseBook? get bookForJs => book;

  AnalyzeRule setChapter(BookChapter? c) {
    chapter = c;
    return this;
  }

  AnalyzeRule setRuleData(RuleDataInterface? d) {
    ruleData = d;
    return this;
  }

  /// Sets what the next rules are applied to (String, Element, XNode, decoded JSON value, regex-group list).
  AnalyzeRule setContent(Object? content, [String? baseUrl]) {
    if (content == null) throw StateError('内容不可空（Content cannot be null）');
    this.content = content;
    if (content is Map || content is List) {
      isJSON = true;
    } else {
      final t = content.toString().trim();
      isJSON = t.startsWith('{') || t.startsWith('[');
    }
    setBaseUrl(baseUrl);
    _xpContent = _jpContent = _jsonContent = null;
    _analyzeByXPath = null;
    _analyzeByJSoup = null;
    _analyzeByJSonPath = null;
    return this;
  }

  AnalyzeRule setBaseUrl(String? baseUrl) {
    if (baseUrl != null) this.baseUrl = baseUrl;
    return this;
  }

  /// Remembers the url that loaded the content; relative result urls are resolved against it.
  String? setRedirectUrl(String url) {
    final u = Uri.tryParse(url);
    if (u != null && u.hasScheme) {
      redirectUrl = url;
    }
    return redirectUrl;
  }

  AnalyzeByXPath _getAnalyzeByXPath(Object o) {
    if (!identical(o, content)) return AnalyzeByXPath(o);
    if (_analyzeByXPath == null || !identical(_xpContent, o)) {
      _analyzeByXPath = AnalyzeByXPath(o);
      _xpContent = o;
    }
    return _analyzeByXPath!;
  }

  AnalyzeByJSoup _getAnalyzeByJSoup(Object o) {
    if (!identical(o, content)) return AnalyzeByJSoup(o);
    if (_analyzeByJSoup == null || !identical(_jpContent, o)) {
      _analyzeByJSoup = AnalyzeByJSoup(o);
      _jpContent = o;
    }
    return _analyzeByJSoup!;
  }

  AnalyzeByJSonPath _getAnalyzeByJSonPath(Object o) {
    final src = (o is Map || o is List || o is String) ? o : o.toString();
    if (!identical(o, content)) return AnalyzeByJSonPath(src);
    if (_analyzeByJSonPath == null || !identical(_jsonContent, o)) {
      _analyzeByJSonPath = AnalyzeByJSonPath(src);
      _jsonContent = o;
    }
    return _analyzeByJSonPath!;
  }

  // ------------------------------------------------------------------------------------------------------------------------------
  // public read API
  // ------------------------------------------------------------------------------------------------------------------------------

  /// The single element/value selected by [ruleStr] (used for `bookInfo.init`).
  Future<Object?> getElement(String ruleStr) async {
    if (ruleStr.isEmpty) return null;
    Object? result;
    final c = content;
    final ruleList = splitSourceRule(ruleStr, allInOne: true);
    if (c != null && ruleList.isNotEmpty) {
      result = c;
      for (final sourceRule in ruleList) {
        await _putRule(sourceRule.putMap);
        await sourceRule.makeUpRule(result);
        if (result != null) {
          final it = result;
          switch (sourceRule.mode) {
            case Mode.regex:
              result = AnalyzeByRegex.getElement(it.toString(), _splitNotBlank(sourceRule.rule, '&&'));
              break;
            case Mode.json:
              result = _getAnalyzeByJSonPath(it).getObject(sourceRule.rule);
              break;
            case Mode.xpath:
              result = _nodesToContent(_getAnalyzeByXPath(it).getElements(sourceRule.rule));
              break;
            case Mode.js:
              result = await evalJS(sourceRule.rule, it);
              break;
            case Mode.default_:
              result = _nodesToContent(_getAnalyzeByJSoup(it).getElements(sourceRule.rule));
              break;
          }
        }
        if (result != null && sourceRule.replaceRegex.isNotEmpty && result is String) {
          result = _replaceRegex(result, sourceRule);
        }
      }
    }
    return result;
  }

  Future<List<String>?> getStringList(Object? rule, {Object? mContent, bool isUrl = false}) async {
    if (rule == null) return null;
    if (rule is String) {
      if (rule.isEmpty) return null;
      return _getStringListRules(splitSourceRule(rule), mContent, isUrl);
    }
    return _getStringListRules(rule as List<SourceRule>, mContent, isUrl);
  }

  Future<List<String>?> _getStringListRules(List<SourceRule> ruleList, Object? mContent, bool isUrl) async {
    Object? result;
    final c = mContent ?? content;
    if (c != null && ruleList.isNotEmpty) {
      result = c;
      if (c is Map) {
        result = c[ruleList[0].rule]?.toString();
      } else {
        for (final sourceRule in ruleList) {
          await _putRule(sourceRule.putMap);
          await sourceRule.makeUpRule(result);
          if (result != null) {
            final it = result;
            switch (sourceRule.mode) {
              case Mode.js:
                result = await evalJS(sourceRule.rule, it);
                break;
              case Mode.json:
                result = _getAnalyzeByJSonPath(it).getStringList(sourceRule.rule);
                break;
              case Mode.xpath:
                result = _getAnalyzeByXPath(it).getStringList(sourceRule.rule);
                break;
              case Mode.default_:
                result = _getAnalyzeByJSoup(it).getStringList(sourceRule.rule);
                break;
              case Mode.regex:
                result = sourceRule.rule;
                break;
            }
            if (sourceRule.replaceRegex.isNotEmpty && result is List) {
              result = [for (final item in result) _replaceRegex(jsToString(item), sourceRule)];
            } else if (sourceRule.replaceRegex.isNotEmpty) {
              result = _replaceRegex(jsToString(result), sourceRule);
            }
          }
        }
      }
    }
    if (result == null) return null;
    if (result is String) {
      result = result.split('\n');
    }
    final list = result is List ? [for (final e in result) e is String ? e : jsToString(e)] : <String>[];
    if (isUrl) {
      final urlList = <String>[];
      for (final url in list) {
        final abs = NetworkUtils.getAbsoluteURL(redirectUrl, url);
        if (abs.isNotEmpty && !urlList.contains(abs)) urlList.add(abs);
      }
      return urlList;
    }
    return list;
  }

  /// [rule] is a rule string or a pre-split `List<SourceRule>` (see [splitSourceRule]).
  Future<String> getString(Object? rule, {Object? mContent, bool isUrl = false, bool unescape = true}) async {
    if (rule == null) return '';
    if (rule is String) {
      if (rule.isEmpty) return '';
      return _getStringRules(splitSourceRule(rule), mContent, isUrl, unescape);
    }
    return _getStringRules(rule as List<SourceRule>, mContent, isUrl, unescape);
  }

  Future<String> _getStringRules(List<SourceRule> ruleList, Object? mContent, bool isUrl, bool unescape) async {
    Object? result;
    final c = mContent ?? content;
    if (c != null && ruleList.isNotEmpty) {
      result = c;
      if (result is Map) {
        result = result[ruleList[0].rule]?.toString();
      } else {
        for (final sourceRule in ruleList) {
          await _putRule(sourceRule.putMap);
          await sourceRule.makeUpRule(result);
          if (sourceRule.rule.isNotEmpty || sourceRule.replaceRegex.isEmpty) {
            if (result != null) {
              final it = result;
              switch (sourceRule.mode) {
                case Mode.js:
                  result = await evalJS(sourceRule.rule, it);
                  break;
                case Mode.json:
                  result = _getAnalyzeByJSonPath(it).getString(sourceRule.rule);
                  break;
                case Mode.xpath:
                  result = _getAnalyzeByXPath(it).getString(sourceRule.rule);
                  break;
                case Mode.default_:
                  result = (isUrl && sourceRule.rule.trim().isEmpty) ? baseUrl : _getAnalyzeByJSoup(it).getString(sourceRule.rule);
                  break;
                case Mode.regex:
                  result = sourceRule.rule;
                  break;
              }
            }
          }
          if (result != null && sourceRule.replaceRegex.isNotEmpty) {
            result = _replaceRegex(jsToString(result), sourceRule);
          }
        }
      }
    }
    result ??= '';
    final str = unescape ? htmlDecode(jsToString(result)) : jsToString(result);
    if (isUrl) {
      return str.trim().isEmpty ? (baseUrl ?? '') : NetworkUtils.getAbsoluteURL(redirectUrl, str);
    }
    return str;
  }

  /// The elements selected by [ruleStr] (Elements / XNodes / decoded JSON values / regex-group lists).
  Future<List<Object>> getElements(String ruleStr) async {
    Object? result;
    final c = content;
    final ruleList = splitSourceRule(ruleStr, allInOne: true);
    if (c != null && ruleList.isNotEmpty) {
      result = c;
      for (final sourceRule in ruleList) {
        await _putRule(sourceRule.putMap);
        if (result != null) {
          final it = result;
          switch (sourceRule.mode) {
            case Mode.regex:
              result = AnalyzeByRegex.getElements(it.toString(), _splitNotBlank(sourceRule.rule, '&&'));
              break;
            case Mode.json:
              result = _getAnalyzeByJSonPath(it).getList(sourceRule.rule);
              break;
            case Mode.xpath:
              result = _getAnalyzeByXPath(it).getElements(sourceRule.rule);
              break;
            case Mode.js:
              result = await evalJS(sourceRule.rule, it);
              break;
            case Mode.default_:
              result = _getAnalyzeByJSoup(it).getElements(sourceRule.rule);
              break;
          }
          if (sourceRule.replaceRegex.isNotEmpty && result is String) {
            result = _replaceRegex(result, sourceRule);
          }
        }
      }
    }
    if (result is List) return List<Object>.from(result.whereType<Object>());
    return [];
  }

  // ------------------------------------------------------------------------------------------------------------------------------
  // variables
  // ------------------------------------------------------------------------------------------------------------------------------
  Future<void> _putRule(Map<String, String> map) async {
    for (final e in map.entries) {
      put(e.key, await getString(e.value));
    }
  }

  /// `@put:{key:rule}` storage (chapter first, then book, then plain rule data).
  String put(String key, String value) => putVar(key, value);

  /// `@get:{key}`; `bookName` and `title` are the book name / chapter title.
  String get(String key) => getVar(key);

  // ------------------------------------------------------------------------------------------------------------------------------
  // rule splitting
  // ------------------------------------------------------------------------------------------------------------------------------
  /// Legado keeps the element *list* as the new content, which prints as `[<el>, <el>]` and is re-parsed as HTML. The equivalent here:
  /// one node stays a node; several nodes become one HTML/text string.
  static Object? _nodesToContent(List<Object>? nodes) {
    if (nodes == null || nodes.isEmpty) return null;
    if (nodes.length == 1) return nodes.first;
    return nodes.map((e) => e is XNode ? e.asString() : e is dom.Node ? jOuterHtml(e) : e.toString()).join('\n');
  }

  static List<String> _splitNotBlank(String s, String sep) => s.split(sep).where((e) => e.trim().isNotEmpty).toList();

  String _replaceRegex(String result, SourceRule rule) {
    if (rule.replaceRegex.isEmpty) return result;
    if (rule.replaceFirst) {
      RegExp re;
      try {
        re = JavaRegex.compile(rule.replaceRegex);
      } on FormatException {
        re = RegExp(RegExp.escape(rule.replaceRegex));
      }
      final m = re.firstMatch(result);
      if (m == null) return '';
      final matched = m.group(0)!;
      try {
        return JavaRegex.replaceFirst(matched, re, rule.replacement);
      } on FormatException {
        return matched.replaceFirst(rule.replaceRegex, rule.replacement);
      }
    }
    try {
      return JavaRegex.replaceAll(result, JavaRegex.compile(rule.replaceRegex), rule.replacement);
    } on FormatException {
      return result.replaceAll(rule.replaceRegex, rule.replacement);
    }
  }

  /// Splits a rule string into its steps. With [allInOne] a leading `:` switches to whole-match regex mode (`isRegex`).
  List<SourceRule> splitSourceRule(String? ruleStr, {bool allInOne = false}) {
    final ruleList = <SourceRule>[];
    if (ruleStr == null || ruleStr.isEmpty) return ruleList;
    var mMode = Mode.default_;
    var start = 0;
    if (allInOne && ruleStr.startsWith(':')) {
      mMode = Mode.regex;
      isRegex = true;
      start = 1;
    } else if (isRegex) {
      mMode = Mode.regex;
    }
    for (final m in _jsPattern.allMatches(ruleStr)) {
      if (m.start > start) {
        final tmp = ruleStr.substring(start, m.start).trim();
        if (tmp.isNotEmpty) ruleList.add(SourceRule(this, tmp, mMode));
      }
      ruleList.add(SourceRule(this, m.group(2) ?? m.group(1) ?? '', Mode.js));
      start = m.end;
    }
    if (ruleStr.length > start) {
      final tmp = ruleStr.substring(start).trim();
      if (tmp.isNotEmpty) ruleList.add(SourceRule(this, tmp, mMode));
    }
    return ruleList;
  }

  // ------------------------------------------------------------------------------------------------------------------------------
  // JavaScript
  // ------------------------------------------------------------------------------------------------------------------------------
  /// Converts rule values to what JS can hold.
  static Object? jsValue(Object? v) {
    if (v == null || v is String || v is num || v is bool) return v;
    if (v is Map) return v;
    if (v is List) return v.map(jsValue).toList();
    if (v is XNode) return v.asString();
    if (v is dom.Node) return jOuterHtml(v);
    return v.toString();
  }

  @override
  void fillBindings(JsBindings b) {
    b.values['baseUrl'] = baseUrl;
    b.values['title'] = chapter?.title;
    b.values['src'] = jsValue(content);
    b.values['nextChapterUrl'] = nextChapterUrl;
  }

  /// Runs rule JavaScript with `result` bound; returns its value (JSON-like).
  Future<Object?> evalJS(String jsStr, [Object? result]) => runJs(jsStr, values: {'result': jsValue(result)});

  // JsBindable: the extra `java.*` members of the rule analyzer ----------------------------------------------------------------
  @override
  Iterable<String> get jsMethods => [...super.jsMethods, 'put', 'get'];

  @override
  Object? jsCall(String name, List<Object?> args) {
    String s(int i) => i < args.length && args[i] != null ? jsToString(args[i]) : '';
    switch (name) {
      case 'put':
        if (args.length == 2) return put(s(0), s(1));
        break;
      case 'get':
        if (args.length == 1) return get(s(0));
        break;
      case 'getString':
        {
          final rule = s(0);
          final mc = args.length > 1 ? args[1] : null;
          final isUrl = args.length > 2 && args[2] == true;
          return jsAwait('getString:$rule:${jsonEncode(jsValue(mc))}:$isUrl', () => getString(rule, mContent: mc, isUrl: isUrl));
        }
      case 'getStringList':
        {
          final rule = s(0);
          final mc = args.length > 1 ? args[1] : null;
          final isUrl = args.length > 2 && args[2] == true;
          return jsAwait('getStringList:$rule:${jsonEncode(jsValue(mc))}:$isUrl', () => getStringList(rule, mContent: mc, isUrl: isUrl));
        }
      case 'getElement':
        {
          final rule = s(0);
          return jsAwait('getElement:$rule', () async => jsValue(await getElement(rule)));
        }
      case 'getElements':
        {
          final rule = s(0);
          return jsAwait('getElements:$rule', () async => (await getElements(rule)).map(jsValue).toList());
        }
      case 'setContent':
        if (args.isNotEmpty && args[0] != null) {
          setContent(args[0], args.length > 1 && args[1] != null ? s(1) : null);
        }
        return null;
    }
    return super.jsCall(name, args);
  }

  /// The rule text as results: `Format.isTrue` helper used by the list parsers.
  static bool isTrue(String? s) => Format.isTrue(s);
}

/// One step of a rule: the rule text with its mode, `##regex##replacement###` and `@put` parts, plus the template pieces that are
/// substituted by [makeUpRule].
class SourceRule {
  final AnalyzeRule _a;
  Mode mode;
  late String rule;
  String replaceRegex = '';
  String replacement = '';
  bool replaceFirst = false;
  final Map<String, String> putMap = {};
  final List<String> _ruleParam = [];
  final List<int> _ruleType = [];

  static const int _getRuleType = -2;
  static const int _jsRuleType = -1;
  static const int _defaultRuleType = 0;

  SourceRule(this._a, String ruleStr, Mode mainMode) : mode = mainMode {
    final lower = ruleStr.toLowerCase();
    if (mode == Mode.js || mode == Mode.regex) {
      rule = ruleStr;
    } else if (lower.startsWith('@css:')) {
      mode = Mode.default_;
      rule = ruleStr;
    } else if (ruleStr.startsWith('@@')) {
      mode = Mode.default_;
      rule = ruleStr.substring(2);
    } else if (lower.startsWith('@xpath:')) {
      mode = Mode.xpath;
      rule = ruleStr.substring(7);
    } else if (lower.startsWith('@json:')) {
      mode = Mode.json;
      rule = ruleStr.substring(6);
    } else if (_a.isJSON || ruleStr.startsWith(r'$.') || ruleStr.startsWith(r'$[')) {
      mode = Mode.json;
      rule = ruleStr;
    } else if (ruleStr.startsWith('/')) {
      mode = Mode.xpath;
      rule = ruleStr;
    } else {
      rule = ruleStr;
    }
    rule = _splitPutRule(rule, putMap);
    var start = 0;
    final matches = _evalPattern.allMatches(rule).toList();
    if (matches.isNotEmpty) {
      final first = matches.first;
      final pre = rule.substring(0, first.start);
      if (mode != Mode.js && mode != Mode.regex && (first.start == 0 || !pre.contains('##'))) {
        mode = Mode.regex;
      }
      for (final m in matches) {
        if (m.start > start) _splitRegex(rule.substring(start, m.start));
        final tmp = m.group(0)!;
        if (tmp.toLowerCase().startsWith('@get:')) {
          _ruleType.add(_getRuleType);
          _ruleParam.add(tmp.substring(6, tmp.length - 1));
        } else if (tmp.startsWith('{{')) {
          _ruleType.add(_jsRuleType);
          _ruleParam.add(tmp.substring(2, tmp.length - 2));
        } else {
          _splitRegex(tmp);
        }
        start = m.end;
      }
      if (matches.last.end < rule.length) _splitRegex(rule.substring(matches.last.end));
    } else {
      _splitRegex(rule);
    }
  }

  static String _splitPutRule(String ruleStr, Map<String, String> putMap) {
    var v = ruleStr;
    for (final m in _putPattern.allMatches(ruleStr)) {
      v = v.replaceFirst(m.group(0)!, '');
      try {
        final d = jsonDecode(m.group(1)!);
        if (d is Map) {
          d.forEach((k, val) => putMap['$k'] = '$val');
        }
      } catch (_) {
        // malformed @put: ignored like Legado does
      }
    }
    return v;
  }

  /// Splits [ruleStr] around `$1`..`$99` group references (only in the part before `##`).
  void _splitRegex(String ruleStr) {
    var start = 0;
    final head = ruleStr.split('##')[0];
    final matches = _regexPattern.allMatches(head).toList();
    if (matches.isNotEmpty) {
      if (mode != Mode.js && mode != Mode.regex) mode = Mode.regex;
      for (final m in matches) {
        if (m.start > start) {
          _ruleType.add(_defaultRuleType);
          _ruleParam.add(ruleStr.substring(start, m.start));
        }
        final tmp = m.group(0)!;
        _ruleType.add(int.parse(tmp.substring(1)));
        _ruleParam.add(tmp);
        start = m.end;
      }
      if (matches.last.end < ruleStr.length) {
        _ruleType.add(_defaultRuleType);
        _ruleParam.add(ruleStr.substring(matches.last.end));
      }
    } else {
      _ruleType.add(_defaultRuleType);
      _ruleParam.add(ruleStr);
    }
  }

  static bool _isRule(String r) => r.startsWith('@') || r.startsWith(r'$.') || r.startsWith(r'$[') || r.startsWith('//');

  /// Substitutes `$n` (regex groups of [result]), `@get:{}` and `{{ }}` into the rule and separates `##regex##replacement###`.
  Future<void> makeUpRule(Object? result) async {
    final infoVal = StringBuffer();
    if (_ruleParam.isNotEmpty) {
      final parts = <String>[];
      for (var index = 0; index < _ruleParam.length; index++) {
        final regType = _ruleType[index];
        if (regType > _defaultRuleType) {
          if (result is List) {
            if (result.length > regType) {
              final it = result[regType];
              if (it != null) parts.add('$it');
            }
          } else {
            parts.add(_ruleParam[index]);
          }
        } else if (regType == _jsRuleType) {
          if (_isRule(_ruleParam[index])) {
            final sr = SourceRule(_a, _ruleParam[index], Mode.default_);
            parts.add(await _a.getString([sr]));
          } else {
            final jsEval = await _a.evalJS(_ruleParam[index], result);
            if (jsEval == null) {
              // Kotlin: nothing is appended
            } else if (jsEval is String) {
              parts.add(jsEval);
            } else if (jsEval is double && jsEval % 1.0 == 0.0) {
              parts.add(jsEval.toInt().toString());
            } else {
              parts.add(jsToRuleString(jsEval));
            }
          }
        } else if (regType == _getRuleType) {
          parts.add(_a.get(_ruleParam[index]));
        } else {
          parts.add(_ruleParam[index]);
        }
      }
      for (final p in parts) {
        infoVal.write(p);
      }
      rule = infoVal.toString();
    }
    final ruleStrS = rule.split('##');
    rule = ruleStrS[0].trim();
    replaceRegex = ruleStrS.length > 1 ? ruleStrS[1] : '';
    replacement = ruleStrS.length > 2 ? ruleStrS[2] : '';
    replaceFirst = ruleStrS.length > 3;
  }
}
