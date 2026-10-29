// 云端仓库 (data/cloud/cloud_books.dart): settings, the mirror run (upload missing / re-upload a different size / delete what left the
// shelf / keep what another device still lists), the restore of a missing local file, the account-server entry.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/common.dart';
import 'package:newread/data/cloud/cloud_books.dart';
import 'package:newread/data/cloud/cloud_drive.dart';
import 'package:newread/data/user.dart';
import 'package:newread/data/webdav.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/webdavserver.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An in-memory drive: `files` path → bytes, `dirs` the collections.
class FakeDrive extends CloudDrive {
  final Map<String, Uint8List> files = {};
  final Set<String> dirs = {'/'};
  final List<String> calls = [];
  bool failList = false;

  @override
  Future<void> ping() async {}

  @override
  Future<List<CloudFile>> list(String path) async {
    calls.add('list $path');
    if (failList) throw const CloudDriveException('offline');
    final dir = path.endsWith('/') ? path : '$path/';
    if (!dirs.contains(dir)) throw const CloudDriveException('404');
    return [
      for (final e in files.entries)
        if (e.key.startsWith(dir) && !e.key.substring(dir.length).contains('/'))
          CloudFile(name: e.key.substring(dir.length), path: e.key, size: e.value.length),
    ];
  }

  @override
  Future<Uint8List> read(String path, {void Function(int count, int total)? onProgress}) async {
    calls.add('read $path');
    final b = files[path];
    if (b == null) throw const CloudDriveException('404 not found');
    return b;
  }

  @override
  Future<void> write(String path, Uint8List data, {void Function(int count, int total)? onProgress}) async {
    calls.add('write $path');
    files[path] = data;
  }

  @override
  Future<void> mkdir(String path) async {
    calls.add('mkdir $path');
    dirs.add(path.endsWith('/') ? path : '$path/');
  }

  @override
  Future<void> remove(String path) async {
    calls.add('remove $path');
    files.remove(path);
  }

  @override
  Future<void> rename(String from, String to) async {}
}

void main() {
  late Directory tmp;
  late FakeDrive drive;
  final log = <String>[];

  Book local(String file, {String origin = ReadApi.localOrigin}) => Book(bookUrl: 'books/$file', name: file, author: 'A', origin: origin);

  File localFile(String name, [String content = 'text']) {
    final f = File('${tmp.path}/books/$name')..createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qread_cloudbooks_');
    SharedPreferences.setMockInitialValues({});
    await Storage.init(prefs: await SharedPreferences.getInstance(), root: tmp);
    ReadStorageRoot.dir = tmp;
    drive = FakeDrive();
    log.clear();
    CloudBooks.log = log.add;
    CloudBooks.driveOf = (_) => drive;
    await WebDav.load();
    if (WebDav.byId('srv-1') == null) await WebDav.add(WebDavServer(id: 'srv-1', name: '测试盘', url: 'http://dav.test/', type_: CloudDrive.typeWebdav));
    await CloudBooks.save(CloudBooksSettings(serverId: 'srv-1'));
  });

  tearDown(() {
    CloudBooks.log = null;
    CloudBooks.driveOf = CloudDrive.of;
    UserSession.isLoggedIn = false;
    tmp.deleteSync(recursive: true);
  });

  test('settings: the original JSON, a bare id from older builds, nothing', () async {
    final s = CloudBooksSettings.parse('{"serverId":"abc","backupDir":"/my/books","lastSyncTime":"2026-10-29 10:00:00"}');
    expect((s.serverId, s.backupDir, s.lastSyncTime), ('abc', '/my/books', '2026-10-29 10:00:00'));
    expect(CloudBooksSettings.parse('{"serverId":"abc"}').backupDir, '/books');
    expect(CloudBooksSettings.parse('legacy-id').serverId, 'legacy-id');
    expect(CloudBooksSettings.parse('').serverId, '');
    expect(CloudBooksSettings.parse('{bad json').serverId, '', reason: 'broken JSON is ignored');
    expect(CloudBooks.normalizeDir('books/'), '/books');
    expect(CloudBooks.normalizeDir('  /a/b//  '), '/a/b');
    expect(CloudBooks.normalizeDir('\\x'), '/x');
    expect(CloudBooks.configured, isTrue);
  });

  test('sync: uploads what is missing, re-uploads a different size, deletes what left the shelf, keeps another device\'s book', () async {
    localFile('a.txt', 'aaaa');
    localFile('b.epub', 'bbbbbbbb');
    drive.dirs.add('/books/');
    drive.files['/books/b.epub'] = Uint8List.fromList('bb'.codeUnits); // incomplete copy
    drive.files['/books/gone.txt'] = Uint8List.fromList('old'.codeUnits); // no longer on the shelf
    drive.files['/books/other.txt'] = Uint8List.fromList('elsewhere'.codeUnits); // listed by the cloud shelf, file not here
    final shelf = [
      local('a.txt'),
      local('b.epub'),
      local('other.txt', origin: 'phone_book'),
      Book(bookUrl: 'https://example.com/web', name: 'web', origin: 'https://example.com'),
    ];
    final r = await CloudBooks.sync(books: shelf);
    expect(r.uploaded, 2);
    expect(r.deleted, 1);
    expect(r.errors, isEmpty);
    expect(drive.files.keys.toSet(), {'/books/a.txt', '/books/b.epub', '/books/other.txt'});
    expect(String.fromCharCodes(drive.files['/books/b.epub']!), 'bbbbbbbb');
    expect(log, contains('上传了本地中不存在于WebDAV的文件: a.txt'));
    expect(log, contains('上传了WebDAV的不完整的文件: b.epub (本地: 8, WebDAV: 2)'));
    expect(log, contains('删除了WebDAV中不存在于本地的文件: gone.txt'));
    expect(log, contains('同步完成，删除了 1 个WebDAV文件，上传了 2 个本地文件'));
    expect(CloudBooks.load().lastSyncTime, isNotEmpty);
    // a second run has nothing to do
    final r2 = await CloudBooks.sync(books: shelf);
    expect((r2.uploaded, r2.deleted), (0, 0));
  });

  test('sync: the backup folder is created when missing; an unreadable drive fails as 获取WebDAV文件列表失败; no server = 请先选择', () async {
    localFile('a.txt');
    final r = await CloudBooks.sync(books: [local('a.txt')], backupDir: '/novels/');
    expect(r.uploaded, 1);
    expect(drive.dirs, contains('/novels/'));
    expect(drive.files.keys.single, '/novels/a.txt');
    drive.failList = true;
    await expectLater(CloudBooks.sync(books: [local('a.txt')]), throwsA(isA<StateError>().having((e) => e.message, 'm', startsWith('获取WebDAV文件列表失败'))));
    await CloudBooks.save(CloudBooksSettings());
    expect(CloudBooks.configured, isFalse);
    await expectLater(CloudBooks.sync(books: []), throwsA(isA<StateError>().having((e) => e.message, 'm', '请先选择 WebDAV 服务器')));
    expect(CloudBooks.syncing, isFalse);
  });

  test('download / restoreIfMissing: the file comes back from the repository; not there = 当前本地书本不存在或者已被删除', () async {
    drive.dirs.add('/books/');
    drive.files['/books/lost.txt'] = Uint8List.fromList('restored text'.codeUnits);
    final book = local('lost.txt');
    final status = <String>[];
    expect(await CloudBooks.restoreIfMissing(book, status: status.add), isTrue);
    expect(status, ['正在连接云端仓库...']);
    expect(File('${tmp.path}/books/lost.txt').readAsStringSync(), 'restored text');
    expect(File('${tmp.path}/books/lost.txt.part').existsSync(), isFalse);
    // present now: nothing to do; a web book: nothing to do
    expect(await CloudBooks.restoreIfMissing(book), isFalse);
    expect(await CloudBooks.restoreIfMissing(Book(bookUrl: 'https://x', origin: 'https://x')), isFalse);
    await expectLater(CloudBooks.download(local('never.txt')), throwsA(isA<StateError>().having((e) => e.message, 'm', '当前本地书本不存在或者已被删除')));
    // without a repository the open path is left alone
    await CloudBooks.save(CloudBooksSettings());
    expect(await CloudBooks.restoreIfMissing(local('never.txt')), isFalse);
  });

  test('useOwnServer: the account-server entry with the session token as password, refreshed on later use', () async {
    Common.apiBase = 'https://qread.example.com/';
    UserSession.isLoggedIn = true;
    UserSession.username = 'owner';
    UserSession.tockenid = 'tok-1';
    final s = await CloudBooks.useOwnServer();
    expect((s.id, s.name, s.url, s.username, s.password, s.type_), (CloudBooks.ownServerId, CloudBooks.ownServerName, 'https://qread.example.com/dav/', 'owner', 'tok-1', CloudDrive.typeWebdav));
    expect(CloudBooks.load().serverId, CloudBooks.ownServerId);
    expect(WebDav.servers.where((e) => e.id == CloudBooks.ownServerId).length, 1);
    UserSession.tockenid = 'tok-2';
    final again = await CloudBooks.server();
    expect(again!.password, 'tok-2');
    expect(WebDav.servers.where((e) => e.id == CloudBooks.ownServerId).length, 1, reason: 'refreshed, not duplicated');
    UserSession.isLoggedIn = false;
    await expectLater(CloudBooks.useOwnServer(), throwsA(isA<StateError>().having((e) => e.message, 'm', '请先登录')));
  });
}
