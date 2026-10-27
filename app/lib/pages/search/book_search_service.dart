// pages/search/book_search_service.dart — the shelf pages' only door to the book-source engine.
//
// The engine (`util/webbook/`, `util/legado/`, `api/sourceapi.dart`) is ported by another area. Every page of the shelf area
// (bookshelf refresh, detail, catalog, change source, search, discovery, exploration, download manager) calls the engine
// through [BookSearchService.instance]; the lead points it at the real engine after merging:
//
//   BookSearchService.instance = EngineBookSearchService();   // implements this interface on top of SourceApi
//
// Until then [UnwiredBookSearchService] answers with empty results and a toast, and the tests use
// `FakeBookSearchService` (fake_book_search_service.dart).
import 'dart:async';

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../models/explore.dart';
import '../../models/source.dart';
import '../../util/toast.dart';

abstract class BookSearchService {
  /// The engine used by every shelf page. Replace once at start-up (tests replace it per test).
  static BookSearchService instance = UnwiredBookSearchService();

  /// Searches [key] in [sources] (null = every enabled source). The stream emits **exactly one list per source searched**, in
  /// completion order (an empty list when the source found nothing or failed), then closes; the pages use the number of
  /// events for the 「已搜索 n/m」 progress. Every [Book] carries its source in `origin` (the `bookSourceUrl`).
  /// Cancelling the subscription stops the search.
  Stream<List<Book>> search(String key, {List<Source>? sources});

  /// Explore categories ("发现" entries) of a source, parsed from its `exploreUrl` (Legado `title::url` lines or the JSON
  /// list form with `title`, `url`, `type` (`url`/`button`/`text`/`select`/`toggle`), `action`, `chars`, `default` …).
  Future<List<Explore>> exploreKinds(Source source);

  /// One page (1-based) of books of an explore category url. An empty list means "no more pages".
  Future<List<Book>> explore(Source source, String url, int page);

  /// Book info page: fills name/author/kind/cover/intro/wordCount/latest chapter/tocUrl of [book] (a copy is returned).
  Future<Book> bookInfo(Book book);

  /// Table of contents of [book] (from its `tocUrl`).
  Future<List<BookChapter>> chapters(Book book);

  /// Text of one chapter (used by the download manager to cache chapters ahead of reading).
  Future<String> content(Book book, BookChapter chapter);

  /// Change-source candidates: the same book (same name, author when known) found in other sources. Same event contract
  /// as [search]: one list per source.
  Stream<List<Book>> changeSourceCandidates(Book book, {List<Source>? sources});
}

/// Placeholder until the engine is merged: no results, one toast per call.
class UnwiredBookSearchService implements BookSearchService {
  static const String message = '书源引擎尚未接入';

  void _say() => Toast.show(message);

  @override
  Stream<List<Book>> search(String key, {List<Source>? sources}) {
    _say();
    return const Stream<List<Book>>.empty();
  }

  @override
  Future<List<Explore>> exploreKinds(Source source) async {
    _say();
    return <Explore>[];
  }

  @override
  Future<List<Book>> explore(Source source, String url, int page) async {
    _say();
    return <Book>[];
  }

  @override
  Future<Book> bookInfo(Book book) async {
    _say();
    return Book.fromJson(book.toJson());
  }

  @override
  Future<List<BookChapter>> chapters(Book book) async {
    _say();
    return <BookChapter>[];
  }

  @override
  Future<String> content(Book book, BookChapter chapter) async => throw StateError(message);

  @override
  Stream<List<Book>> changeSourceCandidates(Book book, {List<Source>? sources}) {
    _say();
    return const Stream<List<Book>>.empty();
  }
}
