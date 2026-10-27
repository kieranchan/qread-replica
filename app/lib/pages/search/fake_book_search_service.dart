// pages/search/fake_book_search_service.dart — an in-memory [BookSearchService] for tests and demos (no network).
import 'dart:async';

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../models/explore.dart';
import '../../models/source.dart';
import 'book_search_service.dart';

class FakeBookSearchService implements BookSearchService {
  /// Books each source "has", keyed by `bookSourceUrl`. A book matches a search when its name or author contains the key.
  final Map<String, List<Book>> library;

  /// Explore categories per source url.
  final Map<String, List<Explore>> kinds;

  /// Explore pages per `"<sourceUrl>|<url>"`: element 0 = page 1.
  final Map<String, List<List<Book>>> pages;

  /// Chapters per `bookUrl`.
  final Map<String, List<BookChapter>> tocs;

  /// Chapter text per `"<bookUrl>|<index>"`; missing entries give `"第n章正文"`.
  final Map<String, String> texts;

  /// Sources whose calls fail.
  final Set<String> failing;

  /// Artificial latency per source (lets tests observe progress / cancel).
  final Duration delay;

  /// Every call, for assertions (`search:<key>`, `explore:<url>:<page>`, `info:<bookUrl>`, `toc:<bookUrl>`, …).
  final List<String> calls = [];

  FakeBookSearchService({
    Map<String, List<Book>>? library,
    Map<String, List<Explore>>? kinds,
    Map<String, List<List<Book>>>? pages,
    Map<String, List<BookChapter>>? tocs,
    Map<String, String>? texts,
    Set<String>? failing,
    this.delay = Duration.zero,
  })  : library = library ?? {},
        kinds = kinds ?? {},
        pages = pages ?? {},
        tocs = tocs ?? {},
        texts = texts ?? {},
        failing = failing ?? {};

  Book _copy(Book b, String origin) => Book.fromJson(b.toJson())..origin = b.origin.isEmpty ? origin : b.origin;

  Future<void> _wait() => delay == Duration.zero ? Future<void>.value() : Future<void>.delayed(delay);

  Stream<List<Book>> _perSource(List<String> urls, List<Book> Function(String url) find) {
    late StreamController<List<Book>> c;
    var cancelled = false;
    Future<void> run() async {
      for (final u in urls) {
        await _wait();
        if (cancelled) return;
        c.add(failing.contains(u) ? <Book>[] : find(u));
      }
      await c.close();
    }

    c = StreamController<List<Book>>(onListen: run, onCancel: () => cancelled = true);
    return c.stream;
  }

  List<String> _urls(List<Source>? sources) => sources == null ? library.keys.toList() : [for (final s in sources) s.bookSourceUrl];

  @override
  Stream<List<Book>> search(String key, {List<Source>? sources}) {
    calls.add('search:$key');
    return _perSource(_urls(sources), (u) => [
          for (final b in library[u] ?? const <Book>[])
            if (b.name.contains(key) || b.author.contains(key)) _copy(b, u)
        ]);
  }

  @override
  Future<List<Explore>> exploreKinds(Source source) async {
    calls.add('kinds:${source.bookSourceUrl}');
    await _wait();
    if (failing.contains(source.bookSourceUrl)) throw StateError('发现加载失败');
    return List<Explore>.of(kinds[source.bookSourceUrl] ?? const <Explore>[]);
  }

  @override
  Future<List<Book>> explore(Source source, String url, int page) async {
    calls.add('explore:$url:$page');
    await _wait();
    if (failing.contains(source.bookSourceUrl)) throw StateError('发现加载失败');
    final list = pages['${source.bookSourceUrl}|$url'] ?? const <List<Book>>[];
    if (page < 1 || page > list.length) return <Book>[];
    return [for (final b in list[page - 1]) _copy(b, source.bookSourceUrl)];
  }

  @override
  Future<Book> bookInfo(Book book) async {
    calls.add('info:${book.bookUrl}');
    await _wait();
    if (failing.contains(book.origin)) throw StateError('详情加载失败');
    for (final list in library.values) {
      for (final b in list) {
        if (b.bookUrl == book.bookUrl) {
          final out = Book.fromJson(book.toJson());
          if (b.intro.isNotEmpty) out.intro = b.intro;
          if (b.coverUrl.isNotEmpty) out.coverUrl = b.coverUrl;
          if (b.kind.isNotEmpty) out.kind = b.kind;
          if (b.wordCount.isNotEmpty) out.wordCount = b.wordCount;
          if (b.latestChapterTitle.isNotEmpty) out.latestChapterTitle = b.latestChapterTitle;
          if (out.tocUrl.isEmpty) out.tocUrl = b.tocUrl.isEmpty ? b.bookUrl : b.tocUrl;
          return out;
        }
      }
    }
    return Book.fromJson(book.toJson())..tocUrl = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl;
  }

  @override
  Future<List<BookChapter>> chapters(Book book) async {
    calls.add('toc:${book.bookUrl}');
    await _wait();
    if (failing.contains(book.origin)) throw StateError('目录加载失败');
    return [for (final c in tocs[book.bookUrl] ?? const <BookChapter>[]) BookChapter.fromJson(c.toJson())];
  }

  @override
  Future<String> content(Book book, BookChapter chapter) async {
    calls.add('content:${book.bookUrl}:${chapter.index}');
    await _wait();
    if (failing.contains(book.origin)) throw StateError('正文获取失败');
    return texts['${book.bookUrl}|${chapter.index}'] ?? '第${chapter.index + 1}章正文';
  }

  @override
  Stream<List<Book>> changeSourceCandidates(Book book, {List<Source>? sources}) {
    calls.add('change:${book.name}');
    return _perSource(_urls(sources), (u) => [
          for (final b in library[u] ?? const <Book>[])
            if (b.name == book.name && (book.author.isEmpty || b.author == book.author) && b.bookUrl != book.bookUrl) _copy(b, u)
        ]);
  }
}
