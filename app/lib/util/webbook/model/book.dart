// util/webbook/model/book.dart - the engine's book classes: `BaseBook` (what rules read and write: `book.name`, `@put/@get` variables),
// `Book`, `ReadConfig`. `models/book.dart` (`Book`, 32 slots) is the persisted/UI copy; [Book.toModel]/[Book.fromModel] convert.
import 'dart:convert';

import '../../../models/book.dart' as m;
import '../../json.dart';
import '../../legado/js_bindable.dart';
import '../analyze_rule/rule_data.dart';

class ReadConfig {
  bool reverseToc;
  bool useReplaceRule;
  String? imageStyle;

  ReadConfig({this.reverseToc = false, this.useReplaceRule = false, this.imageStyle});

  factory ReadConfig.fromJson(Map<String, dynamic> j) => ReadConfig(
        reverseToc: jsonutil.asBool(j['reverseToc']),
        useReplaceRule: jsonutil.asBool(j['useReplaceRule']),
        imageStyle: jsonutil.optString(j['imageStyle']),
      );

  Map<String, dynamic> toJson() => {'reverseToc': reverseToc, 'useReplaceRule': useReplaceRule, 'imageStyle': imageStyle};
}

abstract class BaseBook extends JsBindable implements RuleDataInterface {
  String name = '';
  String author = '';
  String? kind;
  String? coverUrl;
  String? intro;
  String? wordCount;
  String? latestChapterTitle;
  String bookUrl = '';
  String origin = '';
  String originName = '';
  int type = 0;

  /// JSON of the variable map (what `@put` and `book.putVariable` write); persisted with the book.
  String? variable;
  Map<String, String>? _variableMap;

  @override
  Map<String, String> get variableMap {
    final cached = _variableMap;
    if (cached != null) return cached;
    final d = jsonutil.tryDecode(variable);
    final map = <String, String>{};
    if (d is Map) {
      d.forEach((k, v) => map['$k'] = '$v');
    }
    return _variableMap = map;
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

  /// Resets the cached map after [variable] was assigned from storage.
  void reloadVariable() => _variableMap = null;

  String? get infoHtml => null;

  @override
  Iterable<String> get jsMethods => const ['getVariable', 'putVariable', 'getCustomVariable', 'putCustomVariable', 'toString'];

  @override
  Object? jsGet(String name) {
    switch (name) {
      case 'name':
        return this.name;
      case 'author':
        return author;
      case 'kind':
        return kind;
      case 'coverUrl':
        return coverUrl;
      case 'intro':
        return intro;
      case 'wordCount':
        return wordCount;
      case 'latestChapterTitle':
        return latestChapterTitle;
      case 'bookUrl':
        return bookUrl;
      case 'origin':
        return origin;
      case 'originName':
        return originName;
      case 'type':
        return type;
      case 'variable':
        return variable;
    }
    return JsBindable.noMember;
  }

  @override
  void jsSet(String name, Object? value) {
    final v = value?.toString();
    switch (name) {
      case 'name':
        this.name = v ?? '';
        break;
      case 'author':
        author = v ?? '';
        break;
      case 'kind':
        kind = v;
        break;
      case 'coverUrl':
        coverUrl = v;
        break;
      case 'intro':
        intro = v;
        break;
      case 'wordCount':
        wordCount = v;
        break;
      case 'latestChapterTitle':
        latestChapterTitle = v;
        break;
      case 'bookUrl':
        bookUrl = v ?? '';
        break;
    }
  }

  @override
  Map<String, Object?> jsSnapshot() => {
        'name': name,
        'author': author,
        'kind': kind,
        'coverUrl': coverUrl,
        'intro': intro,
        'wordCount': wordCount,
        'latestChapterTitle': latestChapterTitle,
        'bookUrl': bookUrl,
        'origin': origin,
        'originName': originName,
        'type': type,
        'variable': variable,
      };

  @override
  Object? jsCall(String name, List<Object?> args) {
    switch (name) {
      case 'getVariable':
        return getVariable('${args.isNotEmpty ? args[0] : ''}');
      case 'putVariable':
        return putVariable('${args.isNotEmpty ? args[0] : ''}', args.length > 1 && args[1] != null ? '${args[1]}' : null);
      case 'getCustomVariable':
        return getVariable('custom');
      case 'putCustomVariable':
        return putVariable('custom', args.isNotEmpty && args[0] != null ? '${args[0]}' : null);
      case 'toString':
        return jsonEncode(jsSnapshot());
    }
    return super.jsCall(name, args);
  }
}

class Book extends BaseBook {
  static final RegExp _authorRegex = RegExp(r'^\s*作\s*者[:：\s]+|\s+作\s*者\s*$');
  static final RegExp _nameRegex = RegExp(r'\s+作\s*者.*|\s+\S+\s+著');

  String tocUrl = '';
  String customTag = '';
  String customCoverUrl = '';
  String customIntro = '';
  String? charset;
  int group = 0;
  int latestChapterTime = 0;
  int lastCheckTime = 0;
  int lastCheckCount = 0;
  int totalChapterNum = 0;
  String? durChapterTitle;
  int durChapterIndex = 0;
  int durChapterPos = 0;
  int durChapterTime = 0;
  bool canUpdate = true;
  int order = 0;
  int originOrder = 0;
  int syncTime = 0;
  ReadConfig? readConfig;
  String downloadUrls = '';
  bool imageDecode = false;
  bool reverseCatalog = false;
  bool isqread = false;
  String bid = '';

  /// Raw pages kept between the search/info/toc steps so that a detail page is fetched once.
  String? _infoHtml;
  String? tocHtml;

  Book({String bookUrl = '', String name = '', String author = '', String origin = '', String originName = '', int type = 0, String? variable}) {
    this.bookUrl = bookUrl;
    this.name = name;
    this.author = author;
    this.origin = origin;
    this.originName = originName;
    this.type = type;
    this.variable = variable;
  }

  @override
  String? get infoHtml => _infoHtml;
  set infoHtml(String? v) => _infoHtml = v;

  String getDisplayName() => name;
  String getRealAuthor() => author.replaceAll(_authorRegex, '').trim();

  static String formatBookName(String name) => name.replaceAll(_nameRegex, '').trim();
  static String formatBookAuthor(String author) => author.replaceAll(_authorRegex, '').trim();

  bool get isReverseToc => readConfig?.reverseToc ?? reverseCatalog;

  /// The persisted/UI model (`lib/models/book.dart`).
  m.Book toModel() => m.Book(
        bookUrl: bookUrl,
        name: name,
        author: author,
        kind: kind ?? '',
        coverUrl: customCoverUrl.isNotEmpty ? customCoverUrl : (coverUrl ?? ''),
        intro: customIntro.isNotEmpty ? customIntro : (intro ?? ''),
        tocUrl: tocUrl,
        wordCount: wordCount ?? '',
        bookgroup: '$group',
        type_: type,
        isqread: isqread,
        charset: charset ?? '',
        latestChapterTitle: latestChapterTitle ?? '',
        latestChapterTime: latestChapterTime,
        totalChapterNum: totalChapterNum,
        lastCheckTime: lastCheckTime,
        durChapterTime: durChapterTime,
        durChapterTitle: durChapterTitle ?? '',
        durChapterIndex: durChapterIndex,
        durChapterPos: durChapterPos.toDouble(),
        useReplaceRule: readConfig?.useReplaceRule ?? false,
        origin: origin,
        imageDecode: imageDecode,
        downloadUrls: downloadUrls,
        bid: bid,
        reverseCatalog: reverseCatalog,
      );

  static Book fromModel(m.Book b) {
    final r = Book(bookUrl: b.bookUrl, name: b.name, author: b.author, origin: b.origin, type: b.type_);
    r.kind = b.kind.isEmpty ? null : b.kind;
    r.coverUrl = b.coverUrl.isEmpty ? null : b.coverUrl;
    r.intro = b.intro.isEmpty ? null : b.intro;
    r.tocUrl = b.tocUrl;
    r.wordCount = b.wordCount.isEmpty ? null : b.wordCount;
    r.group = int.tryParse(b.bookgroup) ?? 0;
    r.isqread = b.isqread;
    r.charset = b.charset.isEmpty ? null : b.charset;
    r.latestChapterTitle = b.latestChapterTitle.isEmpty ? null : b.latestChapterTitle;
    r.latestChapterTime = b.latestChapterTime;
    r.totalChapterNum = b.totalChapterNum;
    r.lastCheckTime = b.lastCheckTime;
    r.durChapterTime = b.durChapterTime;
    r.durChapterTitle = b.durChapterTitle.isEmpty ? null : b.durChapterTitle;
    r.durChapterIndex = b.durChapterIndex;
    r.durChapterPos = b.durChapterPos.toInt();
    r.imageDecode = b.imageDecode;
    r.downloadUrls = b.downloadUrls;
    r.bid = b.bid;
    r.reverseCatalog = b.reverseCatalog;
    r.readConfig = ReadConfig(useReplaceRule: b.useReplaceRule, reverseToc: b.reverseCatalog);
    return r;
  }

  @override
  Object? jsGet(String name) {
    switch (name) {
      case 'tocUrl':
        return tocUrl;
      case 'charset':
        return charset;
      case 'durChapterTitle':
        return durChapterTitle;
      case 'totalChapterNum':
        return totalChapterNum;
      case 'durChapterIndex':
        return durChapterIndex;
      case 'downloadUrls':
        return downloadUrls;
    }
    return super.jsGet(name);
  }

  @override
  Map<String, Object?> jsSnapshot() => {
        ...super.jsSnapshot(),
        'tocUrl': tocUrl,
        'charset': charset,
        'durChapterTitle': durChapterTitle,
        'totalChapterNum': totalChapterNum,
        'durChapterIndex': durChapterIndex,
        'downloadUrls': downloadUrls,
      };

  @override
  bool operator ==(Object other) => other is Book && other.bookUrl == bookUrl;

  @override
  int get hashCode => bookUrl.hashCode;

  @override
  String toString() => '$name/$author';
}
