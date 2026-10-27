// Backup zip round trip (+ WebDAV upload / download through a fake drive), HTTP TTS request templates against a local server, and the
// Wi-Fi transfer server.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/app_dirs.dart';
import 'package:newread/data/cloud/cloud_drive.dart';
import 'package:newread/data/cloud/webdav_drive.dart';
import 'package:newread/models/webdavserver.dart';
import 'package:newread/pages/setting/backup_service.dart';
import 'package:newread/pages/webdav/clouddrive2_setup_page.dart';
import 'package:newread/pages/wifi_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/audio/http_tts.dart';
import 'package:path/path.dart' as p;

import '../support/env.dart';

/// In-memory drive for the backup upload / download.
class MemDrive extends CloudDrive {
  final Map<String, Uint8List> files = {};
  final Set<String> dirs = {'/'};

  @override
  Future<void> ping() async {}
  @override
  Future<List<CloudFile>> list(String path) async => [
        for (final e in files.entries)
          if (p.posix.dirname(e.key) == path.replaceAll(RegExp(r'/$'), '')) CloudFile(name: p.posix.basename(e.key), path: e.key, size: e.value.length),
      ]..sort(compareCloudFiles);
  @override
  Future<Uint8List> read(String path, {void Function(int count, int total)? onProgress}) async => files[path]!;
  @override
  Future<void> write(String path, Uint8List data, {void Function(int count, int total)? onProgress}) async => files[path] = data;
  @override
  Future<void> mkdir(String path) async => dirs.add(path);
  @override
  Future<void> remove(String path) async => files.remove(path);
  @override
  Future<void> rename(String from, String to) async => files[to] = files.remove(from)!;
}

void main() {
  late TestDevice dev;
  setUp(() async => dev = await newDevice());
  tearDown(() => dev.delete());

  group('BackupService', () {
    void put(String rel, String text) => File(p.join(AppDirs.root.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    String get(String rel) => File(p.join(AppDirs.root.path, rel)).readAsStringSync();

    test('full backup zips settings.json and the data folders; restore brings prefs and files back', () async {
      await Storage.setString('fontFamily', '阿里圆体');
      await Storage.write('bookself', '[{"bookUrl":"a"}]');
      put('fonts/x.ttf', 'font');
      put('bookcache2/a/1.txt', 'chapter');
      final item = await BackupService.create(name: '完整备份');
      expect(File(item.path).existsSync(), isTrue);
      expect(p.basename(item.path), matches(RegExp(r'^完整备份_\d{14}\.zip$')));
      final names = ZipDecoder().decodeBytes(File(item.path).readAsBytesSync()).files.map((f) => f.name.replaceAll('\\', '/')).toSet();
      expect(names, contains('settings.json'));
      expect(names.any((n) => n.startsWith('item/')), isTrue);
      expect(names, contains('fonts/x.ttf'));
      expect(names, contains('bookcache2/a/1.txt'));
      expect((await BackupService.list()).single.id, item.id);

      // change everything, then restore
      await Storage.setString('fontFamily', '默认');
      await Storage.write('bookself', '[]');
      put('fonts/x.ttf', 'changed');
      put('fonts/new.ttf', 'gone after restore');
      await BackupService.restore(item.path);
      expect(Storage.getString('fontFamily'), '阿里圆体');
      expect(await Storage.read('bookself'), '[{"bookUrl":"a"}]');
      expect(get('fonts/x.ttf'), 'font');
      expect(File(p.join(AppDirs.root.path, 'fonts/new.ttf')).existsSync(), isFalse);
      expect(Directory(p.join(AppDirs.root.path, AppDirs.restoreTemp)).existsSync(), isFalse);
    });

    test('quick backup skips the caches, auto backup holds only item/ and keeps autoBackupNum copies', () async {
      put('bookcache2/a/1.txt', 'chapter');
      put('themes/t.png', 'img');
      await Storage.write('k', 'v');
      final quick = await BackupService.create(name: '快速备份', isquick: true);
      final qn = ZipDecoder().decodeBytes(File(quick.path).readAsBytesSync()).files.map((f) => f.name.replaceAll('\\', '/')).toSet();
      expect(qn, contains('themes/t.png'));
      expect(qn.any((n) => n.startsWith('bookcache2')), isFalse);
      await Storage.setInt(BackupService.autoBackupNumKey, 1);
      await BackupService.autoBackup();
      final last = await BackupService.autoBackup();
      final an = ZipDecoder().decodeBytes(File(last.path).readAsBytesSync()).files.map((f) => f.name.replaceAll('\\', '/')).toSet();
      expect(an.where((n) => n != 'settings.json').every((n) => n.startsWith('item')), isTrue);
      final all = await BackupService.list();
      expect(all.where((b) => b.name == '自动备份').length, 1);
      await BackupService.delete(quick);
      expect(File(quick.path).existsSync(), isFalse);
    });

    test('a zip without settings.json / item is refused with the original message', () async {
      final bad = File(p.join(AppDirs.root.path, 'bad.zip'))..writeAsBytesSync(ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.string('x.txt', 'x'))));
      await expectLater(BackupService.restore(bad.path), throwsA(predicate((e) => '$e'.contains('备份文件错误：缺少必要的settings.json或item目录'))));
    });

    test('upload to a drive and download back registers the backup', () async {
      await Storage.write('k', 'v');
      final item = await BackupService.create(name: '快速备份', isquick: true);
      final drive = MemDrive();
      final server = WebDavServer(id: 's', name: 'nas', url: 'http://nas/dav');
      final remote = await BackupService.upload(item, server, drive: drive);
      expect(remote, '${BackupService.defaultWebdavDir}${p.basename(item.path)}');
      final listed = await BackupService.remoteList(server, drive: drive);
      expect(listed.single.name, p.basename(item.path));
      await BackupService.delete(item);
      final back = await BackupService.download(listed.single, server, drive: drive);
      expect(File(back.path).lengthSync(), drive.files[remote]!.length);
      expect((await BackupService.list()).single.path, back.path);
    });
  });

  group('HTTP TTS templates', () {
    test('expressions: variables, helpers, arithmetic and string concatenation', () {
      final t = TtsTemplate({'speakText': '你好 世界', 'speakSpeed': 10, 'speakVolume': 80, 'voice': 'xiaoyi'});
      expect(t.render('{{java.encodeURI(speakText)}}'), Uri.encodeComponent('你好 世界'));
      expect(t.render('r={{speakSpeed * 2 + 5}}&v={{(speakVolume) / 100}}'), 'r=25&v=0.8');
      expect(t.render("{{'zh-' + voice}}"), 'zh-xiaoyi');
      expect(t.render('{{java.base64Encode(speakText)}}'), base64Encode(utf8.encode('你好 世界')));
      expect(t.render('{{Math.round(speakSpeed / 3)}}'), '3');
      expect(() => t.render('{{eval(speakText)}}'), throwsA(isA<TtsTemplateException>()));
    });

    test('GET and POST definitions (Legado `url,{options}` + header) are built and executed; content type is checked', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String>[];
      server.listen((req) async {
        final body = await utf8.decodeStream(req);
        seen.add('${req.method} ${req.uri} ${req.headers.value('x-key')} $body');
        if (req.uri.path == '/bad') {
          req.response
            ..headers.contentType = ContentType.json
            ..write('{"error":"quota"}');
        } else {
          req.response
            ..headers.contentType = ContentType('audio', 'mpeg')
            ..add([1, 2, 3, 4]);
        }
        await req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      HttpTtsRunner.dio = Dio();
      try {
        final get = await HttpTtsRunner.synthesize({
          'url': '$base/tts?t={{java.encodeURI(speakText)}}&s={{speakSpeed}}',
          'header': '{"x-key":"k1"}',
          'contentType': 'audio/.*',
        }, '春眠', speed: 12);
        expect(get.bytes, [1, 2, 3, 4]);
        expect(get.ext, 'mp3');
        expect(seen.last, 'GET /tts?t=${Uri.encodeComponent('春眠')}&s=12 k1 ');

        final post = HttpTtsRunner.build({'url': '$base/p,{"method":"POST","body":"text={{speakText}}&rate={{speakSpeed + 1}}","headers":{"x-key":"{{voice}}"}}'}, '晓',
            speed: 9, voice: 'v2');
        expect(post.method, 'POST');
        expect(post.url, '$base/p');
        expect(post.body, 'text=晓&rate=10');
        expect(post.headers['x-key'], 'v2');
        await HttpTtsRunner.synthesize({'url': '$base/p,{"method":"POST","body":"text={{speakText}}"}'}, '晓');
        expect(seen.last, startsWith('POST /p null text=晓'));

        await expectLater(HttpTtsRunner.synthesize({'url': '$base/bad', 'contentType': 'audio/.*'}, 'x'), throwsA(predicate((e) => '$e'.contains('quota'))));
        expect(() => HttpTtsRunner.build({'url': '<html><script>async function getttsurl(){}</script>'}, 'x'), throwsA(isA<TtsTemplateException>()));
      } finally {
        HttpTtsRunner.dio = null;
        await server.close(force: true);
      }
    });
  });

  group('Wi-Fi transfer', () {
    test('serves the upload page, stores a multipart book and imports it; other files are refused', () async {
      final imported = <String>[];
      final s = WifiTransferServer(importer: (f) async {
        imported.add(f.path);
        return null;
      });
      await s.start(port: 0, address: InternetAddress.loopbackIPv4);
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      try {
        final page = await dio.get<String>('http://127.0.0.1:${s.port}/');
        expect(page.data, contains('Wi-Fi传书'));
        final ok = await dio.post<dynamic>('http://127.0.0.1:${s.port}/upload',
            data: FormData.fromMap({'file': MultipartFile.fromBytes(utf8.encode('第一章\n正文'), filename: '书.txt')}));
        expect(ok.statusCode, 200);
        expect((ok.data is String ? jsonDecode(ok.data as String) : ok.data)['message'], '文件上传并导入书架成功');
        expect(File(imported.single).readAsStringSync(), '第一章\n正文');
        expect(s.uploaded.single.name, '书.txt');
        final bad = await dio.post<dynamic>('http://127.0.0.1:${s.port}/upload',
            data: FormData.fromMap({'file': MultipartFile.fromBytes([1, 2], filename: 'a.exe')}));
        expect(bad.statusCode, 400);
        expect('${bad.data}', contains('上传失败：请先选择需要上传的书本'));
      } finally {
        await s.dispose();
      }
    });
  });

  test('CloudDrive2 urls get scheme, port 19798 and /dav only when missing; WebDAV entries map to CloudFiles', () {
    expect(CloudDrive2SetupPage.normalize('192.168.1.5'), 'http://192.168.1.5:19798/dav');
    expect(CloudDrive2SetupPage.normalize('https://nas.lan:8443/webdav'), 'https://nas.lan:8443/webdav');
    expect(CloudDrive2SetupPage.normalize('nas.lan:5000'), 'http://nas.lan:5000/dav');
    final drive = CloudDrive.of(WebDavServer(url: 'http://x/dav', type_: CloudDrive.typeCloudDrive2));
    expect(drive, isA<WebDavDrive>());
    expect(compareCloudFiles(const CloudFile(name: 'b', path: '/b/', isDir: true), const CloudFile(name: 'a.txt', path: '/a.txt')), lessThan(0));
  });
}
