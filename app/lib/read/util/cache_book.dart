// read/util/cache_book.dart — downloads chapters ahead of reading ("批量下载" / "缓存章节", top menu of the reader and the download manager).
//
// Original (class 1472 `CacheBook`, 0x58 bytes, static `_lock` 0x40a8; the worker closure 0xf6d158 is 0x848 bytes): a task per book that
// fetches the chapters of a range one after the other, writes them with `BookContent` and reports progress; a second request for a book
// that is already being cached is refused with "已有缓存任务正在进行中". This port keeps that contract with a configurable number of parallel
// downloads and a cancel callback; the notification part (`down_notification.dart`) belongs to the UI.
import 'dart:async';
import 'dart:math' as math;

import '../../models/bookchapter.dart';
import '../api/readapi.dart';
import 'comic_cache.dart';

class CacheResult {
  /// Chapters fetched and stored by this run.
  final List<int> cached;

  /// Chapters that were already cached or are not downloadable (volume titles, paid chapters).
  final List<int> skipped;

  /// Chapters whose download failed, with the error text.
  final Map<int, String> failed;

  /// The run was stopped by `isCancelled`.
  final bool cancelled;

  const CacheResult(this.cached, this.skipped, this.failed, this.cancelled);
}

class CacheBook {
  static final Set<String> _running = {};

  /// True while a task for [bookUrl] runs.
  static bool isRunning(String bookUrl) => _running.contains(bookUrl);

  final ReadApi api;

  /// Parallel downloads (the original goes one by one; sources with rate limits should use 1).
  final int concurrent;

  CacheBook(this.api, {this.concurrent = 2});

  /// Caches chapters [from]..[to] (inclusive, clamped to the book). [onProgress] gets (finished, total, chapterIndex).
  /// Throws [StateError] with the original's text when the book is already being cached.
  Future<CacheResult> cacheRange(
    int from,
    int to, {
    void Function(int done, int total, int index)? onProgress,
    bool Function()? isCancelled,
    bool skipPaid = true,
  }) async {
    final book = api.book;
    if (_running.contains(book.bookUrl)) throw StateError('已有缓存任务正在进行中');
    final loader = api.loader;
    if (loader == null) throw StateError('没有章节来源');
    _running.add(book.bookUrl);
    try {
      final last = api.chapters.length - 1;
      final lo = math.max(0, math.min(from, to));
      final hi = math.min(last, math.max(from, to));
      final cached = <int>[];
      final skipped = <int>[];
      final failed = <int, String>{};
      if (ReadApi.isLocalBook(book)) {
        return CacheResult(cached, [for (var i = lo; i <= hi; i++) i], failed, false);
      }
      // comics keep their pictures in ComicCache (the original's worker caches the images of a chapter too, `缓存图片失败`)
      final comic = ComicCache.isComic(book);
      final todo = <int>[];
      for (var i = lo; i <= hi; i++) {
        final c = api.chapters[i];
        final have = comic ? ComicCache.exists(book.bookUrl, i) : api.bookContent.existsSync(book.bookUrl, i);
        if (c.isVolume || (skipPaid && c.isPay) || have) {
          skipped.add(i);
        } else {
          todo.add(i);
        }
      }
      var done = 0;
      var cancelled = false;
      var next = 0;
      Future<void> worker() async {
        while (true) {
          if (isCancelled?.call() ?? false) {
            cancelled = true;
            return;
          }
          if (next >= todo.length) return;
          final index = todo[next++];
          final BookChapter chapter = api.chapters[index];
          try {
            if (comic) {
              final lost = await ComicCache.cacheChapter(api, index, isCancelled: isCancelled);
              if (lost > 0) {
                failed[index] = '缓存图片失败: $lost 张';
              } else {
                cached.add(index);
              }
            } else {
              final content = await loader(chapter);
              if (content.text.trim().isEmpty) {
                failed[index] = '正文为空';
              } else {
                await api.bookContent.saveToLocal(book.bookUrl, index, content.text, book: book);
                cached.add(index);
              }
            }
          } catch (e) {
            failed[index] = '$e';
          }
          done++;
          onProgress?.call(done, todo.length, index);
        }
      }

      await Future.wait([for (var i = 0; i < math.max(1, concurrent); i++) worker()]);
      cached.sort();
      return CacheResult(cached, skipped, failed, cancelled);
    } finally {
      _running.remove(book.bookUrl);
    }
  }
}
