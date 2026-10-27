// pages/read/pages/novel/views/reader_host.dart — what the reader's menus may ask the open reader to do. In the original the menus
// (`TopMenu`, `ButtomMenu`, `ReadMoreSettingPage`, ...) receive dozens of callbacks from `_NovelViewState`; this port bundles them in one
// interface that `_NovelViewState` implements.
import 'package:flutter/widgets.dart';

import '../../../../../models/book.dart';
import '../../../../../models/bookchapter.dart';
import '../../../../../read/api/readapi.dart';
import '../../../../../read/setting/read_setting.dart';

abstract class ReaderHost {
  Book get book;
  ReadApi get api;
  ReadSetting get setting;
  List<BookChapter> get chapters;
  int get chapterIndex;

  /// 0..1 through the current chapter / the whole book.
  double get chapterProgress;
  double get bookProgress;

  String get chapterTitle;

  /// Log lines of this reading session ("显示日志").
  List<String> get logs;

  /// Opens chapter [index] at [offset] (chapter-text character), else at [progress] (0..1), or at its last page.
  Future<void> jumpToChapter(int index, {double progress = 0, int? offset, bool last = false});
  Future<bool> turnPage(int delta);
  Future<void> nextChapter();
  Future<void> prevChapter();

  /// Re-paginates after a layout setting changed (font size, spacing, columns, margins ...).
  Future<void> relayout();

  /// Reloads the current chapter from its source (`refresh`) and re-applies the replace rules.
  Future<void> reloadChapter({bool refresh = false});

  void closeMenus();
  void openCatalog();
  void openSearch([String keyword = '']);
  void startListen();
  void startAutoTurn();
  Future<void> toggleNight();

  bool get isBookmarked;
  Future<void> toggleBookmark();

  BuildContext get context;
}
