// pages/read/pages/novel_view.dart — the novel reader (`NovelView` / `_NovelViewState`, 329 functions / 145 KB in the original).
//
// What it does, following the original's flow (0x10c532c init: "开始初始化 ReadApi" -> "获取章节目录" -> "开始加载初始章节" with the saved
// "上次阅读章节" / "上次阅读进度"; 0xeae13c paging: "=== 开始计算分页 ===", "根据进度得到页码", "上一章的最后一页" / "下一章的第一页"):
//   * loads the table of contents (given, from the local importer, or from the book-source engine) and the reading settings;
//   * loads the start chapter through `ReadApi.loadChapter` (cache, replace rules, AI purification), lays it out with
//     `CalculateChapter` and shows the page that holds `Book.durChapterPos`;
//   * turns pages with the selected animation (`turn`), tap zones (`turntype`), drags, volume / arrow keys, auto turn;
//   * saves the progress after every page turn (`ReadApi.saveProgress`) and preloads the neighbouring chapters (`preloadAt`);
//   * re-paginates when a layout setting or the window size changes and keeps the reading position (character offset);
//   * menus: top bar (TopMenu), bottom bar + setting panels (ButtomMenu), catalog / bookmarks / notes drawer, in-book search,
//     read aloud (ReadAloudController + ReaderSpeaker), notes / highlights from a long-press selection, pull-down bookmark,
//     pull-up exit, day / night switch.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/highlight.dart';
import '../../../data/note_data_n.dart';
import '../../../data/replace.dart';
import '../../../models/book.dart';
import '../../../models/bookchapter.dart';
import '../../../models/note.dart';
import '../../../read/api/calculate/calculate_hapter.dart';
import '../../../read/api/readapi.dart';
import '../../../read/model/mypage.dart';
import '../../../read/model/page.dart';
import '../../../read/pdf/pdf_file.dart';
import '../../../qread/qread_jobs.dart';
import '../../../read/setting/read_layout_style.dart';
import '../../../read/setting/read_setting.dart';
import '../../../read/util/chapter_content.dart';
import '../../../read/util/content_painter.dart';
import '../../../read/util/highlight_apply.dart';
import '../../../read/util/list_content.dart';
import '../../../read/util/listcontroller.dart';
import '../../../read/util/read.dart';
import '../../../util/epub/epub_zh_convert.dart';
import '../../../util/image/image_service.dart';
import '../../../util/source/image_meta.dart';
import '../../../util/source/source_events.dart';
import '../../../util/toast.dart';
import '../../../widget/delayed_selection_area.dart';
import '../../../widget/note_sheet.dart';
import '../../replace/replace_rule_edit.dart';
import '../read_aloud.dart';
import '../reader_speaker.dart';
import 'novel/apple_book.dart';
import 'novel/content.dart';
import 'novel/list.dart';
import 'novel/page.dart';
import 'novel/search_book.dart';
import 'novel/views/ai_chat_sheet.dart';
import 'novel/views/auto_turn.dart';
import 'novel/views/bottom_menu.dart';
import 'novel/views/catalog_view.dart';
import 'novel/views/listen_bar.dart';
import 'novel/views/reader_host.dart';
import 'novel/views/top_menu.dart';
import 'novel/views/turn.dart';

/// Loads the table of contents of a book (local importer or book-source engine).
typedef ChapterListLoader = Future<List<BookChapter>> Function(Book book);

class NovelView extends StatefulWidget {
  final Book book;
  final int? chapterIndex;
  final List<BookChapter>? chapters;
  final ChapterLoader? loader;
  final ChapterListLoader? chapterListLoader;

  const NovelView({super.key, required this.book, this.chapterIndex, this.chapters, this.loader, this.chapterListLoader});

  @override
  State<NovelView> createState() => NovelViewState();
}

class _Sel {
  final int chapterIndex;
  final int start;
  final int end;
  final Offset at;
  const _Sel(this.chapterIndex, this.start, this.end, this.at);
}

class NovelViewState extends State<NovelView> with WidgetsBindingObserver implements ReaderHost {
  final ReadSetting _setting = ReadSetting();
  late ReadApi _api;
  List<BookChapter> _chapters = [];

  final Map<int, ReadChapter> _content = {};
  final Map<int, List<PageText>> _pages = {};
  final Map<int, Future<void>> _loading = {};
  final Map<int, List<BookNote>> _notes = {};
  final List<String> _log = [];

  int _ci = 0;
  int _pi = 0;
  double? _pendingProgress;
  int? _pendingOffset;

  ReadLayoutStyle? _style;
  late int _simplified = _setting.simplified;
  (bool, double)? _brightness;
  int _wakelock = 0;
  Size? _size;
  EdgeInsets _safe = EdgeInsets.zero;
  int _gen = 0;

  String? _status = '目录加载中...';
  String? _error;
  bool _inited = false;

  bool _menu = false;
  bool _autoTurn = false;
  Timer? _autoTimer;
  double _pull = 0;
  _Sel? _sel;
  ({int ci, int start, int end})? _hit;

  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();
  final NovelPagerController _pager = NovelPagerController();
  final ReadListController _list = ReadListController();
  final FocusNode _focus = FocusNode(debugLabel: 'novel');
  ReadAloudController? _aloud;

  // ------------------------------------------------------------------ ReaderHost

  @override
  Book get book => widget.book;
  @override
  ReadApi get api => _api;
  @override
  ReadSetting get setting => _setting;
  @override
  List<BookChapter> get chapters => _chapters;
  @override
  int get chapterIndex => _ci;
  @override
  List<String> get logs => _log;

  @override
  String get chapterTitle => _content[_ci]?.title ?? (_ci < _chapters.length ? _chapters[_ci].name : '');

  @override
  double get chapterProgress {
    final pages = _pages[_ci];
    final rc = _content[_ci];
    if (pages == null || rc == null) return 0;
    return CalculateChapter.progressForPage(pages, _pi, rc.content.length);
  }

  @override
  double get bookProgress => _chapters.isEmpty ? 0 : ((_ci + chapterProgress) / _chapters.length).clamp(0.0, 1.0);

  /// Current page index inside the chapter (tests).
  int get pageIndex => _pi;
  int get pageCount => _pages[_ci]?.length ?? 0;
  bool get menuVisible => _menu;
  ReadAloudController? get aloud => _aloud;
  ReadLayoutStyle? get layoutStyle => _style;

  void _aiError(String m) => Toast.show(m);

  void _logLine(String s) {
    _log.add('${clockText()} $s');
    if (_log.length > 300) _log.removeAt(0);
  }

  // ------------------------------------------------------------------ lifecycle

  @override
  void initState() {
    super.initState();
    // tapped images with `js` run it in this book's 时光源 page
    ParagraphComments.activeSource = () => widget.book.origin;
    WidgetsBinding.instance.addObserver(this);
    _setting.addListener(_onSetting);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ReadApi.log == _logLine) ReadApi.log = null;
    if (ReadApi.aiError == _aiError) ReadApi.aiError = null;
    if (ReadApi.refreshCurrent == _refreshFromSource) ReadApi.refreshCurrent = null;
    if (QreadHooks.currentBook == widget.book) QreadHooks.currentBook = null;
    if (QreadHooks.refreshToc == _refreshToc) QreadHooks.refreshToc = null;
    if (QreadHooks.refreshContent == _refreshFromSource) QreadHooks.refreshContent = null;
    _setting.removeListener(_onSetting);
    _autoTimer?.cancel();
    ReaderWakelock.stop();
    if (_brightness != null) ReaderBrightness.restore();
    _aloud?.dispose();
    _list.dispose();
    _focus.dispose();
    _setting.dispose();
    _restoreSystemUi();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _inited) {
      _logLine('进入后台');
      _saveProgress();
    } else if (state == AppLifecycleState.resumed && _inited) {
      // 0x2b48ac: back in the foreground the idle clock restarts.
      ReaderWakelock.touch();
      ReaderWakelock.start(_setting.wakelockTimeout);
    }
  }

  Future<void> _init() async {
    _logLine('开始初始化 ReadApi');
    try {
      await Future.wait<Object?>([
        ReplaceData.load(),
        HighlightData.load(),
        NoteDataN.load(),
      ]);
    } catch (e) {
      _logLine('加载规则失败: $e');
    }
    try {
      _logLine('获取章节目录');
      var list = widget.chapters;
      if (list == null || list.isEmpty) {
        final l = widget.chapterListLoader;
        list = l == null ? <BookChapter>[] : await l(widget.book);
      }
      _chapters = List<BookChapter>.of(list);
      _logLine('获取到 ${_chapters.length} 个章节');
    } catch (e) {
      _fail('目录加载出错：$e');
      return;
    }
    if (_chapters.isEmpty) {
      _fail('章节列表为空');
      return;
    }
    _api = ReadApi(widget.book, chapters: _chapters, loader: widget.loader, replaceRules: ReplaceData.rules);
    ReadApi.log ??= _logLine;
    ReadApi.aiError = _aiError;
    ReadApi.refreshCurrent = _refreshFromSource;
    // the bound 轻阅读 backend's refreshBookToc / refreshContent jobs act on this book (0x10c54ac sets the statics)
    QreadHooks.currentBook = widget.book;
    QreadHooks.refreshToc = _refreshToc;
    QreadHooks.refreshContent = _refreshFromSource;
    final b = widget.book;
    var start = widget.chapterIndex ?? b.durChapterIndex;
    var progress = widget.chapterIndex == null || widget.chapterIndex == b.durChapterIndex ? b.durChapterPos : 0.0;
    _logLine('上次阅读章节：${b.durChapterIndex}');
    _logLine('上次阅读进度：${b.durChapterPos}');
    if (start < 0 || start >= _chapters.length) {
      Toast.show('当前章节超出目录总章节，请前往目录重新选择章节');
      start = start < 0 ? 0 : _chapters.length - 1;
      progress = 0;
    }
    _ci = start;
    _pendingProgress = progress;
    _inited = true;
    _wakelock = _setting.wakelockTimeout;
    ReaderWakelock.start(_wakelock);
    _applyBrightness();
    _status = '正文加载中...';
    if (mounted) setState(() {});
    _applySystemUi();
    _logLine('开始加载初始章节');
    if (_size != null) await relayout();
  }

  void _fail(String message) {
    _logLine(message);
    if (!mounted) return;
    setState(() {
      _error = message;
      _status = null;
    });
  }

  void _onSetting() {
    if (!mounted) return;
    _applyBrightness();
    if (_inited && _setting.wakelockTimeout != _wakelock) {
      _wakelock = _setting.wakelockTimeout;
      ReaderWakelock.start(_wakelock);
    }
    if (_setting.simplified != _simplified) {
      _simplified = _setting.simplified;
      if (_inited) {
        reloadChapter();
        return;
      }
    }
    final size = _size;
    if (size == null || !_inited) {
      setState(() {});
      return;
    }
    final style = _setting.layoutStyle(size, _safe);
    if (_style == null || style.signature != _style!.signature) {
      relayout();
    } else {
      setState(() {});
    }
  }

  void _applySystemUi() {
    try {
      if (_menu || (!_setting.hidetop && !_setting.hidebottom)) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [
          if (!_setting.hidetop) SystemUiOverlay.top,
          if (!_setting.hidebottom) SystemUiOverlay.bottom,
        ]);
      }
    } catch (_) {}
  }

  void _restoreSystemUi() {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ chapters and pages

  /// 简体繁体 (0x24d448): `simplified1` 1 = to simplified, 2 = to traditional; chapters over 100000 characters stay as they are.
  ChapterContent _convert(ChapterContent c) {
    final mode = _setting.simplified;
    if (mode == FanMode.off || EpubZhConvert.converter == null) return c;
    if (c.text.length > FanMode.maxLength) {
      Toast.show('正本内容过长，暂不支持简繁转换');
      return c;
    }
    final toT = mode == FanMode.toTraditional;
    if (c.isPlainText) return ChapterContent.fromText(EpubZhConvert.convert(c.text, toTraditional: toT));
    for (final b in c.blocks) {
      if (b.isImage) continue;
      for (final r in b.runs) {
        if (!r.isImage) r.str = EpubZhConvert.convert(r.str, toTraditional: toT);
      }
    }
    return ChapterContent.fromBlocks(c.blocks);
  }

  ChapterContent _paragraphComments(ChapterContent c) => paragraphComments(c, needdp: _setting.needdp);

  /// 显示段评 (`needdp`) off: the `dp:` bubbles of book-source text are left out, the inline ones at the ends of paragraphs as well as
  /// those on a line of their own. The text and its offsets do not change (bubbles take no characters).
  @visibleForTesting
  static ChapterContent paragraphComments(ChapterContent c, {required bool needdp}) {
    if (needdp || c.isPlainText) return c;
    return c.withoutImages((r) => r.href.startsWith('dp:'));
  }

  Future<ReadChapter> _ensureContent(int i, {bool refresh = false}) async {
    final have = _content[i];
    if (have != null && !refresh) return have;
    _logLine('正文获取 $i');
    final rc = await _api.loadChapter(i, refresh: refresh);
    final out = ReadChapter(rc.chapter, rc.title, _convert(_paragraphComments(rc.content)), purified: rc.purified);
    _content[i] = out;
    return out;
  }

  Future<void> _ensurePages(int i, {bool refresh = false}) {
    if (i < 0 || i >= _chapters.length) return Future<void>.value();
    if (_pages.containsKey(i) && !refresh) return Future<void>.value();
    final running = _loading[i];
    if (running != null && !refresh) return running;
    final gen = _gen;
    final f = () async {
      try {
        final rc = await _ensureContent(i, refresh: refresh);
        final style = _style;
        final size = _size;
        if (style == null || size == null || gen != _gen) return;
        final calc = CalculateChapter(style: style, imageSizeOf: (src) => imageSize(src, style: style));
        final pages = await calc.calculate(
          size: size,
          blocks: rc.content.blocks,
          title: _setting.hidetitle ? '' : rc.title,
          isVolume: rc.chapter.isVolume,
        );
        if (gen != _gen) return;
        _pages[i] = pages;
        _logLine('分页完成，总页数：${pages.length}');
        unawaited(_loadNotes(i));
      } finally {
        _loading.remove(i);
      }
    }();
    _loading[i] = f;
    return f;
  }

  /// Layout size of an image block. A 段评 bubble (`dp:N`) on a line of its own takes one line: the original sizes it
  /// `fontSize x lineHeight` high (0xebf770, the `dp` branch of the image-size pass) and draws it like an inline bubble (0xffedf4: the
  /// "我的" box, picture `min(fontSize * 1.2, height - 1)` high), so it gets the inline image box ([ReadTextBuilder.inlineImageSize]).
  @visibleForTesting
  static Future<Size?> imageSize(String src, {ReadLayoutStyle style = const ReadLayoutStyle()}) async {
    if (src.startsWith(PdfFile.scheme)) return PdfFile.sizeOf(src);
    if (src.startsWith('dp:')) return ReadTextBuilder.inlineImageSize(style);
    if (src.startsWith('http') || src.startsWith('data:')) return null;
    try {
      final m = await ImageService.readSizes([src]);
      return m[src];
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadNotes(int i) async {
    try {
      final list = await NoteDataN.notesOfChapter(widget.book.bookUrl, i);
      _notes[i] = list;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// `preloadAt`: lays out the neighbours of the current chapter in the background.
  void _preload() {
    for (final i in [_ci + 1, _ci - 1]) {
      if (i < 0 || i >= _chapters.length || _pages.containsKey(i)) continue;
      _ensurePages(i).then((_) {
        if (!mounted) return;
        if (_setting.turn == TurnMode.scroll) _syncList();
        setState(() {});
      }).catchError((Object e) {
        _logLine('预加载失败 $i: $e');
      });
    }
    // Keep memory bounded: only the window around the current chapter stays laid out.
    _pages.removeWhere((k, _) => (k - _ci).abs() > 2);
    _content.removeWhere((k, _) => (k - _ci).abs() > 3);
  }

  int get _step => (_style?.columns ?? 1) == 2 ? 2 : 1;

  int _alignPage(int pi) => _step == 2 ? pi - pi % 2 : pi;

  /// Lays the current chapter out again and returns to the remembered character offset.
  @override
  Future<void> relayout() async {
    final size = _size;
    if (size == null || !_inited) return;
    final keep = _pendingOffset ?? (_pages[_ci] != null && _pages[_ci]!.isNotEmpty ? CalculateChapter.offsetForPage(_pages[_ci]!, _pi) : null);
    _pendingOffset = keep;
    _gen++;
    _style = _setting.layoutStyle(size, _safe);
    _pages.clear();
    _loading.clear();
    _logLine('=== 开始计算分页 === 当前章节索引：$_ci，当前页码：$_pi');
    final sw = Stopwatch()..start();
    if (mounted) setState(() => _status = _content.containsKey(_ci) ? '分页中' : '正文加载中...');
    try {
      await _ensurePages(_ci);
    } catch (e) {
      _fail('正文获取失败: $e');
      return;
    }
    final pages = _pages[_ci];
    if (pages == null || !mounted) return;
    final rc = _content[_ci]!;
    if (_pendingOffset != null) {
      _pi = CalculateChapter.pageIndexForOffset(pages, _pendingOffset!);
    } else if (_pendingProgress != null) {
      _pi = CalculateChapter.pageIndexForProgress(pages, _pendingProgress!, rc.content.length);
      _logLine('根据进度得到页码:$_pi');
    }
    _pi = _alignPage(_pi.clamp(0, pages.length - 1));
    _pendingOffset = null;
    _pendingProgress = null;
    _logLine('=== 分页计算完成 ===，总耗时：${sw.elapsedMilliseconds} 毫秒');
    setState(() {
      _status = null;
      _error = null;
    });
    if (_setting.turn == TurnMode.scroll) _resetList();
    _preload();
  }

  /// `refreshContent` of a 时光源 page: reload the current chapter from the source.
  Future<void> _refreshFromSource() => reloadChapter(refresh: true);

  /// 0x10c6328: the table of contents again (the backend changed it).
  Future<void> _refreshToc() async {
    final l = widget.chapterListLoader;
    if (l == null) return;
    try {
      final list = await l(widget.book);
      if (list.isEmpty || !mounted) return;
      setState(() => _chapters = List<BookChapter>.of(list));
      _api.chapters = _chapters;
    } catch (e) {
      _logLine('目录刷新失败: $e');
    }
  }

  @override
  Future<void> reloadChapter({bool refresh = false}) async {
    _api.replaceRules = ReplaceData.rules;
    _content.remove(_ci);
    _pendingOffset = _pages[_ci] == null ? null : CalculateChapter.offsetForPage(_pages[_ci]!, _pi);
    if (refresh) {
      try {
        await _ensureContent(_ci, refresh: true);
      } catch (e) {
        Toast.show('正文获取失败');
        return;
      }
    }
    _content.removeWhere((k, _) => k != _ci);
    await relayout();
  }

  // ------------------------------------------------------------------ position

  (int, int)? _neighbor(int d) {
    final pages = _pages[_ci];
    if (pages == null) return null;
    if (d > 0) {
      if (_pi + _step < pages.length) return (_ci, _pi + _step);
      final np = _pages[_ci + 1];
      if (_ci + 1 < _chapters.length && np != null) return (_ci + 1, 0);
      return null;
    }
    if (_pi > 0) return (_ci, _alignPage(math.max(0, _pi - _step)));
    final pp = _pages[_ci - 1];
    if (_ci > 0 && pp != null) return (_ci - 1, _alignPage(pp.length - 1));
    return null;
  }

  bool _canTurn(int d) => _neighbor(d) != null;

  void _blocked(int d) {
    final pages = _pages[_ci];
    if (pages == null) {
      Toast.show('内容正在加载中请稍后');
      return;
    }
    if (d > 0 && _ci + 1 >= _chapters.length && _pi + _step >= pages.length) {
      Toast.show('阅读结束');
      _stopAutoTurn();
      return;
    }
    if (d < 0 && _ci == 0 && _pi == 0) {
      Toast.show('已经到头了');
      return;
    }
    Toast.show('内容正在加载中请稍后');
    _ensurePages(_ci + d).then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      _logLine('正文获取失败 $e');
    });
  }

  void _turned(int d) {
    ReaderWakelock.touch();
    final n = _neighbor(d);
    if (n == null) return;
    final chapterChanged = n.$1 != _ci;
    setState(() {
      _ci = n.$1;
      _pi = n.$2;
      _sel = null;
    });
    if (chapterChanged) _logLine(d > 0 ? '下一章的第一页' : '上一章的最后一页');
    _saveProgress();
    if (chapterChanged) _preload();
  }

  Future<void> _saveProgress() async {
    if (!_inited || _pages[_ci] == null) return;
    try {
      await _api.saveProgress(chapterIndex: _ci, pos: chapterProgress, chapterTitle: chapterTitle);
      // a listening 时光源 gets `saveRead` with every saved progress (0xe078d4)
      SourceEvents.fire(SourceEvents.saveRead, _api.book);
    } catch (e) {
      _logLine('不能保存 $e');
    }
  }

  @override
  Future<bool> turnPage(int delta) async {
    if (_setting.turn == TurnMode.scroll) {
      await _list.page(delta, duration: Duration(milliseconds: _setting.pageTurnSpeed));
      return true;
    }
    if (!_canTurn(delta)) {
      _blocked(delta);
      return false;
    }
    return _pager.turn(delta);
  }

  @override
  Future<void> jumpToChapter(int index, {double progress = 0, int? offset, bool last = false}) async {
    if (index < 0 || index >= _chapters.length) {
      Toast.show('当前章节超出目录总章节，请前往目录重新选择章节');
      return;
    }
    setState(() {
      _status = '正文加载中...';
      _sel = null;
    });
    try {
      await _ensurePages(index);
    } catch (e) {
      _fail('正文获取失败: $e');
      return;
    }
    final pages = _pages[index];
    if (pages == null || !mounted) return;
    final rc = _content[index]!;
    _ci = index;
    if (last) {
      _pi = pages.length - 1;
    } else if (offset != null) {
      _pi = CalculateChapter.pageIndexForOffset(pages, offset);
    } else {
      _pi = CalculateChapter.pageIndexForProgress(pages, progress, rc.content.length);
    }
    _pi = _alignPage(_pi.clamp(0, pages.length - 1));
    setState(() {
      _status = null;
      _error = null;
    });
    if (_setting.turn == TurnMode.scroll) _resetList();
    await _saveProgress();
    _preload();
  }

  @override
  Future<void> nextChapter() => _ci + 1 < _chapters.length ? jumpToChapter(_ci + 1) : Future<void>.sync(() => Toast.show('阅读结束'));

  @override
  Future<void> prevChapter() => _ci > 0 ? jumpToChapter(_ci - 1) : Future<void>.sync(() => Toast.show('已经到头了'));

  // ------------------------------------------------------------------ scroll mode

  void _resetList() {
    final pages = _pages[_ci];
    if (pages == null) return;
    _list.reset(_ci, chapterTitle, pages, pageIndex: _pi);
    _syncList();
  }

  void _syncList() {
    if (_list.isEmpty) return;
    final next = _list.lastChapter + 1;
    final np = _pages[next];
    if (np != null) _list.append(next, _content[next]?.title ?? '', np);
    final prev = _list.firstChapter - 1;
    final pp = _pages[prev];
    if (pp != null && _list.topIndex < 3) _list.prepend(prev, _content[prev]?.title ?? '', pp);
  }

  void _onListTop(ListContent top) {
    if (top.chapterIndex == _ci && top.pageIndex == _pi) return;
    final changed = top.chapterIndex != _ci;
    _ci = top.chapterIndex;
    _pi = top.pageIndex;
    _saveProgress();
    if (changed) {
      _preload();
      setState(() {});
    }
  }

  void _onListEdge(int dir) {
    final target = dir > 0 ? _list.lastChapter + 1 : _list.firstChapter - 1;
    if (target < 0 || target >= _chapters.length) return;
    _ensurePages(target).then((_) {
      if (!mounted) return;
      final pages = _pages[target];
      if (pages == null) return;
      if (dir > 0) {
        _list.append(target, _content[target]?.title ?? '', pages);
      } else {
        _list.prepend(target, _content[target]?.title ?? '', pages);
      }
    }).catchError((Object e) {
      _logLine('正文获取失败 $e');
    });
  }

  // ------------------------------------------------------------------ taps, keys, pulls

  void _onTap(Offset pos, Size size) {
    ReaderWakelock.touch();
    if (_sel != null) {
      setState(() => _sel = null);
      return;
    }
    if (_autoTurn) {
      _stopAutoTurn();
      return;
    }
    if (_menu) {
      closeMenus();
      return;
    }
    final a = _setting.clickArea.hit(pos, size);
    switch (a) {
      case ClickAreaType.menu:
        _openMenus();
      case ClickAreaType.nextPage:
        turnPage(1);
      case ClickAreaType.previousPage:
        turnPage(-1);
      case ClickAreaType.none:
        break;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.audioVolumeDown || k == LogicalKeyboardKey.audioVolumeUp) {
      if (!_setting.volumeButton || _menu) return KeyEventResult.ignored;
      turnPage(k == LogicalKeyboardKey.audioVolumeDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.space) {
      turnPage(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp) {
      turnPage(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape && _menu) {
      closeMenus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static const double _pullLimit = 90;

  void _onPullUpdate(double dy) {
    if (!_setting.downmark && !_setting.exit) return;
    setState(() => _pull = dy);
  }

  Future<void> _onPull(double dy) async {
    setState(() => _pull = 0);
    if (dy > _pullLimit && _setting.downmark) {
      await toggleBookmark();
    } else if (dy < -_pullLimit && _setting.exit) {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  String? get _pullHint {
    if (_pull > 10 && _setting.downmark) {
      final del = isBookmarked;
      if (_pull > _pullLimit) return del ? '松手删除书签' : '松手添加书签';
      return del ? '继续下滑删除书签' : '继续下滑添加书签';
    }
    if (_pull < -10 && _setting.exit) return _pull < -_pullLimit ? '松手退出阅读' : '继续上滑退出阅读';
    return null;
  }

  // ------------------------------------------------------------------ menus

  void _openMenus() {
    setState(() => _menu = true);
    _applySystemUi();
  }

  @override
  void closeMenus() {
    if (!_menu) return;
    setState(() => _menu = false);
    _applySystemUi();
    _focus.requestFocus();
  }

  @override
  void openCatalog() {
    closeMenus();
    _scaffold.currentState?.openDrawer();
  }

  @override
  Future<void> openSearch([String keyword = '']) async {
    closeMenus();
    final hit = await Navigator.of(context).push<SearchHit>(
      MaterialPageRoute(builder: (_) => SearchBookPage(host: this, initialKeyword: keyword)),
    );
    if (hit == null || !mounted) return;
    _hit = (ci: hit.chapterIndex, start: hit.start, end: hit.end);
    await jumpToChapter(hit.chapterIndex, offset: hit.start);
  }

  @override
  Future<void> toggleNight() async {
    final n = !_setting.night;
    await _setting.setNight(n);
    Toast.show(n ? '已切换到夜间模式' : '已切换到白天模式');
  }

  // ------------------------------------------------------------------ bookmarks

  BookNote? get _currentBookmark {
    final pages = _pages[_ci];
    if (pages == null || pages.isEmpty) return null;
    final p = pages[_pi.clamp(0, pages.length - 1)];
    for (final n in NoteDataN.notes) {
      if (n.bookUrl != widget.book.bookUrl || !NoteDataN.isBookmark(n) || n.chapterIndex != _ci) continue;
      if (n.startStableId >= p.start && n.startStableId < math.max(p.end, p.start + 1)) return n;
    }
    return null;
  }

  @override
  bool get isBookmarked => _currentBookmark != null;

  @override
  Future<void> toggleBookmark() async {
    try {
      final have = _currentBookmark;
      if (have != null) {
        await NoteDataN.delete(have.id);
        Toast.show('已删除书签');
      } else {
        final pages = _pages[_ci];
        if (pages == null) {
          Toast.show('正在加载中，请稍后再试！');
          return;
        }
        final p = pages[_pi];
        final text = _content[_ci]?.content.text ?? '';
        final snippet = text.substring(p.start.clamp(0, text.length), math.min(text.length, p.start + 60)).trim();
        await NoteDataN.add(
          BookNote(
            bookUrl: widget.book.bookUrl,
            bookName: widget.book.name,
            chapterIndex: _ci,
            chapterName: chapterTitle,
            startStableId: p.start,
            endStableId: p.end,
            selectedText: snippet,
          ),
          bookmark: true,
        );
        Toast.show('已添加书签');
      }
      if (mounted) setState(() {});
    } catch (e) {
      Toast.show('书签操作失败:$e');
    }
  }

  // ------------------------------------------------------------------ selection, notes

  void _onLongPress(int ci, int offset, Offset global) {
    final text = _content[ci]?.content.text ?? '';
    if (text.isEmpty) return;
    const stops = '。！？；!?;…\n';
    var s = offset;
    while (s > 0 && !stops.contains(text[s - 1])) {
      s--;
    }
    var e = offset;
    while (e < text.length && !stops.contains(text[e])) {
      e++;
    }
    if (e < text.length && text[e] != '\n') e++;
    while (s < e && text[s].trim().isEmpty) {
      s++;
    }
    if (e <= s) return;
    HapticFeedback.selectionClick();
    setState(() => _sel = _Sel(ci, s, e, global));
  }

  String get _selText {
    final s = _sel;
    if (s == null) return '';
    final text = _content[s.chapterIndex]?.content.text ?? '';
    return text.substring(s.start.clamp(0, text.length), s.end.clamp(0, text.length));
  }

  Future<void> _onSelectionAction(SelectionAction a) async {
    final s = _sel;
    if (s == null) return;
    final text = _selText;
    switch (a) {
      case SelectionAction.copy:
        await Clipboard.setData(ClipboardData(text: text));
        Toast.show('已复制');
        setState(() => _sel = null);
      case SelectionAction.readFromHere:
        setState(() => _sel = null);
        await _startListenAt(s.chapterIndex, s.start);
      case SelectionAction.selectParagraph:
        final all = _content[s.chapterIndex]?.content.text ?? '';
        var ps = s.start;
        while (ps > 0 && all[ps - 1] != '\n') {
          ps--;
        }
        var pe = s.end;
        while (pe < all.length && all[pe] != '\n') {
          pe++;
        }
        setState(() => _sel = _Sel(s.chapterIndex, ps, pe, s.at));
      case SelectionAction.dictionary:
        setState(() => _sel = null);
        await DelayedSelectionAreaState.showDictionary(context, text);
      case SelectionAction.search:
        setState(() => _sel = null);
        await openSearch(text);
      case SelectionAction.replace:
        setState(() => _sel = null);
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => ReplaceRuleEdit(initialPattern: text, scope: widget.book.name)),
        );
        if (saved == true) await reloadChapter();
      case SelectionAction.note:
        setState(() => _sel = null);
        await _addNote(s, text);
    }
  }

  Future<void> _addNote(_Sel s, String text) async {
    final r = await showNoteCreateSheet(context, quote: text);
    if (r == null) return;
    await NoteDataN.add(BookNote(
      bookUrl: widget.book.bookUrl,
      bookName: widget.book.name,
      chapterIndex: s.chapterIndex,
      chapterName: _content[s.chapterIndex]?.title ?? '',
      startStableId: s.start,
      endStableId: s.end,
      selectedText: text,
      noteContent: r.content,
      color: r.color,
    ));
    await _loadNotes(s.chapterIndex);
  }

  List<TextDeco> _decorate(Content c, int ci) {
    final out = <TextDeco>[];
    final night = _setting.config().isDark;
    final rules = HighlightData.enabled;
    if (rules.isNotEmpty) out.addAll(HighlightApply.ruleDecos(HighlightApply.flatText(c), rules, night: night));
    for (final n in _notes[ci] ?? const <BookNote>[]) {
      final r = HighlightApply.flatRange(c, n.startStableId, n.endStableId);
      if (r == null) continue;
      final color = HighlightApply.parseColor(n.color) ?? const Color(0xFFFFC107);
      out.add(TextDeco(r.start, r.end,
          background: color.withValues(alpha: 0.3), decoration: TextDecoration.underline, decorationColor: color));
    }
    final h = _hit;
    if (h != null && h.ci == ci) {
      final r = HighlightApply.flatRange(c, h.start, h.end);
      if (r != null) out.add(TextDeco(r.start, r.end, background: const Color(0x88FFEB3B)));
    }
    final a = _aloud;
    final seg = a?.current;
    if (a != null && seg != null && a.chapterIndex == ci && seg.start >= 0) {
      final r = HighlightApply.flatRange(c, seg.start, seg.end);
      if (r != null) {
        final color = _setting.config().speakColor;
        out.add(_setting.readHighlightType == 0
            ? TextDeco(r.start, r.end, decoration: TextDecoration.underline, decorationColor: color)
            : TextDeco(r.start, r.end, color: color, background: color.withValues(alpha: 0.18)));
      }
    }
    final sel = _sel;
    if (sel != null && sel.chapterIndex == ci) {
      final r = HighlightApply.flatRange(c, sel.start, sel.end);
      if (r != null) out.add(TextDeco(r.start, r.end, background: const Color(0x663D8BFF)));
    }
    return out;
  }

  // ------------------------------------------------------------------ read aloud

  @override
  void startListen() {
    closeMenus();
    final pages = _pages[_ci];
    _startListenAt(_ci, pages == null ? 0 : CalculateChapter.offsetForPage(pages, _pi));
  }

  Future<void> _startListenAt(int ci, int offset) async {
    var a = _aloud;
    if (a == null) {
      a = ReadAloudController(
        speaker: ReaderSpeaker.create(bookUrl: widget.book.bookUrl),
        chapterAt: (i) async {
          if (i < 0 || i >= _chapters.length) return null;
          try {
            return await _ensureContent(i);
          } catch (_) {
            return null;
          }
        },
        chapterCount: () => _chapters.length,
      );
      a.bookName = widget.book.name;
      a.coverUrl = widget.book.coverUrl;
      a.onSegment = _followAloud;
      a.onStopped = () {
        if (mounted) setState(() {});
      };
      a.addListener(() {
        if (mounted) setState(() {});
      });
      _aloud = a;
    }
    await a.start(ci, fromOffset: offset);
  }

  void _followAloud(int ci, AloudSegment seg) {
    if (!mounted) return;
    if (ci != _ci) {
      jumpToChapter(ci, offset: math.max(0, seg.start));
      return;
    }
    final pages = _pages[ci];
    if (pages == null || seg.start < 0) return;
    final target = _alignPage(CalculateChapter.pageIndexForOffset(pages, seg.start));
    if (target != _pi) {
      setState(() => _pi = target);
      if (_setting.turn == TurnMode.scroll) _list.jumpTo(ci, target);
      _saveProgress();
    }
  }

  // ------------------------------------------------------------------ auto turn

  @override
  void startAutoTurn() {
    closeMenus();
    _autoTimer?.cancel();
    setState(() => _autoTurn = true);
    if (_setting.turn == TurnMode.scroll) {
      _autoTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!_list.scroll.hasClients) return;
        final pos = _list.scroll.position;
        final next = pos.pixels + _setting.fan / 5;
        if (next >= pos.maxScrollExtent) {
          _onListEdge(1);
        }
        _list.scroll.jumpTo(math.min(next, pos.maxScrollExtent));
      });
    } else {
      _autoTimer = Timer.periodic(Duration(seconds: _setting.turntime), (_) async {
        if (!await turnPage(1)) _stopAutoTurn();
      });
    }
  }

  void _stopAutoTurn() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (mounted && _autoTurn) setState(() => _autoTurn = false);
  }

  // ------------------------------------------------------------------ build

  MyPage? _myPage(int ci, int pi) {
    final pages = _pages[ci];
    if (pages == null) return null;
    final rc = _content[ci];
    return MyPage.fromPages(
      pages: pages,
      index: pi,
      chapterIndex: ci,
      chapterName: rc?.title ?? _chapters[ci].name,
      columns: _style?.columns ?? 1,
      isVolume: _chapters[ci].isVolume,
      progress: rc == null ? 0 : CalculateChapter.progressForPage(pages, pi, rc.content.length),
    );
  }

  Widget _screen(int delta, ReadConfig config) {
    var pos = (_ci, _pi);
    if (delta != 0) {
      final n = _neighbor(delta);
      if (n == null) return Container(decoration: config.decoration);
      pos = n;
    }
    final page = _myPage(pos.$1, pos.$2);
    if (page == null || _style == null) return Container(decoration: config.decoration);
    final cp = pos.$1 == _ci ? CalculateChapter.progressForPage(_pages[_ci]!, pos.$2, _content[_ci]?.content.length) : 0.0;
    return ContentPage(
      key: ValueKey('page_${pos.$1}_${pos.$2}'),
      page: page,
      style: _style!,
      setting: _setting,
      config: config,
      safe: _safe,
      bookProgress: _chapters.isEmpty ? 0 : (pos.$1 + cp) / _chapters.length,
      decorate: _decorate,
      onLongPress: delta == 0 ? _onLongPress : null,
      bookName: widget.book.name,
      showStatus: false,
    );
  }

  /// Header and footer of the current page, drawn once over the pager: they stay put while the pages turn.
  Widget _statusBars(ReadConfig config) {
    final page = _myPage(_ci, _pi);
    if (page == null) return const SizedBox();
    return IgnorePointer(
      child: Stack(
        children: ContentPage.statusBars(
          page: page,
          setting: _setting,
          config: config,
          safe: _safe,
          bookProgress: bookProgress,
          bookName: widget.book.name,
        ),
      ),
    );
  }

  Widget _reader(ReadConfig config) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, style: TextStyle(color: config.textColor), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(spacing: 12, children: [
              OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('返回')),
              if (_inited) OutlinedButton(onPressed: openCatalog, child: const Text('目录')),
              if (_inited) OutlinedButton(onPressed: () => reloadChapter(refresh: true), child: const Text('刷新')),
            ]),
          ]),
        ),
      );
    }
    if (_status != null || _pages[_ci] == null || _style == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _inited ? _openMenus : null,
        child: Center(child: Text(_status ?? '内容加载中...', style: TextStyle(color: config.textColor))),
      );
    }
    if (_setting.turn == TurnMode.scroll) {
      return ListPage(
        controller: _list,
        setting: _setting,
        style: _style!,
        config: config,
        safe: _safe,
        chapterTitle: chapterTitle,
        bookName: widget.book.name,
        pageNum: _pi + 1,
        totalPage: pageCount,
        bookProgress: bookProgress,
        decorate: _decorate,
        onLongPress: _onLongPress,
        onTap: _onTap,
        onTopChanged: _onListTop,
        onEdge: _onListEdge,
      );
    }
    if (_setting.turn == TurnMode.appleBook && AppleBookPager.supported && !(_setting.needcss2 && _isEpub)) {
      // 仿真翻页(IOS原生): the UIKit page view; the header / footer stay a Flutter overlay as in the other paged modes. An EPUB in
      // 完整 css mode falls through to the Flutter curl (the original switches it back with a toast, 0x10c532c)
      return Stack(
        children: [
          Positioned.fill(
            child: AppleBookPager(
              controller: _pager,
              paperColor: config.backgroundColor,
              pageBuilder: (d) => _screen(d, config),
              canTurn: _canTurn,
              onTurned: _turned,
              onBlocked: _blocked,
              onTap: _onTap,
            ),
          ),
          Positioned.fill(child: _statusBars(config)),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: NovelPager(
            mode: _setting.turn,
            duration: Duration(milliseconds: _setting.pageTurnSpeed),
            controller: _pager,
            paperColor: config.backgroundColor,
            pageBuilder: (d) => _screen(d, config),
            canTurn: _canTurn,
            onTurned: _turned,
            onBlocked: _blocked,
            onTap: _onTap,
            onVerticalPull: (_setting.downmark || _setting.exit) ? _onPull : null,
            onVerticalPullUpdate: _onPullUpdate,
          ),
        ),
        Positioned.fill(child: _statusBars(config)),
      ],
    );
  }

  bool get _isEpub => widget.book.bookUrl.toLowerCase().endsWith('.epub');

  void _checkSize(Size size, EdgeInsets safe) {
    if (_size == size && _safe == safe) return;
    final first = _size == null;
    _size = size;
    _safe = safe;
    if (!_inited) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!first) _logLine('窗口变化');
      relayout();
    });
  }

  /// 亮度设置: the screen's brightness itself (screen_brightness), not an overlay.
  Future<void> _applyBrightness() async {
    final key = (_setting.autoBrightness, _setting.brightness);
    if (key == _brightness) return;
    _brightness = key;
    final ok = await ReaderBrightness.apply(auto: _setting.autoBrightness, value: _setting.brightness);
    if (!ok && !_setting.autoBrightness && _setting.brightness >= 0) Toast.show('当前设备不支持亮度调节');
  }

  @override
  Widget build(BuildContext context) {
    final config = _setting.config();
    final sel = _sel;
    final hint = _pullHint;
    return Scaffold(
      key: _scaffold,
      backgroundColor: config.backgroundColor,
      drawer: _inited ? Drawer(child: CatalogView(host: this)) : null,
      drawerEnableOpenDragGesture: false,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, box) {
          _checkSize(box.biggest, MediaQuery.paddingOf(context));
          return Stack(
            children: [
              Positioned.fill(child: Container(decoration: config.decoration)),
              Positioned.fill(child: _reader(config)),
              if (hint != null)
                Positioned(
                  top: _pull > 0 ? _safe.top + 8 : null,
                  bottom: _pull < 0 ? _safe.bottom + 8 : null,
                  left: 0,
                  right: 0,
                  child: Center(child: Text(hint, style: TextStyle(color: config.textColor.withValues(alpha: 0.8)))),
                ),
              if (sel != null)
                Positioned(
                  left: 8,
                  right: 8,
                  top: (sel.at.dy - 64).clamp(_safe.top, box.maxHeight - 56),
                  child: Center(child: ReaderSelectionMenu(onAction: _onSelectionAction)),
                ),
              if (_menu) ...[
                Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: closeMenus)),
                Positioned(top: 0, left: 0, right: 0, child: TopMenu(host: this)),
                Positioned(left: 0, right: 0, bottom: 0, child: ButtomMenu(host: this, onAiChat: _openAiChat)),
              ],
              if (!_menu && _aloud != null && _aloud!.active)
                Positioned(left: 0, right: 0, bottom: 0, child: ListenBar(controller: _aloud!, host: this)),
              if (_autoTurn)
                Positioned(left: 0, right: 0, bottom: 0, child: AutoTurn(setting: _setting, onStop: _stopAutoTurn, onChanged: startAutoTurn)),
            ],
          );
        }),
      ),
    );
  }

  void _openAiChat() {
    closeMenus();
    showAiChatSheet(context, book: widget.book, chapterTitle: chapterTitle, chapterText: _content[_ci]?.content.text ?? '', setting: _setting);
  }
}
