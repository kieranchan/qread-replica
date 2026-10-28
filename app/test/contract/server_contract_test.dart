// Contract test: the Dart UserApi against the real qread-server (spawned from ../server with a temp database).
// Skipped when `node` is not available. Covers register, login, the membership flow and the cloud-sync calls.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/userapi.dart';
import 'package:newread/common/common.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/data/cloud/auto_backup.dart';
import 'package:newread/data/rss.dart';
import 'package:newread/data/source.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/about_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/self_check.dart';
import 'package:newread/util/toast.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();

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

void main() {
  final skip = hasNode() ? null : 'node or ../server not available';
  late Process server;
  late Directory tmp;
  late Map<String, String> env;
  late String base;

  String admin(List<String> args) {
    final r = Process.runSync('node', ['--disable-warning=ExperimentalWarning', 'src/admin.mjs', ...args], workingDirectory: '../server', environment: env, stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return (r.stdout as String).trim();
  }

  setUpAll(() async {
    if (skip != null) return;
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('qread-contract-');
    await Storage.init(root: Directory('${tmp.path}/app')); // the file store (shelf, sources) lives here, not in path_provider
    final port = await freePort();
    base = 'http://127.0.0.1:$port';
    env = {'QREAD_PORT': '$port', 'QREAD_HOST': '127.0.0.1', 'QREAD_DATA_DIR': tmp.path, 'QREAD_BASE_URL': base, 'QREAD_LOG': '0'};
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
    Common.apiBase = '$base/';
    Common.appid = 'dart-test-1';
    Common.deviceModel = 'flutter-test';
  });

  tearDownAll(() async {
    if (skip != null) return;
    server.kill();
    await server.exitCode;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('register needs an admin-issued invite code', () async {
    await expectLater(UserApi.register(username: 'dart', email: 'dart@example.com', password: 'secret-pw', code: '000000'), throwsA(isA<ApiException>()));
    final invite = admin(['make-codes', 'invite']);
    await UserApi.register(username: 'dart', email: 'dart@example.com', password: 'secret-pw', code: invite);
    // the code is single use
    await expectLater(UserApi.register(username: 'dart2', email: 'dart2@example.com', password: 'secret-pw', code: invite), throwsA(isA<ApiException>()));
  }, skip: skip);

  test('login returns a session; the app applies it and survives a restart', () async {
    await expectLater(UserApi.login('dart', 'wrong'), throwsA(isA<ApiException>()));
    final info = await UserApi.login('dart', 'secret-pw');
    expect(info.tockenid, isNotEmpty);
    expect(info.isvip, isFalse);
    expect(info.username, 'dart');
    await UserSession.apply(info);
    expect(UserSession.isLoggedIn, isTrue);
    UserSession.tockenid = '';
    await UserSession.restore();
    expect(UserSession.tockenid, info.tockenid);
    expect(await UserSession.refresh(), isTrue);
  }, skip: skip);

  test('non-member: cloud closed on the server, gate toast, sync switches off', () async {
    expect(UserSession.isvip, isFalse);
    expect(await UserApi.canOpenCloud(), isFalse);
    await UserSession.setSwitch(PrefKeys.cloudbookself, true);
    Toast.log.clear();
    expect(await UserApi.cloudEtag(CloudKind.books), '');
    expect(UserSession.cloudbookself, isFalse, reason: 'a failed cloud call turns the bookshelf sync off');
    expect(Toast.log, contains('云端功能需要会员权限'));
    await expectLater(UserApi.getItemJson('tts_engines'), throwsA(isA<ApiException>()));
  }, skip: skip);

  test('membership: activation code via paynew -> refresh -> isvip, expiry shown', () async {
    await expectLater(UserApi.redeem('QR-0000-0000-0000'), throwsA(isA<ApiException>()));
    final code = admin(['make-codes', 'vip', '30']);
    await UserApi.redeem(code);
    expect(UserSession.isvip, isTrue);
    expect(UserSession.vipText, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(await UserApi.canOpenCloud(), isTrue);
    await expectLater(UserApi.redeem(code), throwsA(isA<ApiException>()), reason: 'codes are single use');
    // the same page the app opens
    final c = HttpClient();
    final r = await (await c.getUrl(Uri.parse('${Common.apiBase}vip?tockenid=${UserSession.tockenid}'))).close();
    expect(r.statusCode, 200);
    expect(await r.transform(utf8.decoder).join(), contains('会员中心'));
    c.close();
  }, skip: skip);

  test('cloud: items, md5 and the etag / update-url / list flow', () async {
    expect(await UserApi.getItemJson('tts_engines'), '');
    expect(await UserApi.getItemMd5('tts_engines'), '');
    const tts = '[{"name":"引擎","id":1}]';
    await UserApi.setItemJsonFile('tts_engines', tts);
    expect(await UserApi.getItemJson('tts_engines'), tts);
    expect(await UserApi.getItemMd5('tts_engines'), md5Hex(tts));

    expect(await UserApi.cloudEtag(CloudKind.books), '');
    expect(await UserApi.cloudList(CloudKind.books), '');
    const books = '[{"bookUrl":"u1","name":"A"},{"bookUrl":"u2","name":"B"}]';
    await UserApi.setItemJsonFile('books', books);
    final etag = await UserApi.cloudEtag(CloudKind.books);
    expect(etag, md5Hex(books));
    expect(await UserApi.cloudUpdateUrl(CloudKind.books, etag), etag, reason: 'client is current: the server etag');
    expect(await UserApi.cloudUpdateUrl(CloudKind.books, 'stale'), '', reason: 'newer data exists: empty = merge');
    expect(await UserApi.cloudList(CloudKind.books), books);
    for (final k in CloudKind.values) {
      expect(await UserApi.cloudUpdateUrl(k, 'x'), anyOf('', isNotEmpty));
    }
  }, skip: skip);

  test('device backups: openAuto -> PUT -> device list -> getBookSelf; newopenAuto2 -> sources / rss', () async {
    AutoBackup.reset();
    // st "1" (start-up) needs a registered device; the failure switches the backup off
    await UserSession.setSwitch(PrefKeys.autoSyncEnabled, true);
    await expectLater(UserApi.openAuto(st: '1'), throwsA(isA<ApiException>()));
    expect(UserSession.autoSyncEnabled, isFalse);
    final url = await UserApi.openAuto();
    expect(url, startsWith('$base/autobackup/'));
    expect(AutoBackup.booksUrl, url);
    await Bookdata.load();
    Bookdata.books
      ..clear()
      ..add(Book(name: '书一', author: '某人', bookUrl: 'https://example.com/b1'));
    await AutoBackup.backupBooks();
    expect(Storage.getString(PrefKeys.lastSyncTime), matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));
    final devs = await UserApi.getAutoDevices(1);
    expect(devs.single.appid, 'dart-test-1');
    expect(devs.single.model, 'flutter-test');
    Toast.log.clear();
    final books = await UserApi.getBookSelf('dart-test-1');
    expect(Toast.log, isEmpty);
    expect(books.single.name, '书一');
    expect(books.single.bookUrl, 'https://example.com/b1');
    expect(await UserApi.getBookSelf('unknown-device'), isEmpty, reason: 'code != 0: an empty list, as the original');

    final two = await UserApi.newopenAuto2();
    expect(two.source, isNot(two.rss));
    await expectLater(UserApi.downloadBackup(await UserApi.getRss('dart-test-1')), throwsA(predicate((e) => '$e'.contains('404'))));
    await Sources.add({'bookSourceUrl': 'https://s.example', 'bookSourceName': '源S'});
    await RssSources.add({'sourceUrl': 'https://r.example', 'sourceName': '订阅R'});
    await AutoBackup.backupSources();
    await AutoBackup.backupRss();
    expect(await UserApi.downloadBackup(await UserApi.getSources('dart-test-1')), contains('https://s.example'));
    expect(await UserApi.downloadBackup(await UserApi.getRss('dart-test-1')), contains('https://r.example'));
    expect((await UserApi.getAutoDevices(2)).single.appid, 'dart-test-1');

    // removed from another device: the next start-up re-open fails and the switch goes off
    await UserApi.removeAutoDevice(1, 'dart-test-1');
    await UserSession.setSwitch(PrefKeys.autoSyncEnabled, true);
    await UserSession.setSwitch(PrefKeys.auto2SyncEnabled, true);
    Toast.log.clear();
    await AutoBackup.reopen();
    expect(UserSession.autoSyncEnabled, isFalse);
    expect(Toast.log, contains(startsWith('开启书架同步失败:')));
    expect(Toast.log, contains('开启书源同步成功'));
    await UserSession.setSwitch(PrefKeys.auto2SyncEnabled, false);
    AutoBackup.reset();
  }, skip: skip);

  test('profile: nickname, avatar, devices, cleanuser', () async {
    await UserApi.updateNickname('小达特');
    expect(UserSession.nickname, '小达特');
    final png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    final url = await UserApi.updateAvatar(png, 'a.png');
    expect(url, startsWith('$base/images/'));
    expect(UserSession.avatarUrl, url);
    final devices = await UserApi.getLoginDevices();
    expect(devices.map((d) => d.appid), contains('dart-test-1'));
    expect(devices.first.platform, isNotEmpty);
    await UserApi.cleanUser();
    expect(await UserApi.cloudList(CloudKind.books), '');
  }, skip: skip);

  test('self-check passes for a member (incl. cloud round trip) and the report reaches the server', () async {
    final results = await SelfCheck.run();
    expect(results.where((r) => !r.ok), isEmpty, reason: results.map((r) => '${r.name}: ${r.detail}').join(' | '));
    expect(results.map((r) => r.name), containsAll(['服务器连通', '账号信息 getUserInfo', '会员门槛 canOpenCloud', '云端读写 selfcheck']));
    final rep = await UserApi.diag(results);
    expect(rep['fail'], 0);
    expect(rep['ok'], results.length);
    // the admin CLI sees it
    expect(admin(['list-diag', '--limit', '1', '--full']), contains('云端读写 selfcheck'));
  }, skip: skip);

  test('check_update: no release -> no update; admin set-update with a newer build -> 发现新版本 data', () async {
    PackageInfo.setMockInitialValues(appName: 'a', packageName: 'p', version: '1.0.0', buildNumber: '3', buildSignature: '', installerStore: null);
    AboutPage.dio = null;
    expect((await AboutPage.checkUpdate()).hasUpdate, isFalse);
    final rel = File('${tmp.path}/release.json')
      ..writeAsStringSync(jsonEncode({'version': '1.0.1', 'build': 4, 'notes': '更新说明', 'url': 'https://example.invalid/4.ipa'}));
    expect(admin(['set-update', rel.path]), contains('build 4'));
    final u = await AboutPage.checkUpdate();
    expect(u.hasUpdate, isTrue);
    expect(u.updateUrl, 'https://example.invalid/4.ipa');
    expect(u.description, '更新说明');
    PackageInfo.setMockInitialValues(appName: 'a', packageName: 'p', version: '1.0.1', buildNumber: '4', buildSignature: '', installerStore: null);
    expect((await AboutPage.checkUpdate()).hasUpdate, isFalse, reason: 'the installed build is the release');
    admin(['set-update', '--clear']);
  }, skip: skip);

  test('password change ends the session: the old token is rejected with 登陆已过期', () async {
    await UserApi.changePassword('secret-pw', 'new-secret');
    Toast.log.clear();
    expect(await UserApi.getUserInfo(), isNull);
    expect(UserSession.isLoggedIn, isFalse, reason: 'NEED_LOGIN clears the local session');
    expect(Toast.log, contains('登陆已过期'));
    final info = await UserApi.login('dart@example.com', 'new-secret'); // e-mail login works
    await UserSession.apply(info);
    expect(UserSession.isvip, isTrue);
    await UserApi.logout();
    expect(UserSession.isLoggedIn, isFalse);
    expect(UserSession.tockenid, '');
  }, skip: skip);
}
