// read/api/readapi.dart — `ReadApi`: everything the reader needs around one open book, minus drawing.
//
// Original (class 1496, 0x70 bytes: fields `bookContent` 0x28, `bookRules` 0x30, `bookai` 0x38, `bookh` 0x40; statics `_historyLock`,
// `history_tmp`): chapter text with caching and purification, progress saving (`_saveProgress` 0x228548 in an isolate, then the server's
// `autopos` / `addreads`), the history list in the item store (`historybook`), read-chapter marks (`_getBookread` 0x244700, `_savereads`
// 0x244858, `_postreads` 0x244890), directory JSON parsing (`_parseDirectoryListJson` 0x227aac), replace rules and `_decodeHtmlEntities`.
//
// Differences: the chapter source is an injected [ChapterLoader] (local files: `LocalBookImporter`; web books: the book-source engine of the
// engine area), the shelf is updated through [onProgress] (the shelf owner persists it) and the server calls go through
// [ReadProgressRemote]. The original's history cap is not recoverable: [historyLimit] is this port's choice.
import 'dart:async';
import 'dart:convert';

import '../../ai/read.dart';
import '../../models/_json.dart';
import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../models/replacerule.dart';
import '../../storage/setting.dart';
import '../../storage/storage.dart';
import '../util/chapter_content.dart';
import '../util/replace_rules.dart';
import 'book_ai.dart';
import 'book_content.dart';
import 'book_hight.dart';
import 'book_mark.dart';
import 'book_rules.dart';
import 'read_file_store.dart';
import 'read_progress_remote.dart';

/// Loads the raw content of one chapter from its source.
typedef ChapterLoader = Future<ChapterContent> Function(BookChapter chapter);

/// Class 1495 `Progress`: where the reader is (the four values that go into the `Book` fields `durChapter*`).
class Progress {
  final int index;
  final String title;

  /// 0..1 of the chapter text (1/10000 resolution).
  final double pos;
  final int time;

  const Progress({required this.index, required this.title, required this.pos, required this.time});

  Map<String, dynamic> toJson() => {'index': index, 'title': title, 'pos': pos, 'time': time};

  factory Progress.fromJson(Map<String, dynamic> j) =>
      Progress(index: jInt(j['index']), title: jStr(j['title']), pos: jDouble(j['pos']), time: jInt(j['time']));
}

/// A chapter ready for the layout engine.
class ReadChapter {
  final BookChapter chapter;

  /// Chapter title after the title replace rules.
  final String title;
  final ChapterContent content;

  /// Replace rules were applied.
  final bool purified;

  const ReadChapter(this.chapter, this.title, this.content, {this.purified = false});
}

class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() fn) {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return prev.then((_) => fn()).whenComplete(done.complete);
  }
}

/// At most [limit] AI purifications at a time (the purify model's `concurrent`, legacy prefs `purifyConcurrent`).
class _Gate {
  int _running = 0;
  final List<Completer<void>> _waiting = [];

  Future<T> run<T>(int limit, Future<T> Function() fn) async {
    while (_running >= (limit < 1 ? 1 : limit)) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      return await fn();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}

class ReadApi {
  final Book book;
  List<BookChapter> chapters;
  final ChapterLoader? loader;

  /// Replace rules known to the reader (the data layer's list); filtered per book/scope when used.
  List<ReplaceRule> replaceRules;

  late final BookContent bookContent;
  late final BookRules bookRules;
  late final BookAi bookai;
  late final BookHight bookh;
  late final BookMark bookMark;

  ReadApi(
    this.book, {
    List<BookChapter>? chapters,
    this.loader,
    this.replaceRules = const [],
    BookContent? bookContent,
    BookRules? bookRules,
    BookAi? bookai,
    BookHight? bookh,
    BookMark? bookMark,
  }) : chapters = chapters ?? <BookChapter>[] {
    this.bookContent = bookContent ?? const BookContent();
    this.bookRules = bookRules ?? BookRules();
    this.bookai = bookai ?? BookAi();
    this.bookh = bookh ?? BookHight();
    this.bookMark = bookMark ?? const BookMark();
    active = this;
  }

  /// The book most recently opened in the reader (the 时光源 handlers `getReadBook` / `getdurChapterIndex` / `getDirectoryList` /
  /// `putLyric` read it, as the original reads its reader state).
  static ReadApi? active;

  /// Asks the open reader to reload the current chapter (`refreshContent` of a 时光源); the reader UI installs it.
  static Future<void> Function()? refreshCurrent;

  // ------------------------------------------------------------------ statics (wiring)

  /// The shelf owner's hook: persist the book (with the new `durChapter*`) in the bookshelf store.
  static Future<void> Function(Book book)? onProgress;

  /// Server side of the progress (null = never upload). Default: the account server, only when progress sync is on.
  static ReadProgressRemote? remote = ServerReadProgressRemote();

  /// Called with a message for failures that must not interrupt reading (the original prints them with `debugPrint`).
  static void Function(String message)? log;

  /// Ai净化 of a chapter text (0xf089b0 "开始使用ai": the 正文净化 model, `AiRead.purify`); throws `AiException`.
  static Future<String> Function(String text) aiPurifier = (t) => AiRead.purify(t);

  /// How many chapters may be purified at once (the purify model's `concurrent`, default 1).
  static int Function() aiConcurrency = () => Setting.purifyModel?.concurrent ?? Storage.getInt('purifyConcurrent', 1);

  static final _Gate _aiGate = _Gate();

  /// Shown to the user when Ai净化 failed (the reader toasts it).
  static void Function(String message)? aiError;

  static const String historyKey = 'historybook';
  static const int historyLimit = 300;

  static final _AsyncLock _historyLock = _AsyncLock();

  /// Cache of the history list (original `history_tmp`).
  static List<Book>? historyTmp;

  static bool isLocalBook(Book b) => b.origin == localOrigin;

  /// `Book.origin` of local books (0xd97fa4: `loc_book`).
  static const String localOrigin = 'loc_book';

  // ------------------------------------------------------------------ chapter text

  /// Loads chapter [index]: cached raw text first (web books), else the loader; then purification (replace rules; AI result).
  Future<ReadChapter> loadChapter(int index, {bool refresh = false}) async {
    if (index < 0 || index >= chapters.length) {
      throw RangeError('当前章节超出目录总章节');
    }
    final chapter = chapters[index];
    ChapterContent? raw;
    final cacheable = !isLocalBook(book);
    if (cacheable && !refresh) {
      final cached = await bookContent.readFromLocal(book.bookUrl, index);
      if (cached != null) raw = ChapterContent.fromText(cached);
    }
    if (raw == null) {
      final l = loader;
      if (l == null) throw StateError('正文获取失败: 没有章节来源');
      raw = await l(chapter);
      if (cacheable && raw.isPlainText && raw.text.isNotEmpty) {
        await bookContent.saveToLocal(book.bookUrl, index, raw.text, book: book);
      }
    }
    final title = await purifyTitle(chapter.name);
    final content = await purify(index, raw);
    return ReadChapter(chapter, title, content.$1, purified: content.$2);
  }

  /// Title replace rules.
  Future<String> purifyTitle(String title) async {
    if (!book.useReplaceRule) return title;
    final rules = ReplaceRuleEngine.select(replaceRules, book, title: true);
    if (rules.isEmpty) return title;
    return ReplaceRuleEngine.apply(title, rules, onTimeout: _ruleTimeout);
  }

  /// Applies AI result / replace rules to a chapter. Returns the content and whether anything was applied.
  Future<(ChapterContent, bool)> purify(int index, ChapterContent raw) async {
    if (book.useai && raw.isPlainText && raw.text.trim().isNotEmpty) {
      final ai = await bookai.readFromLocal(book.bookUrl, index);
      if (ai != null && ai.text.isNotEmpty && ai.oldtext == raw.text) {
        return (ChapterContent.fromText(ai.text), true);
      }
      // 0xf089b0: no stored result -> ask the purify model, keep {oldtext, text} for the next time
      log?.call('开始使用ai');
      final src = raw.text;
      try {
        final out = await _aiGate.run(aiConcurrency(), () => aiPurifier(src));
        if (out.trim().isNotEmpty) {
          await bookai.saveToLocal(book.bookUrl, index, AiContext(oldtext: src, text: out));
          return (ChapterContent.fromText(out), true);
        }
      } catch (e) {
        // the original reports "正文获取失败:Ai净化出错 <e>" ("请先配置AiTocken" without a model); the chapter is still shown with the
        // replace rules below
        log?.call('$e' == '请先配置AiTocken' ? '请先配置AiTocken' : '正文获取失败:Ai净化出错 $e');
        aiError?.call('$e' == '请先配置AiTocken' ? '请先配置AiTocken' : 'Ai净化出错 $e');
      }
    }
    if (!book.useReplaceRule) return (raw, false);
    final rules = ReplaceRuleEngine.select(replaceRules, book, title: false);
    if (rules.isEmpty) return (raw, false);

    final digest = RuleContext.digestOf(raw.text);
    final signature = RuleContext.rulesSignature(rules);
    if (raw.isPlainText) {
      // Plain text: the result can be cached per chapter and reused while text and rules stay the same.
      final cached = await bookRules.readFromLocal(book.bookUrl, index);
      if (cached != null && cached.md5 == '$digest|$signature') {
        return (ChapterContent.fromText(cached.text), true);
      }
      final src = raw.text;
      final out = await ReadIsolate.run(() => ReplaceRuleEngine.apply(src, rules));
      await bookRules.saveToLocal(book.bookUrl, index, RuleContext(md5: '$digest|$signature', text: out, rules: rules));
      return (ChapterContent.fromText(out), true);
    }
    // Rich content (EPUB / MOBI, source text with images): rules run over the text of each run (inline images stay); offsets are rebuilt.
    for (final b in raw.blocks) {
      if (b.isImage) continue;
      for (final r in b.runs) {
        if (!r.isImage) r.str = ReplaceRuleEngine.apply(r.str, rules, onTimeout: _ruleTimeout);
      }
    }
    return (ChapterContent.fromBlocks(raw.blocks), true);
  }

  void _ruleTimeout(ReplaceRule r) => log?.call('替换净化规则超时已停用: ${r.name}');

  /// `ReadApi._decodeHtmlEntities` (0x2a732c).
  static String decodeHtmlEntities(String s) => ReplaceRuleEngine.decodeHtmlEntities(s);

  // ------------------------------------------------------------------ progress

  /// Remembers the reading position: updates the book (`durChapterIndex/Title/Pos/Time`), the read-chapter set, the history list and
  /// the shelf, then tells the server (fire and forget; failures are logged, not thrown).
  Future<Progress> saveProgress({
    required int chapterIndex,
    required double pos,
    String? chapterTitle,
    bool markRead = true,
    bool upload = true,
  }) async {
    final p = Progress(
      index: chapterIndex,
      title: chapterTitle ?? (chapterIndex >= 0 && chapterIndex < chapters.length ? chapters[chapterIndex].name : book.durChapterTitle),
      pos: roundProgress(pos),
      time: DateTime.now().millisecondsSinceEpoch,
    );
    final changedChapter = book.durChapterIndex != p.index;
    book.durChapterIndex = p.index;
    book.durChapterTitle = p.title;
    book.durChapterPos = p.pos;
    book.durChapterTime = p.time;
    var readsChanged = false;
    if (markRead) {
      final before = book.readchapter;
      book.readchapter = joinRead({...parseRead(before), p.index});
      readsChanged = before != book.readchapter;
    }
    await saveRead(book);
    try {
      await onProgress?.call(book);
    } catch (e) {
      log?.call('书架保存失败: $e');
    }
    final r = remote;
    if (upload && r != null && !isLocalBook(book)) {
      unawaited(r.autoPos(book, p.index, p.pos).catchError((Object e) => log?.call('阅读进度保存错误: $e')));
      if (readsChanged || changedChapter) {
        unawaited(r.addReads(book).catchError((Object e) => log?.call('保存进度到服务器失败:$e')));
      }
    }
    return p;
  }

  /// Progress is kept with 1/10000 resolution (0xeae13c scales by 10000).
  static double roundProgress(double pos) => (pos.clamp(0.0, 1.0) * 10000).round() / 10000;

  // ------------------------------------------------------------------ read marks (`readchapter` = "1,2,5")

  static List<int> parseRead(String s) {
    final set = <int>{};
    for (final part in s.split(RegExp(r'[,，\s]+'))) {
      final v = int.tryParse(part);
      if (v != null && v >= 0) set.add(v);
    }
    return set.toList()..sort();
  }

  static String joinRead(Iterable<int> reads) => (reads.toSet().toList()..sort()).join(',');

  /// `_getBookread` (0x244700): the read chapters of the history entry for `book`. Args: `hostorys` (a list of Book), `book`.
  static Future<List<String>> getBookread(Map<String, dynamic> args) => ReadIsolate.run(() => _getBookreadSync(args));

  static List<String> _getBookreadSync(Map<String, dynamic> args) {
    final hist = (args['hostorys'] as List?)?.cast<Book>() ?? const <Book>[];
    final book = args['book'] as Book;
    for (final h in hist) {
      if (h.bookUrl == book.bookUrl) return h.readchapter.split(',').where((s) => s.isNotEmpty).toList();
    }
    return <String>[];
  }

  /// `_postreads` (0x244890): union of the new reads (`reads`, ints) and the stored ones (`hreads`, strings).
  static Future<Set<int>> postreads(Map<String, dynamic> args) => ReadIsolate.run(() => _postreadsSync(args));

  static Set<int> _postreadsSync(Map<String, dynamic> args) {
    final reads = (args['reads'] as List?)?.cast<int>() ?? const <int>[];
    final hreads = (args['hreads'] as List?)?.cast<String>() ?? const <String>[];
    return {...reads, ...hreads.map(int.tryParse).whereType<int>()};
  }

  /// `_savereads` (0x244858): writes the merged set of read chapters into the matching book(s) of `historys` and returns the list.
  static Future<List<Book>> savereads(Map<String, dynamic> args) => ReadIsolate.run(() => _savereadsSync(args));

  static List<Book> _savereadsSync(Map<String, dynamic> args) {
    final books = (args['historys'] as List?)?.cast<Book>() ?? <Book>[];
    final bookUrl = args['bookUrl'] as String;
    final reads = (args['reads'] as List?)?.cast<int>() ?? const <int>[];
    final hreads = (args['hreads'] as List?)?.cast<String>() ?? const <String>[];
    final merged = joinRead({...reads, ...hreads.map(int.tryParse).whereType<int>()});
    for (final b in books) {
      if (b.bookUrl == bookUrl) b.readchapter = merged;
    }
    return books;
  }

  /// Marks chapters as read (without moving the reading position).
  Future<void> markRead(Iterable<int> indexes) async {
    book.readchapter = joinRead({...parseRead(book.readchapter), ...indexes});
    await saveRead(book);
    await onProgress?.call(book);
  }

  // ------------------------------------------------------------------ history list

  /// The history list (most recent first), from the item store; cached in [historyTmp].
  static Future<List<Book>> getHistory({bool refresh = false}) async {
    final cached = historyTmp;
    if (cached != null && !refresh) return List<Book>.of(cached);
    final text = await ReadItemStore.read(historyKey);
    final list = ReadFileStore.decodeList(text) ?? const [];
    final books = <Book>[
      for (final e in list)
        if (e is Map) Book.fromJson(Map<String, dynamic>.from(e)),
    ];
    historyTmp = books;
    return List<Book>.of(books);
  }

  /// Puts [book] at the top of the history (original `saveRead`, serialised by `_historyLock`).
  static Future<void> saveRead(Book book) => _historyLock.synchronized(() async {
        final list = await getHistory(refresh: historyTmp == null);
        list.removeWhere((b) => b.bookUrl == book.bookUrl);
        list.insert(0, Book.fromJson(book.toJson()));
        if (list.length > historyLimit) list.removeRange(historyLimit, list.length);
        historyTmp = list;
        final json = jsonEncode(list.map((b) => b.toJson()).toList());
        try {
          await ReadItemStore.write(historyKey, json);
        } catch (e) {
          log?.call('历史记录保存失败: $e');
        }
      });

  static Future<void> removeFromHistory(String bookUrl) => _historyLock.synchronized(() async {
        final list = await getHistory(refresh: historyTmp == null);
        list.removeWhere((b) => b.bookUrl == bookUrl);
        historyTmp = list;
        await ReadItemStore.write(historyKey, jsonEncode(list.map((b) => b.toJson()).toList()));
      });

  /// Resets the in-memory history cache (tests, account switch).
  static void resetCaches() => historyTmp = null;

  // ------------------------------------------------------------------ directory JSON

  /// `_parseDirectoryListJson` (0x227aac): the server's chapter list `{"directoryList":[{...BookChapter...}]}` (or a bare list).
  static Future<List<BookChapter>> parseDirectoryListJson(String json) => ReadIsolate.run(() => _parseDirectoryListSync(json));

  static List<BookChapter> _parseDirectoryListSync(String json) {
    try {
      final j = jsonDecode(json);
      final list = j is Map ? j['directoryList'] : j;
      if (list is! List) return <BookChapter>[];
      final out = <BookChapter>[];
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        if (e is! Map) continue;
        final c = BookChapter.fromJson(Map<String, dynamic>.from(e));
        if (!e.containsKey('index')) c.index = i;
        out.add(c);
      }
      return out;
    } catch (e) {
      throw FormatException('解析目录JSON失败：$e');
    }
  }
}
