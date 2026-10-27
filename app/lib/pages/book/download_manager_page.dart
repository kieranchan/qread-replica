// pages/book/download_manager_page.dart — 下载管理: running chapter downloads (`CacheBook`) with progress, pause / cancel, and the
// books that have a chapter cache on disk (scan of `/bookcache2`, sizes, 「缓存总大小: 」, clear).
//
// Original (`_DownloadManagerPageState`, `CachedBookInfo`): two tabs — tasks (「暂无下载任务」, 「已停止」, 「 章」, 「总进度」,
// 「 进行中」) and cached books (`_scanCachedBooks`: `/bookcache2`, `/audio2`, `/covers` per book with `book.json`; 「暂无缓存书籍」,
// 「未知书籍」, 「缓存已清除」 / 「清除失败」, 「扫描缓存失败: 」). The task queue is `Common.cacheBooks` in the original; the replica keeps
// it in [DownloadTasks].
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../read/api/book_content.dart';
import '../../read/api/read_file_store.dart';
import '../../read/api/read_storage_root.dart';
import '../../read/api/readapi.dart';
import '../../read/util/cache_book.dart';
import '../../read/util/chapter_content.dart';
import '../../util/toast.dart';
import '../../widget/book/toc_cache.dart';
import '../../widget/book_page.dart';
import '../../widget/image/cached_cover_image.dart';
import '../search/book_search_service.dart';

enum DownloadState { waiting, running, paused, done, failed }

/// One download job: chapters [from]..[to] of [book].
class DownloadTask {
  final Book book;
  final int from;
  final int to;
  DownloadState state = DownloadState.waiting;
  int done = 0;
  int total = 0;
  int failed = 0;
  String error = '';
  bool _stop = false;

  DownloadTask(this.book, this.from, this.to);

  double get progress => total == 0 ? 0 : done / total;
}

/// The queue of downloads (one book at a time per task, chapters fetched in parallel by [CacheBook]).
abstract class DownloadTasks {
  static final List<DownloadTask> tasks = [];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Parallel chapter downloads (缓存线程).
  static int concurrent = 2;

  static void _bump() => revision.value++;

  static DownloadTask? taskOf(String bookUrl) {
    for (final t in tasks) {
      if (t.book.bookUrl == bookUrl && (t.state == DownloadState.running || t.state == DownloadState.waiting)) return t;
    }
    return null;
  }

  /// Queues chapters [from]..[to] (0-based, inclusive; null = whole book). Refuses a second task for a running book with the
  /// original's text 「已有缓存任务正在进行中」. Local books need no download.
  static Future<DownloadTask?> start(Book book, {int? from, int? to, List<BookChapter>? chapters}) async {
    if (isLocalShelfBook(book)) return null;
    if (taskOf(book.bookUrl) != null || CacheBook.isRunning(book.bookUrl)) {
      Toast.show('已有缓存任务正在进行中');
      return null;
    }
    final t = DownloadTask(book, from ?? 0, to ?? 1 << 30);
    tasks.add(t);
    _bump();
    unawaited(_run(t, chapters));
    return t;
  }

  static Future<void> _run(DownloadTask t, List<BookChapter>? chapters) async {
    t.state = DownloadState.running;
    t._stop = false;
    _bump();
    try {
      final list = chapters ?? await TocCache.load(t.book);
      final api = ReadApi(t.book, chapters: list, loader: (c) async => ChapterContent.fromText(await BookSearchService.instance.content(t.book, c)));
      final r = await CacheBook(api, concurrent: concurrent).cacheRange(
        t.from,
        t.to.clamp(0, list.isEmpty ? 0 : list.length - 1),
        onProgress: (done, total, _) {
          t.done = done;
          t.total = total;
          _bump();
        },
        isCancelled: () => t._stop,
      );
      t.failed = r.failed.length;
      if (t.total == 0) t.total = r.cached.length + r.failed.length;
      t.state = r.cancelled ? DownloadState.paused : DownloadState.done;
    } catch (e) {
      t.error = '$e';
      t.state = DownloadState.failed;
    }
    _bump();
  }

  /// Stops a running task (「已停止」); already cached chapters stay.
  static void pause(DownloadTask t) {
    t._stop = true;
    _bump();
  }

  /// Restarts a stopped task (cached chapters are skipped by CacheBook).
  static void resume(DownloadTask t) {
    if (t.state == DownloadState.running) return;
    t.done = 0;
    unawaited(_run(t, null));
  }

  /// Stops and removes the task.
  static void cancel(DownloadTask t) {
    t._stop = true;
    tasks.remove(t);
    _bump();
  }

  static void clearFinished() {
    tasks.removeWhere((t) => t.state == DownloadState.done);
    _bump();
  }
}

/// `CachedBookInfo`: one book directory of the chapter cache.
class CachedBookInfo {
  final String dir;
  final Book? book;
  final int contentCount;
  final int contentSize;

  const CachedBookInfo(this.dir, this.book, this.contentCount, this.contentSize);

  String get name => book?.name.isNotEmpty == true ? book!.name : '未知书籍';
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// `_scanCachedBooks`: every `<root>/bookcache2/<md5>/` with its `book.json` (written by BookContent.saveToLocal).
Future<List<CachedBookInfo>> scanCachedBooks() async {
  if (!ReadStorageRoot.isSet) return [];
  final root = ReadStorageRoot.sub(ReadStorageRoot.bookcache2).path;
  return ReadIsolate.run(() {
    final d = Directory(root);
    if (!d.existsSync()) return <CachedBookInfo>[];
    final out = <CachedBookInfo>[];
    for (final e in d.listSync()) {
      if (e is! Directory) continue;
      var count = 0, size = 0;
      Book? book;
      for (final f in e.listSync(recursive: true)) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (name == 'book.json') {
          try {
            final j = jsonDecode(f.readAsStringSync());
            if (j is Map) book = Book.fromJson(Map<String, dynamic>.from(j));
          } catch (_) {}
          continue;
        }
        count++;
        size += f.lengthSync();
      }
      out.add(CachedBookInfo(e.path, book, count, size));
    }
    out.sort((a, b) => b.contentSize.compareTo(a.contentSize));
    return out;
  });
}

class DownloadManagerPage extends StatefulWidget {
  const DownloadManagerPage({super.key});

  @override
  State<DownloadManagerPage> createState() => _DownloadManagerPageState();
}

class _DownloadManagerPageState extends State<DownloadManagerPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<CachedBookInfo>? _cached;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    try {
      final r = await scanCachedBooks();
      if (mounted) setState(() => _cached = r);
    } catch (e) {
      Toast.show('扫描缓存失败: $e', iserror: true);
      if (mounted) setState(() => _cached = []);
    }
  }

  Future<void> _clear(CachedBookInfo info) async {
    try {
      if (info.book != null) {
        await const BookContent().deleteBook(info.book!.bookUrl);
      }
      final d = Directory(info.dir);
      if (d.existsSync()) d.deleteSync(recursive: true);
      Toast.show('缓存已清除');
    } catch (e) {
      Toast.show('清除失败', iserror: true);
    }
    await _scan();
  }

  Widget _tasks() {
    return ValueListenableBuilder<int>(
      valueListenable: DownloadTasks.revision,
      builder: (context, _, _) {
        final list = DownloadTasks.tasks;
        if (list.isEmpty) return const Center(child: Text('暂无下载任务'));
        final running = list.where((t) => t.state == DownloadState.running).length;
        final total = list.fold<int>(0, (a, t) => a + t.total);
        final done = list.fold<int>(0, (a, t) => a + t.done);
        return Column(children: [
          ListTile(
            title: const Text('总进度'),
            subtitle: LinearProgressIndicator(value: total == 0 ? 0 : done / total),
            trailing: Text('$running 进行中'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (c, i) {
                final t = list[i];
                final stopped = t.state == DownloadState.paused;
                return ListTile(
                  key: Key('task_${t.book.bookUrl}'),
                  leading: CachedCoverImage(url: t.book.coverUrl, title: t.book.name, width: 40, height: 54),
                  title: Text(t.book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    LinearProgressIndicator(value: t.progress),
                    Text(stopped
                        ? '已停止'
                        : t.state == DownloadState.failed
                            ? t.error
                            : '${t.done}/${t.total} 章  ${(t.progress * 100).toStringAsFixed(0)}%'),
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (t.state == DownloadState.running)
                      IconButton(key: Key('pause_${t.book.bookUrl}'), icon: const Icon(Icons.pause), onPressed: () => DownloadTasks.pause(t)),
                    if (stopped || t.state == DownloadState.failed)
                      IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => DownloadTasks.resume(t)),
                    IconButton(key: Key('cancel_${t.book.bookUrl}'), icon: const Icon(Icons.close), onPressed: () => DownloadTasks.cancel(t)),
                  ]),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  Widget _cachedList() {
    final list = _cached;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) return const Center(child: Text('暂无缓存书籍'));
    final size = list.fold<int>(0, (a, b) => a + b.contentSize);
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Text('缓存总大小: ${formatBytes(size)}')),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _scan,
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final info = list[i];
              return ListTile(
                leading: CachedCoverImage(url: info.book?.coverUrl ?? '', title: info.name, width: 40, height: 54),
                title: Text(info.name),
                subtitle: Text('${bookTypeLabel(info.book?.type_ ?? 0)} · ${info.contentCount} 章 · ${formatBytes(info.contentSize)}'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _clear(info)),
              );
            },
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        centerTitle: true,
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: '下载任务'), Tab(text: '已缓存')]),
      ),
      body: TabBarView(controller: _tabs, children: [_tasks(), _cachedList()]),
    );
  }
}
