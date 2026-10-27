// util/webbook/model/rule.dart - the five rule groups of a book source. Field names are the JSON keys (toJson order of the original,
// rule_engine.txt section 0). `callBackJs`, `subContent`, `payAction`, `imageStyle`, `imageDecode`, `isVip`/`isPay`, `downloadUrls`
// are app extensions over upstream Legado.
import '../../json.dart';

abstract class BookListRule {
  String? get bookList;
  String? get name;
  String? get author;
  String? get intro;
  String? get kind;
  String? get lastChapter;
  String? get updateTime;
  String? get bookUrl;
  String? get coverUrl;
  String? get wordCount;
}

String? _s(Object? v) {
  final t = jsonutil.optString(v);
  return t;
}

class SearchRule implements BookListRule {
  String? checkKeyWord;
  @override
  String? bookList, name, author, intro, kind, lastChapter, updateTime, bookUrl, coverUrl, wordCount;

  SearchRule({this.checkKeyWord, this.bookList, this.name, this.author, this.intro, this.kind, this.lastChapter, this.updateTime, this.bookUrl, this.coverUrl, this.wordCount});

  factory SearchRule.fromJson(Map<String, dynamic> j) => SearchRule(
        checkKeyWord: _s(j['checkKeyWord']),
        bookList: _s(j['bookList']),
        name: _s(j['name']),
        author: _s(j['author']),
        intro: _s(j['intro']),
        kind: _s(j['kind']),
        lastChapter: _s(j['lastChapter']),
        updateTime: _s(j['updateTime']),
        bookUrl: _s(j['bookUrl']),
        coverUrl: _s(j['coverUrl']),
        wordCount: _s(j['wordCount']),
      );

  Map<String, dynamic> toJson() => {
        'checkKeyWord': checkKeyWord,
        'bookList': bookList,
        'name': name,
        'author': author,
        'intro': intro,
        'kind': kind,
        'lastChapter': lastChapter,
        'updateTime': updateTime,
        'bookUrl': bookUrl,
        'coverUrl': coverUrl,
        'wordCount': wordCount,
      };
}

class ExploreRule implements BookListRule {
  @override
  String? bookList, name, author, intro, kind, lastChapter, updateTime, bookUrl, coverUrl, wordCount;

  ExploreRule({this.bookList, this.name, this.author, this.intro, this.kind, this.lastChapter, this.updateTime, this.bookUrl, this.coverUrl, this.wordCount});

  factory ExploreRule.fromJson(Map<String, dynamic> j) => ExploreRule(
        bookList: _s(j['bookList']),
        name: _s(j['name']),
        author: _s(j['author']),
        intro: _s(j['intro']),
        kind: _s(j['kind']),
        lastChapter: _s(j['lastChapter']),
        updateTime: _s(j['updateTime']),
        bookUrl: _s(j['bookUrl']),
        coverUrl: _s(j['coverUrl']),
        wordCount: _s(j['wordCount']),
      );

  Map<String, dynamic> toJson() => {
        'bookList': bookList,
        'name': name,
        'author': author,
        'intro': intro,
        'kind': kind,
        'lastChapter': lastChapter,
        'updateTime': updateTime,
        'bookUrl': bookUrl,
        'coverUrl': coverUrl,
        'wordCount': wordCount,
      };
}

class BookInfoRule {
  String? init, name, author, intro, kind, lastChapter, updateTime, coverUrl, tocUrl, wordCount, canReName, downloadUrls;

  BookInfoRule({this.init, this.name, this.author, this.intro, this.kind, this.lastChapter, this.updateTime, this.coverUrl, this.tocUrl, this.wordCount, this.canReName, this.downloadUrls});

  factory BookInfoRule.fromJson(Map<String, dynamic> j) => BookInfoRule(
        init: _s(j['init']),
        name: _s(j['name']),
        author: _s(j['author']),
        intro: _s(j['intro']),
        kind: _s(j['kind']),
        lastChapter: _s(j['lastChapter']),
        updateTime: _s(j['updateTime']),
        coverUrl: _s(j['coverUrl']),
        tocUrl: _s(j['tocUrl']),
        wordCount: _s(j['wordCount']),
        canReName: _s(j['canReName']),
        downloadUrls: _s(j['downloadUrls']),
      );

  Map<String, dynamic> toJson() => {
        'init': init,
        'name': name,
        'author': author,
        'intro': intro,
        'kind': kind,
        'lastChapter': lastChapter,
        'updateTime': updateTime,
        'coverUrl': coverUrl,
        'tocUrl': tocUrl,
        'wordCount': wordCount,
        'canReName': canReName,
        'downloadUrls': downloadUrls,
      };
}

class TocRule {
  String? preUpdateJs, chapterList, chapterName, chapterUrl, formatJs, isVolume, isVip, isPay, updateTime, nextTocUrl;

  TocRule({this.preUpdateJs, this.chapterList, this.chapterName, this.chapterUrl, this.formatJs, this.isVolume, this.isVip, this.isPay, this.updateTime, this.nextTocUrl});

  factory TocRule.fromJson(Map<String, dynamic> j) => TocRule(
        preUpdateJs: _s(j['preUpdateJs']),
        chapterList: _s(j['chapterList']),
        chapterName: _s(j['chapterName']),
        chapterUrl: _s(j['chapterUrl']),
        formatJs: _s(j['formatJs']),
        isVolume: _s(j['isVolume']),
        isVip: _s(j['isVip']),
        isPay: _s(j['isPay']),
        updateTime: _s(j['updateTime']),
        nextTocUrl: _s(j['nextTocUrl']),
      );

  Map<String, dynamic> toJson() => {
        'preUpdateJs': preUpdateJs,
        'chapterList': chapterList,
        'chapterName': chapterName,
        'chapterUrl': chapterUrl,
        'formatJs': formatJs,
        'isVolume': isVolume,
        'isVip': isVip,
        'isPay': isPay,
        'updateTime': updateTime,
        'nextTocUrl': nextTocUrl,
      };
}

class ContentRule {
  String? callBackJs, subContent, content, title, nextContentUrl, webJs, sourceRegex, replaceRegex, imageStyle, imageDecode, payAction;

  ContentRule({this.callBackJs, this.subContent, this.content, this.title, this.nextContentUrl, this.webJs, this.sourceRegex, this.replaceRegex, this.imageStyle, this.imageDecode, this.payAction});

  factory ContentRule.fromJson(Map<String, dynamic> j) => ContentRule(
        callBackJs: _s(j['callBackJs']),
        subContent: _s(j['subContent']),
        content: _s(j['content']),
        title: _s(j['title']),
        nextContentUrl: _s(j['nextContentUrl']),
        webJs: _s(j['webJs']),
        sourceRegex: _s(j['sourceRegex']),
        replaceRegex: _s(j['replaceRegex']),
        imageStyle: _s(j['imageStyle']),
        imageDecode: _s(j['imageDecode']),
        payAction: _s(j['payAction']),
      );

  Map<String, dynamic> toJson() => {
        'callBackJs': callBackJs,
        'subContent': subContent,
        'content': content,
        'title': title,
        'nextContentUrl': nextContentUrl,
        'webJs': webJs,
        'sourceRegex': sourceRegex,
        'replaceRegex': replaceRegex,
        'imageStyle': imageStyle,
        'imageDecode': imageDecode,
        'payAction': payAction,
      };
}
