// Contract test: the app's WebDAV client (WebDavDrive, package webdav_client) against the real server's `/dav` store (spawned from
// ../server with a temp database): Basic auth with the password and with the session token, mkdir / write / list / read / remove /
// rename, and the 云端仓库 mirror run through CloudBooks on top of it. Skipped when `node` is not available.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/cloud/cloud_books.dart';
import 'package:newread/data/cloud/cloud_drive.dart';
import 'package:newread/data/cloud/webdav_drive.dart';
import 'package:newread/data/webdav.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/webdavserver.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<int> freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

bool hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0 && Directory('../server/src').existsSync();
  } catch (_) {
    return false;
  }
}

Future<Map<String, dynamic>> post(String base, String path, Map<String, dynamic> body) async {
  final c = HttpClient();
  try {
    final req = await c.postUrl(Uri.parse('$base$path'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    c.close();
  }
}

void main() {
  final skip = hasNode() ? null : 'node or ../server not available';
  late Process server;
  late Directory tmp;
  late String base;
  late String token;

  String admin(List<String> args, Map<String, String> env) {
    final r = Process.runSync('node', ['--disable-warning=ExperimentalWarning', 'src/admin.mjs', ...args], workingDirectory: '../server', environment: env, stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return (r.stdout as String).trim();
  }

  setUpAll(() async {
    if (skip != null) return;
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('qread-dav-contract-');
    await Storage.init(root: Directory('${tmp.path}/app'));
    ReadStorageRoot.dir = Directory('${tmp.path}/app');
    final port = await freePort();
    base = 'http://127.0.0.1:$port';
    final env = {'QREAD_PORT': '$port', 'QREAD_HOST': '127.0.0.1', 'QREAD_DATA_DIR': tmp.path, 'QREAD_BASE_URL': base, 'QREAD_LOG': '0'};
    server = await Process.start('node', ['--disable-warning=ExperimentalWarning', 'src/server.mjs'], workingDirectory: '../server', environment: env);
    server.stdout.drain<void>();
    server.stderr.drain<void>();
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      try {
        final c = HttpClient();
        final r = await (await c.getUrl(Uri.parse('$base/healthz'))).close();
        await r.drain<void>();
        c.close();
        if (r.statusCode == 200) break;
      } catch (_) {}
      if (DateTime.now().isAfter(deadline)) fail('server did not start');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final invite = admin(['make-codes', 'invite'], env);
    final code = RegExp(r'\d{6}').firstMatch(invite)!.group(0)!;
    expect((await post(base, '/register', {'username': 'davdart', 'email': 'davdart@example.com', 'password': 'secret-pw', 'code': code}))['code'], 0);
    final login = await post(base, '/login', {'username': 'davdart', 'password': 'secret-pw', 'platform': 'ios', 'model': 'iPhone', 'appid': 'dart-dav'});
    expect(login['code'], 0, reason: '$login');
    token = '${(login['data'] as Map)['id']}';
  });

  tearDownAll(() async {
    if (skip != null) return;
    server.kill();
    await server.exitCode;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('WebDavDrive against /dav: token auth, folder, upload, list, download, rename, delete; wrong secret is refused', () async {
    final drive = WebDavDrive(WebDavServer(id: 'd', name: 'own', url: '$base/dav/', username: 'davdart', password: token, type_: CloudDrive.typeWebdav));
    await drive.ping();
    await drive.mkdir('/books');
    await drive.write('/books/斩神.txt', Uint8List.fromList(utf8.encode('第一章 正文')));
    await drive.write('/books/b.epub', Uint8List.fromList(List<int>.filled(300, 7)));
    final list = await drive.list('/books');
    expect(list.map((f) => f.name).toSet(), {'斩神.txt', 'b.epub'});
    expect(list.firstWhere((f) => f.name == 'b.epub').size, 300);
    expect(utf8.decode(await drive.read('/books/斩神.txt')), '第一章 正文');
    await drive.rename('/books/b.epub', '/books/c.epub');
    expect((await drive.list('/books')).map((f) => f.name).toSet(), {'斩神.txt', 'c.epub'});
    await drive.remove('/books/c.epub');
    expect((await drive.list('/books')).map((f) => f.name).toList(), ['斩神.txt']);
    // the password works too; a wrong secret does not
    final byPassword = WebDavDrive(WebDavServer(url: '$base/dav/', username: 'davdart', password: 'secret-pw', type_: CloudDrive.typeWebdav));
    expect((await byPassword.list('/books')).length, 1);
    final wrong = WebDavDrive(WebDavServer(url: '$base/dav/', username: 'davdart', password: 'nope', type_: CloudDrive.typeWebdav));
    await expectLater(wrong.list('/books'), throwsA(isA<CloudDriveException>()));
  }, skip: skip);

  test('CloudBooks.sync mirrors the shelf\'s local books into the store and restores a missing file from it', () async {
    final drive = WebDavDrive(WebDavServer(id: 'd', name: 'own', url: '$base/dav/', username: 'davdart', password: token, type_: CloudDrive.typeWebdav));
    final booksDir = Directory('${tmp.path}/app/books')..createSync(recursive: true);
    File('${booksDir.path}/novel.txt').writeAsStringSync('本地书正文' * 100);
    final shelf = [Book(bookUrl: 'books/novel.txt', name: 'novel', author: 'A', origin: ReadApi.localOrigin)];
    await CloudBooks.save(CloudBooksSettings(serverId: 'd', backupDir: '/mirror'));
    final r = await CloudBooks.sync(drive: drive, books: shelf);
    expect(r.uploaded, 1);
    expect(r.deleted, 0);
    expect(r.errors, isEmpty);
    expect((await drive.list('/mirror')).map((f) => f.name).toList(), ['novel.txt']);
    // the local file disappears: opening it restores the copy
    File('${booksDir.path}/novel.txt').deleteSync();
    // the open path (restoreIfMissing) goes through the stored server entry and the real drive factory
    await WebDav.load();
    await WebDav.add(WebDavServer(id: 'd', name: 'own', url: '$base/dav/', username: 'davdart', password: token, type_: CloudDrive.typeWebdav));
    expect(await CloudBooks.restoreIfMissing(shelf.first), isTrue);
    expect(File('${booksDir.path}/novel.txt').readAsStringSync(), '本地书正文' * 100);
    expect(await CloudBooks.restoreIfMissing(shelf.first), isFalse, reason: 'present again');
  }, skip: skip);
}
