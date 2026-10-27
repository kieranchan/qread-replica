// pages/book/shelf_routes.dart — entry points of the shelf area for the lead's wiring (lib/main.dart, main_page.dart):
//
//   await ShelfRoutes.init();                         // after Storage / AppDirs / ReadStorageRoot are set up
//   Nav.openBook   = (c, b) => ShelfRoutes.push(c, 'book_detail_page', b);
//   Nav.openSearch = (c, {key}) => ShelfRoutes.push(c, 'search_book_page', key);
//   Nav.openNamed  = (c, name, {arguments}) => ShelfRoutes.handles(name) ? ShelfRoutes.push(c, name, arguments) : <other areas>;
//
// Route names are the original file stems.
import 'package:flutter/material.dart';

import '../../data/bookself.dart';
import '../../models/book.dart';
import '../../read/api/readapi.dart';
import '../bookshelf_page.dart';
import '../discovery_page.dart';
import '../discovery_page_new.dart';
import '../exploration/edit/exploration_edit_page.dart';
import '../exploration/exploration_page.dart';
import '../history/history_page.dart';
import '../search/backbook_page.dart';
import '../search/search_book_page.dart';
import 'book_catalog_page.dart';
import 'book_change_yuan.dart';
import 'book_detail_page.dart';
import 'book_edit_page.dart';
import 'book_notes_page.dart';
import 'download_manager_page.dart';

abstract class ShelfRoutes {
  /// Route name → page. Arguments: a [Book] for the book pages, a search key (String) for `search_book_page`.
  static final Map<String, Widget Function(Object? arguments)> pages = {
    'bookshelf_page': (_) => const BookshelfPage(),
    'discovery_page': (_) => const DiscoveryPage(),
    'discovery_page_new': (_) => const DiscoveryPageNew(),
    'exploration_page': (_) => const ExplorationPage(),
    'exploration_edit_page': (_) => const ExplorationEditPage(),
    'history_page': (_) => const HistoryPage(),
    'download_manager_page': (_) => const DownloadManagerPage(),
    'backbook_page': (_) => const BackbookPage(),
    'search_book_page': (a) => SearchBookPage(searchKey: a is String ? a : ''),
    'book_detail_page': (a) => BookDetailPage(book: a as Book),
    'book_catalog_page': (a) => BookCatalogPage(book: a as Book),
    'book_edit_page': (a) => BookEditPage(book: a as Book),
    'book_change_yuan': (a) => BookChangeYuan(book: a as Book),
    'book_notes_page': (a) => BookNotesPage(book: a as Book),
  };

  static bool handles(String name) => pages.containsKey(name);

  static Future<void> push(BuildContext context, String name, Object? arguments) async {
    final b = pages[name];
    if (b == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => b(arguments), settings: RouteSettings(name: name)));
  }

  /// Start-up hook: loads the shelf and makes the reader's progress land on the shelf entry (`ReadApi.onProgress`; the reading
  /// core calls it after every progress save).
  static Future<void> init() async {
    await BookSelfN.load();
    ReadApi.onProgress = (book) async {
      if (!BookSelfN.contains(book.bookUrl)) return;
      await BookSelfN.updateProgress(book.bookUrl,
          index: book.durChapterIndex, pos: book.durChapterPos, title: book.durChapterTitle, readchapter: book.readchapter);
    };
  }
}
