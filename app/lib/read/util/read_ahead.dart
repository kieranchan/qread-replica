// read/util/read_ahead.dart — 预缓存 while reading: the chapters after the one being read are downloaded in the background
// so that they are on disk before the reader gets there (and stay readable offline).
//
// Original: the reading core reads the 书源设置 value `cachebook` (预缓存 / 缓存章数, default "5", `阅读时预先缓存的数量，如果
// 书源不允许下载请设置为0。`, read by 0x1f90e0 from the reader's initialisation 0xe8db48) and fetches that many chapters ahead
// of the current one. This port keeps the setting and the behaviour: one quiet task per book that walks forward from the
// current chapter, writes each chapter with `BookContent` exactly like 批量下载 (`cache_book.dart`), skips chapters that are
// already cached, volume titles and paid chapters, fetches one chapter at a time (sources are rate limited), and moves its
// window whenever the reader turns to another chapter. A running 批量下载 of the same book pauses it; three failures in a row
// stop it (the source is probably down) until the next chapter change.
import 'dart:async';
import 'dart:math' as math;

import '../../storage/storage.dart';
import '../api/readapi.dart';
import 'cache_book.dart';

class ReadAhead {
  /// The value the setting takes when it was never set (the original ships 5; the owner reads faster than that).
  static const int defaultCount = 20;

  /// Upper bound of the setting (书源设置 → 缓存章数).
  static const int maxCount = 500;

  /// How many chapters to keep cached ahead of the current one (0 = off). Replaceable for tests.
  static int Function() count = () => (Storage.ready ? Storage.getInt('cachebook', defaultCount) : defaultCount).clamp(0, maxCount);

  /// Lines for the reader log (`预缓存 …`).
  static void Function(String line)? log;

  static final Map<String, _Job> _jobs = {};

  static bool isRunning(String bookUrl) => _jobs.containsKey(bookUrl);

  /// The running job's completion (tests), null when none runs.
  static Future<void>? running(String bookUrl) => _jobs[bookUrl]?.done.future;

  /// The reader is at chapter [index] of [api]'s book: keep the next `count()` chapters cached.
  static void touch(ReadApi api, int index) {
    final n = count();
    final book = api.book;
    if (n <= 0 || api.loader == null || ReadApi.isLocalBook(book) || api.chapters.isEmpty) return;
    final last = api.chapters.length - 1;
    final from = math.min(index + 1, last);
    final to = math.min(index + n, last);
    if (from > to) return;
    final job = _jobs[book.bookUrl];
    if (job != null) {
      job.move(from, to);
      return;
    }
    final j = _Job(api, from, to);
    _jobs[book.bookUrl] = j;
    j.onDone = () {
      if (_jobs[book.bookUrl] == j) _jobs.remove(book.bookUrl);
    };
    j.run();
  }

  /// Stops the job of [bookUrl] (the reader closed).
  static void stop(String bookUrl) {
    _jobs[bookUrl]?.cancelled = true;
  }

  static void stopAll() {
    for (final j in _jobs.values) {
      j.cancelled = true;
    }
  }
}

class _Job {
  final ReadApi api;
  int from;
  int to;
  bool cancelled = false;
  final Completer<void> done = Completer<void>();

  /// Runs before [done] completes (the registry drops the job).
  void Function()? onDone;

  _Job(this.api, this.from, this.to);

  /// A chapter change: continue from the new position (chapters before it are no longer worth fetching).
  void move(int newFrom, int newTo) {
    from = newFrom;
    to = math.max(newTo, to);
    // a job that stopped after repeated failures starts counting again from the new position
    _failures = 0;
  }

  int _failures = 0;

  Future<void> run() async {
    final book = api.book;
    final loader = api.loader!;
    var i = from;
    try {
      while (!cancelled) {
        if (i < from) i = from;
        if (i > to || i >= api.chapters.length) break;
        if (CacheBook.isRunning(book.bookUrl)) {
          // 批量下载 of this book is fetching: let it work, look again later
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        final chapter = api.chapters[i];
        if (chapter.isVolume || chapter.isPay || api.bookContent.existsSync(book.bookUrl, i)) {
          i++;
          continue;
        }
        try {
          final content = await loader(chapter);
          if (content.text.trim().isEmpty) throw StateError('正文为空');
          await api.bookContent.saveToLocal(book.bookUrl, i, content.text, book: book);
          _failures = 0;
          ReadAhead.log?.call('预缓存 第${i + 1}章 ${chapter.name}');
        } catch (e) {
          _failures++;
          ReadAhead.log?.call('预缓存失败 第${i + 1}章: $e');
          if (_failures >= 3) {
            ReadAhead.log?.call('预缓存连续失败，暂停到下一次翻章');
            break;
          }
        }
        i++;
        // give the UI and the source a breath between chapters
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } finally {
      onDone?.call();
      if (!done.isCompleted) done.complete();
    }
  }
}
