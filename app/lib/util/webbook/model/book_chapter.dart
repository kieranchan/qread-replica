// util/webbook/model/book_chapter.dart - a chapter entry of a table of contents (Legado `BookChapter`); also the `chapter` object of
// rule JavaScript. `models/bookchapter.dart` is the persisted copy ([toModel]).
import 'dart:convert';

import '../../../models/bookchapter.dart' as m;
import '../../json.dart';
import '../../legado/js_bindable.dart';
import '../analyze_rule/rule_data.dart';
import '../util/network_utils.dart';

class BookChapter extends JsBindable implements RuleDataInterface {
  String url;
  String title;
  bool isVolume;
  String baseUrl;
  String bookUrl;
  int index;
  bool isVip;
  bool isPay;
  String? resourceUrl;
  String? tag;
  int start;
  int end;
  String chapterId;
  String? variable;
  Map<String, String>? _vm;

  BookChapter({
    this.url = '',
    this.title = '',
    this.isVolume = false,
    this.baseUrl = '',
    this.bookUrl = '',
    this.index = 0,
    this.isVip = false,
    this.isPay = false,
    this.resourceUrl,
    this.tag,
    this.start = 0,
    this.end = 0,
    this.chapterId = '',
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

  /// Legado `getAbsoluteURL`: resolves [url] against [baseUrl], keeping a trailing `,{options}` part intact.
  String getAbsoluteURL() {
    // volumes whose url was derived from the title point at the page the toc came from
    if (url.startsWith(title) && isVolume) return baseUrl;
    final match = NetworkUtils.paramPattern.firstMatch(url);
    final urlBefore = match == null ? url : url.substring(0, match.start);
    final abs = NetworkUtils.getAbsoluteURL(baseUrl, urlBefore);
    return match == null ? abs : '$abs, ${url.substring(match.end)}';
  }

  String getDisplayTitle() => title;

  m.BookChapter toModel() => m.BookChapter(
        name: title,
        chapterId: chapterId.isNotEmpty ? chapterId : url,
        tag: tag ?? '',
        baseUrl: baseUrl,
        isVolume: isVolume,
        index: index,
        isPay: isPay,
        isVip: isVip,
        start: start,
        end: end,
      );

  /// [bookUrl] is not part of the persisted model; pass it when the chapter's own url is stored in `chapterId`.
  static BookChapter fromModel(m.BookChapter c, {String bookUrl = ''}) => BookChapter(
        url: c.chapterId,
        title: c.name,
        isVolume: c.isVolume,
        baseUrl: c.baseUrl,
        bookUrl: bookUrl,
        index: c.index,
        isVip: c.isVip,
        isPay: c.isPay,
        tag: c.tag.isEmpty ? null : c.tag,
        start: c.start,
        end: c.end,
        chapterId: c.chapterId,
      );

  @override
  Iterable<String> get jsMethods => const ['getVariable', 'putVariable', 'getAbsoluteURL', 'toString'];

  @override
  Object? jsGet(String name) {
    switch (name) {
      case 'title':
        return title;
      case 'url':
        return url;
      case 'index':
        return index;
      case 'isVolume':
        return isVolume;
      case 'isVip':
        return isVip;
      case 'isPay':
        return isPay;
      case 'tag':
        return tag;
      case 'baseUrl':
        return baseUrl;
      case 'bookUrl':
        return bookUrl;
      case 'variable':
        return variable;
    }
    return JsBindable.noMember;
  }

  @override
  void jsSet(String name, Object? value) {
    if (name == 'title') title = '$value';
    if (name == 'url') url = '$value';
  }

  @override
  Map<String, Object?> jsSnapshot() => {
        'title': title,
        'url': url,
        'index': index,
        'isVolume': isVolume,
        'isVip': isVip,
        'isPay': isPay,
        'tag': tag,
        'baseUrl': baseUrl,
        'bookUrl': bookUrl,
        'variable': variable,
      };

  @override
  Object? jsCall(String name, List<Object?> args) {
    switch (name) {
      case 'getVariable':
        return getVariable('${args.isNotEmpty ? args[0] : ''}');
      case 'putVariable':
        return putVariable('${args.isNotEmpty ? args[0] : ''}', args.length > 1 && args[1] != null ? '${args[1]}' : null);
      case 'getAbsoluteURL':
        return getAbsoluteURL();
      case 'toString':
        return title;
    }
    return super.jsCall(name, args);
  }

  @override
  bool operator ==(Object other) => other is BookChapter && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => title;
}
