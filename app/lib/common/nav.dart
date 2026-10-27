// common/nav.dart — cross-area navigation hooks (lead-owned).
//
// The page areas are ported in parallel (shelf/discovery, reader UI, sources/RSS, extras), so a page never imports another area's page
// file directly. It calls one of these hooks instead; `lib/main.dart` points them at the real pages once all areas are merged. Until a
// hook is wired it shows a short "not available yet" message, so every area compiles and tests on its own.
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/bookchapter.dart';
import '../models/source.dart';
import '../models/rsssource.dart';
import '../util/toast.dart';

/// Opens the reader for [book]. [chapterIndex] overrides the saved progress; [chapters] skips loading the table of contents.
typedef OpenReader = Future<void> Function(BuildContext context, Book book, {int? chapterIndex, List<BookChapter>? chapters});

/// Opens the book detail page for a book found by search / discovery / exploration.
typedef OpenBook = Future<void> Function(BuildContext context, Book book);

/// Opens the search page, optionally pre-filled with [key].
typedef OpenSearch = Future<void> Function(BuildContext context, {String? key});

/// Opens the editor of a book source (null = new source).
typedef OpenSourceEdit = Future<void> Function(BuildContext context, Source? source);

/// Opens an RSS source (its article list).
typedef OpenRss = Future<void> Function(BuildContext context, RssSource source);

/// Opens a page by its area-local route name with optional arguments (settings sub pages, TTS, themes, ...).
typedef OpenNamed = Future<void> Function(BuildContext context, String name, {Object? arguments});

abstract class Nav {
  static Future<void> _missing(String what) async => Toast.show('$what 尚未接入');

  static OpenReader openReader = (context, book, {chapterIndex, chapters}) => _missing('阅读器');
  static OpenBook openBook = (context, book) => _missing('书籍详情');
  static OpenSearch openSearch = (context, {key}) => _missing('搜索');
  static OpenSourceEdit openSourceEdit = (context, source) => _missing('书源编辑');
  static OpenRss openRss = (context, source) => _missing('订阅');

  /// Fallback for everything else; route names are listed in docs/PORTING.md ("Navigation hooks").
  static OpenNamed openNamed = (context, name, {arguments}) => _missing(name);
}
