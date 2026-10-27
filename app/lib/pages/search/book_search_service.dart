// pages/search/book_search_service.dart — the shelf pages' only door to the book-source engine.
//
// Every page of the shelf area (bookshelf refresh, detail, catalog, change source, search, discovery, exploration, download
// manager) calls the engine (`api/sourceapi.dart`) through [BookSearchService.instance]. The default is
// `EngineBookSearchService` (engine_book_search_service.dart); tests put a `FakeBookSearchService` there.
import 'dart:async';

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../models/explore.dart';
import '../../models/source.dart';
import 'engine_book_search_service.dart';

abstract class BookSearchService {
  /// The engine used by every shelf page. Tests replace it.
  static BookSearchService instance = EngineBookSearchService();

  /// Searches [key] in [sources] (null = every enabled source). The stream emits **exactly one list per source searched**, in
  /// completion order (an empty list when the source found nothing or failed), then closes; the pages use the number of
  /// events for the 「已搜索 n/m」 progress. Every [Book] carries its source in `origin` (the `bookSourceUrl`).
  /// Cancelling the subscription stops the search.
  Stream<List<Book>> search(String key, {List<Source>? sources});

  /// Explore categories ("发现" entries) of a source, parsed from its `exploreUrl` (Legado `title::url` lines or the JSON
  /// list form with `title`, `url`, `type`, `action`, `chars`, `default` …).
  Future<List<Explore>> exploreKinds(Source source);

  /// One page (1-based) of books of an explore category url. An empty list means "no more pages".
  Future<List<Book>> explore(Source source, String url, int page);

  /// Book info page: fills name/author/kind/cover/intro/wordCount/latest chapter/tocUrl of [book] (a copy is returned; shelf
  /// fields such as group and progress are kept).
  Future<Book> bookInfo(Book book);

  /// Table of contents of [book] in source order (the book's `reverseCatalog` is applied by the pages).
  Future<List<BookChapter>> chapters(Book book);

  /// Text of one chapter (used by the download manager to cache chapters ahead of reading).
  Future<String> content(Book book, BookChapter chapter);

  /// Change-source candidates: the same book (same name, author when known) found in other sources. Same event contract
  /// as [search]: one list per source.
  Stream<List<Book>> changeSourceCandidates(Book book, {List<Source>? sources});
}
