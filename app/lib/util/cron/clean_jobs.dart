// util/cron/clean_jobs.dart — the start-up housekeeping of the original (`util/cron/book.dart`; scheduled by main_page 0x10ba82c /
// 0x10bc39c / 0x10bc4c8 and the local-book sweep 0xf813ec; the runner 0xf7b53c logs `执行清理任务时出错`):
//   * 清理图片缓存 (0xf7c670): the picture caches are trimmed to `maxImageCacheSize` MB (阅读设置 › 缓存设置, 1000 by default), the
//     oldest files first — `清理图片缓存: 删除文件 … (x MB)`, `清理完成，删除了 n 个图片文件，释放了 x MB 空间`
//   * 清理非文件夹和空文件 (0xf7bdbc): stray files in the documents root go (`kong` and `icon.txt` are kept), empty ones first
//   * 清理字体文件 (0xf7daf0): files in `fonts/` that no font of the list refers to
//   * 清理本地书籍 (0xf813ec): files in `books/` that no shelf book refers to, and `epub/` folders of books no longer on the shelf
// 清理自动备份 (0xf7b6e0) is the backup service's 保留数量; 同步本地书籍与WebDAV (0xf7e960) belongs to the 云端仓库 and is not ported.
// The jobs run once, a minute after start-up, each on its own so that one failure does not stop the others.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../common/app_dirs.dart';
import '../../data/bookself.dart';
import '../../data/fonts.dart';
import '../../models/book.dart';
import '../../models/font.dart';
import '../../pages/setting/clean_page.dart';
import '../../read/api/read_file_store.dart';
import '../../read/api/read_storage_root.dart';
import '../../read/api/readapi.dart';
import '../../storage/storage.dart';

class CleanReport {
  final int deleted;
  final int freedBytes;
  const CleanReport(this.deleted, this.freedBytes);
  double get freedMB => freedBytes / (1024 * 1024);
}

abstract class CleanJobs {
  static const Duration startupDelay = Duration(seconds: 60);

  /// 阅读设置 › 缓存设置 › 图片缓存 (MB).
  static const String maxImageCacheKey = 'maxImageCacheSize';
  static const int defaultMaxImageCacheMB = 1000;

  /// Files of the documents root that stay (the original keeps `kong` and `icon.txt`; `.qa_driver` is the replica's QA flag).
  static const List<String> keepInRoot = ['kong', 'icon.txt', '.qa_driver'];

  static void Function(String line)? log;
  static Timer? _timer;

  static void scheduleAtStartup({Duration? delay}) {
    _timer?.cancel();
    _timer = Timer(delay ?? startupDelay, () => unawaited(runAll()));
  }

  static void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Runs every job; a failing one is logged (`执行清理任务时出错`) and the next one still runs.
  static Future<void> runAll() async {
    for (final job in <Future<Object?> Function()>[cleanImageCache, cleanStrayFiles, cleanFonts, cleanLocalBooks]) {
      try {
        await job();
      } catch (e) {
        log?.call('执行清理任务时出错: $e');
      }
    }
  }

  // ------------------------------------------------------------------ 清理图片缓存

  static Future<CleanReport> cleanImageCache({int? maxMB, List<Directory>? dirs}) async {
    final limit = (maxMB ?? Storage.getInt(maxImageCacheKey, defaultMaxImageCacheMB)).clamp(1, 1 << 20) * 1024 * 1024;
    final files = <FileStat, File>{};
    var total = 0;
    for (final d in dirs ?? [for (final n in CleanPage.imageDirs) AppDirs.dir(n)]) {
      if (!d.existsSync()) continue;
      for (final e in d.listSync(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final st = e.statSync();
        files[st] = e;
        total += st.size;
      }
    }
    if (total <= limit) return const CleanReport(0, 0);
    final order = files.keys.toList()..sort((a, b) => a.modified.compareTo(b.modified));
    var deleted = 0;
    var freed = 0;
    for (final st in order) {
      if (total - freed <= limit) break;
      final f = files[st]!;
      try {
        f.deleteSync();
        deleted++;
        freed += st.size;
        log?.call('清理图片缓存: 删除文件 ${f.path} (${(st.size / 1048576).toStringAsFixed(2)}MB)');
      } catch (e) {
        log?.call('删除图片文件失败 ${f.path}: $e');
      }
    }
    log?.call('清理完成，删除了 $deleted 个图片文件，释放了 ${(freed / 1048576).toStringAsFixed(2)} MB 空间');
    return CleanReport(deleted, freed);
  }

  // ------------------------------------------------------------------ 清理非文件夹和空文件

  static Future<int> cleanStrayFiles({Directory? root}) async {
    final d = root ?? AppDirs.root;
    if (!d.existsSync()) {
      log?.call('文档目录不存在: ${d.path}');
      return 0;
    }
    var n = 0;
    for (final e in d.listSync(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (keepInRoot.contains(name) || name.startsWith('.')) {
        log?.call('清理非文件夹和空文件: 跳过文件 $name');
        continue;
      }
      try {
        final size = e.lengthSync();
        e.deleteSync();
        n++;
        log?.call(size == 0 ? '清理非文件夹和空文件: 删除空文件 $name' : '清理非文件夹和空文件: 删除文件 $name (${(size / 1048576).toStringAsFixed(2)}MB)');
      } catch (err) {
        log?.call('删除文件失败 $name: $err');
      }
    }
    log?.call('清理完成，删除了 $n 个非文件夹文件');
    return n;
  }

  // ------------------------------------------------------------------ 清理字体文件

  static Future<int> cleanFonts({Iterable<Font>? fonts, Directory? dir}) async {
    final d = dir ?? FontsData.directory;
    if (!d.existsSync()) {
      d.createSync(recursive: true);
      log?.call('字体目录不存在，已创建: ${d.path}');
      return 0;
    }
    final list = fonts ?? await FontsData.load();
    final keep = {for (final f in list) p.normalize(FontsData.filePath(f)).toLowerCase(), for (final f in list) p.basename(f.path).toLowerCase()};
    log?.call('字体文件列表长度: ${list.length}');
    var n = 0;
    for (final e in d.listSync(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path).toLowerCase();
      if (keep.contains(p.normalize(e.path).toLowerCase()) || keep.contains(name)) continue;
      try {
        e.deleteSync();
        n++;
        log?.call('删除了不存在于字体列表的文件: $name');
      } catch (err) {
        log?.call('删除字体文件失败 $name: $err');
      }
    }
    log?.call('清理完成，删除了 $n 个不存在于字体列表的文件');
    return n;
  }

  // ------------------------------------------------------------------ 清理本地书籍

  /// Files of `books/` that no local shelf book refers to (the book file itself and its `<md5(bookUrl)>.chapters.json`), then the
  /// `epub/` folders of books no longer on the shelf (CleanPage.cleanBookCache).
  static Future<int> cleanLocalBooks({Iterable<Book>? books, Directory? booksDir, bool epub = true}) async {
    final d = booksDir ?? ReadStorageRoot.sub('books');
    if (!d.existsSync()) {
      log?.call('书籍目录不存在: ${d.path}');
      return 0;
    }
    final shelf = books ?? (await Bookdata.load());
    final keep = <String>{};
    for (final b in shelf) {
      if (!ReadApi.isLocalBook(b)) continue;
      keep.add(p.basename(b.bookUrl).toLowerCase());
      keep.add('${ReadFileStore.md5Hex(b.bookUrl)}.chapters.json');
    }
    var n = 0;
    for (final e in d.listSync(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (keep.contains(name.toLowerCase())) continue;
      try {
        e.deleteSync();
        n++;
        log?.call('删除了不存在于书架的文件: $name');
      } catch (err) {
        log?.call('删除文件失败 $name: $err');
      }
    }
    log?.call('清理完成，删除了 $n 个不存在于书架的文件');
    if (epub && books == null) {
      final dirs = CleanPage.cleanBookCache('epub');
      if (dirs > 0) log?.call('删除了不存在于书架的文件夹: $dirs ,路径 ${ReadStorageRoot.sub(ReadStorageRoot.epub).path}');
      n += dirs;
    }
    return n;
  }
}
