// pages/read/read_page.dart — the full-screen reader for a book (original `ReadPage` / `_ReadPageState`, build 0x2462a0).
//
// The original picks the view by `Book.type`: 0 -> NovelView, 1 -> AudioView (key `audio_<bookUrl>`), 2 -> ComicView, 4 -> VideoView,
// anything else -> "不支持的阅读类型". Chapter sources: local books (`origin == loc_book`) use `LocalBookImporter`; books from a book
// source use [ReadPage.webLoader] / [ReadPage.webChapters] (default: the book-source engine through [WebBookLoader]); both can be
// overridden by the app.
import 'package:flutter/material.dart';

import '../../data/txtrule.dart';
import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../read/api/readapi.dart';
import '../../read/local_book_importer.dart';
import '../../read/util/reading_time.dart';
import 'pages/audio_view.dart';
import 'pages/comic_view.dart';
import 'pages/novel_view.dart';
import 'pages/video/video_view.dart';
import 'web_book_loader.dart';

/// `Book.type` values (0x2462a0).
abstract class BookType {
  static const int novel = 0;
  static const int audio = 1;
  static const int comic = 2;
  static const int video = 4;
}

class ReadPage extends StatefulWidget {
  final Book book;
  final int? chapterIndex;
  final List<BookChapter>? chapters;
  final ChapterLoader? loader;

  const ReadPage({super.key, required this.book, this.chapterIndex, this.chapters, this.loader});

  /// Chapter text of web books (books from a book source). Default: the book-source engine. Set to null to disable web books
  /// (the reader then shows "未接入书源引擎，无法阅读网络书籍").
  static ChapterLoader? Function(Book book)? webLoader = WebBookLoader.loaderFor;

  /// Table of contents of web books. Default: the book-source engine.
  static Future<List<BookChapter>> Function(Book book)? webChapters = WebBookLoader.chapters;

  /// The loader for [book] (explicit, local importer, or [webLoader]); null when there is none.
  static ChapterLoader? loaderOf(Book book, {ChapterLoader? explicit}) {
    if (explicit != null) return explicit;
    if (ReadApi.isLocalBook(book)) return const LocalBookImporter().loaderFor(book);
    return webLoader?.call(book);
  }

  /// The table-of-contents loader for [book].
  static Future<List<BookChapter>> Function(Book book)? chapterListOf(Book book) {
    if (ReadApi.isLocalBook(book)) {
      return (b) async {
        try {
          await Txtruledata.load();
        } catch (_) {}
        final rules = Txtruledata.enabled;
        return const LocalBookImporter().loadChapters(b, txtRules: rules.isEmpty ? null : rules);
      };
    }
    return webChapters;
  }

  /// Entry point for `Nav.openReader`.
  static Future<void> open(BuildContext context, Book book, {int? chapterIndex, List<BookChapter>? chapters}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReadPage(book: book, chapterIndex: chapterIndex, chapters: chapters)));

  @override
  State<ReadPage> createState() => _ReadPageState();
}

class _ReadPageState extends State<ReadPage> with WidgetsBindingObserver {
  /// 阅读统计: counts while this page is open and the app in the foreground.
  late final ReadingTimer _time = ReadingTimer(widget.book);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _time.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _time.start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _time.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _time.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final loader = ReadPage.loaderOf(book, explicit: widget.loader);
    switch (book.type_) {
      case BookType.novel:
        if (loader == null) return _unsupported('未接入书源引擎，无法阅读网络书籍');
        return NovelView(
          book: book,
          chapterIndex: widget.chapterIndex,
          chapters: widget.chapters,
          loader: loader,
          chapterListLoader: ReadPage.chapterListOf(book),
        );
      case BookType.audio:
        return AudioView(
          key: ValueKey('audio_${book.bookUrl}'),
          book: book,
          loader: loader,
          chapters: widget.chapters,
          chapterIndex: widget.chapterIndex,
          chapterListLoader: ReadPage.chapterListOf(book),
        );
      case BookType.comic:
        if (loader == null) return _unsupported('未接入书源引擎，无法阅读网络书籍');
        return ComicView(
          book: book,
          chapters: widget.chapters,
          chapterIndex: widget.chapterIndex,
          loader: loader,
          chapterListLoader: ReadPage.chapterListOf(book),
        );
      case BookType.video:
        return VideoView(book: book, chapters: widget.chapters, chapterIndex: widget.chapterIndex, chapterListLoader: ReadPage.chapterListOf(book));
      default:
        return _unsupported('不支持的阅读类型');
    }
  }

  Widget _unsupported(String text) => Scaffold(appBar: AppBar(), body: Center(child: Text(text)));
}
