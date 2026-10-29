// Start-up housekeeping (util/cron/clean_jobs.dart): picture caches trimmed to the limit (oldest first), stray root files, fonts
// not in the list, local book files not on the shelf.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/app_dirs.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/font.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/util/cron/clean_jobs.dart';

File _file(Directory d, String name, int bytes, {DateTime? modified}) {
  final f = File('${d.path}/$name')..createSync(recursive: true);
  f.writeAsBytesSync(List.filled(bytes, 0));
  if (modified != null) f.setLastModifiedSync(modified);
  return f;
}

void main() {
  late Directory tmp;
  final log = <String>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('qread_clean_');
    AppDirs.root = tmp;
    ReadStorageRoot.dir = tmp;
    log.clear();
    CleanJobs.log = log.add;
  });

  tearDown(() {
    CleanJobs.log = null;
    CleanJobs.cancel();
    tmp.deleteSync(recursive: true);
  });

  test('清理图片缓存: nothing below the limit; above it the oldest files go until the cache fits', () async {
    final covers = Directory('${tmp.path}/covers_cache');
    final t0 = DateTime(2026, 1, 1);
    _file(covers, 'old.jpg', 600 * 1024, modified: t0);
    _file(covers, 'sub/mid.jpg', 600 * 1024, modified: t0.add(const Duration(hours: 1)));
    _file(covers, 'new.jpg', 600 * 1024, modified: t0.add(const Duration(hours: 2)));
    expect((await CleanJobs.cleanImageCache(maxMB: 2, dirs: [covers])).deleted, 0);
    expect(covers.listSync(recursive: true).whereType<File>().length, 3);
    final r = await CleanJobs.cleanImageCache(maxMB: 1, dirs: [covers]);
    expect(r.deleted, 2);
    expect(r.freedBytes, 2 * 600 * 1024);
    expect(File('${covers.path}/old.jpg').existsSync(), isFalse);
    expect(File('${covers.path}/sub/mid.jpg').existsSync(), isFalse);
    expect(File('${covers.path}/new.jpg').existsSync(), isTrue);
    expect(log.last, '清理完成，删除了 2 个图片文件，释放了 1.17 MB 空间');
    expect(log.first, startsWith('清理图片缓存: 删除文件 '));
  });

  test('清理非文件夹和空文件: root files go, kong / icon.txt / hidden files and folders stay', () async {
    _file(tmp, 'kong', 3);
    _file(tmp, 'icon.txt', 3);
    _file(tmp, '.qa_driver', 1);
    _file(tmp, 'junk.tmp', 10);
    _file(tmp, 'empty', 0);
    _file(Directory('${tmp.path}/books'), 'a.txt', 5);
    expect(await CleanJobs.cleanStrayFiles(), 2);
    expect(File('${tmp.path}/kong').existsSync(), isTrue);
    expect(File('${tmp.path}/icon.txt').existsSync(), isTrue);
    expect(File('${tmp.path}/.qa_driver').existsSync(), isTrue);
    expect(File('${tmp.path}/junk.tmp').existsSync(), isFalse);
    expect(File('${tmp.path}/empty').existsSync(), isFalse);
    expect(File('${tmp.path}/books/a.txt').existsSync(), isTrue);
    expect(log, contains('清理非文件夹和空文件: 删除空文件 empty'));
    expect(log, contains('清理非文件夹和空文件: 跳过文件 kong'));
    expect(log.last, '清理完成，删除了 2 个非文件夹文件');
  });

  test('清理字体文件: files no font refers to are removed (relative and absolute font paths)', () async {
    final fonts = Directory('${tmp.path}/fonts');
    _file(fonts, 'a.ttf', 4);
    _file(fonts, 'b.ttf', 4);
    _file(fonts, 'c.otf', 4);
    final list = [Font(family: 'A', path: 'a.ttf'), Font(family: 'B', path: '${fonts.path}/b.ttf')];
    expect(await CleanJobs.cleanFonts(fonts: list, dir: fonts), 1);
    expect(File('${fonts.path}/a.ttf').existsSync(), isTrue);
    expect(File('${fonts.path}/b.ttf').existsSync(), isTrue);
    expect(File('${fonts.path}/c.otf').existsSync(), isFalse);
    expect(log, contains('删除了不存在于字体列表的文件: c.otf'));
    // a missing folder is created, nothing deleted
    final none = Directory('${tmp.path}/fonts2');
    expect(await CleanJobs.cleanFonts(fonts: list, dir: none), 0);
    expect(none.existsSync(), isTrue);
  });

  test('清理本地书籍: book files and chapter caches of shelf books stay, the rest goes', () async {
    final books = Directory('${tmp.path}/books');
    _file(books, 'x.txt', 4);
    _file(books, 'y.epub', 4);
    _file(books, 'z.txt', 4);
    _file(books, '${ReadFileStore.md5Hex('books/x.txt')}.chapters.json', 4);
    _file(books, '${ReadFileStore.md5Hex('books/gone.txt')}.chapters.json', 4);
    final shelf = [
      Book(bookUrl: 'books/x.txt', name: 'x', origin: ReadApi.localOrigin),
      Book(bookUrl: '${books.path}/y.epub', name: 'y', origin: ReadApi.localOrigin),
      Book(bookUrl: 'https://example.com/z', name: 'z', origin: 'https://example.com'),
    ];
    expect(await CleanJobs.cleanLocalBooks(books: shelf, booksDir: books), 2);
    expect(File('${books.path}/x.txt').existsSync(), isTrue);
    expect(File('${books.path}/y.epub').existsSync(), isTrue);
    expect(File('${books.path}/z.txt').existsSync(), isFalse);
    expect(File('${books.path}/${ReadFileStore.md5Hex('books/x.txt')}.chapters.json').existsSync(), isTrue);
    expect(File('${books.path}/${ReadFileStore.md5Hex('books/gone.txt')}.chapters.json').existsSync(), isFalse);
    expect(log, contains('删除了不存在于书架的文件: z.txt'));
  });

  test('scheduleAtStartup runs the jobs after the delay; cancel stops it', () async {
    final covers = Directory('${tmp.path}/covers_cache');
    _file(tmp, 'stray.tmp', 2);
    CleanJobs.scheduleAtStartup(delay: const Duration(milliseconds: 20));
    CleanJobs.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(File('${tmp.path}/stray.tmp').existsSync(), isTrue, reason: 'cancelled before it ran');
    CleanJobs.scheduleAtStartup(delay: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(File('${tmp.path}/stray.tmp').existsSync(), isFalse);
    expect(covers.existsSync(), isFalse);
  });
}
