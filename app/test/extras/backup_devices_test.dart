// 备份设置 + the backup-device dialog + 备份导入 against a fake server (a Dio adapter answering like ../server): switching the
// bookshelf backup on registers the device (openAuto), 立即备份 PUTs the shelf, the dialog lists / removes devices, imports a
// source backup (404 = 此设备书源备份为空) and opens BackbookPage for a bookshelf device.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/api/userapi.dart';
import 'package:newread/common/common.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/data/cloud/auto_backup.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/userinfo.dart';
import 'package:newread/pages/search/backbook_page.dart';
import 'package:newread/pages/user/auto_device_management_dialog.dart';
import 'package:newread/pages/user/backup_setting_page.dart';
import 'package:newread/qread/http.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

/// A tiny in-memory replica of the server's backup endpoints.
class FakeServer implements HttpClientAdapter {
  final calls = <String>[];
  final devices = <String, List<Map<String, String>>>{'1': [], '2': []};
  final blobs = <String, String>{};

  ResponseBody _json(Object o, [int status = 200]) =>
      ResponseBody.fromBytes(utf8.encode(jsonEncode(o)), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = o.uri.path;
    if (path.startsWith('/autobackup/')) {
      final key = path.substring('/autobackup/'.length);
      if (o.method == 'PUT') {
        calls.add('PUT $key');
        blobs[key] = o.data is String ? o.data as String : utf8.decode(o.data as List<int>);
        return _json({'code': 0});
      }
      calls.add('GET $key');
      final b = blobs[key];
      return b == null ? _json({'code': 404}, 404) : ResponseBody.fromBytes(utf8.encode(b), 200);
    }
    final name = path.substring(1);
    final p = Map<String, dynamic>.from(o.data as Map);
    calls.add('$name ${p['st'] ?? ''}'.trim());
    final appid = '${p['appid'] ?? ''}';
    switch (name) {
      case 'openAuto':
        if (devices['1']!.every((d) => d['appid'] != appid)) devices['1']!.add({'appid': appid, 'platform': 'ios', 'model': 'iPhone'});
        return _json({'code': 0, 'data': 'http://fake.test/autobackup/books-$appid'});
      case 'newopenAuto2':
        return _json({'code': 0, 'data': {'source': 'http://fake.test/autobackup/src-$appid', 'rss': 'http://fake.test/autobackup/rss-$appid'}});
      case 'getAutoDevice':
        return _json({'code': 0, 'data': devices['1']});
      case 'getAuto2Device':
        return _json({'code': 0, 'data': devices['2']});
      case 'removeAutoDevice':
        devices['1']!.removeWhere((d) => d['appid'] == appid);
        return _json({'code': 0});
      case 'getBookSelf':
        return _json({'code': 0, 'data': 'http://fake.test/autobackup/books-$appid'});
      case 'getSources':
        return _json({'code': 0, 'data': 'http://fake.test/autobackup/src-$appid'});
      case 'getRss':
        return _json({'code': 0, 'data': 'http://fake.test/autobackup/rss-$appid'});
    }
    return _json({'code': -1, 'errorMsg': 'unsupported $name'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

Future<void> signIn({required bool vip}) => UserSession.apply(Userinfo(
    username: 'alice', vip: vip ? '2030-01-01' : '', tockenid: 't', email: 'a@x.io', nickname: 'a', avatarUrl: '', isvip: vip));

void main() {
  late TestDevice dev;
  late FakeServer server;
  late HttpClientAdapter oldAdapter;

  setUp(() async {
    dev = await newDevice();
    Toast.log.clear();
    Toast.sink = (_, _) {};
    server = FakeServer();
    oldAdapter = QHttp.dio.httpClientAdapter;
    QHttp.dio.httpClientAdapter = server;
    Common.apiBase = 'http://fake.test/';
    Common.appid = 'phone-1';
    AutoBackup.reset();
    Bookdata.autoSync = false;
    await Bookdata.load();
  });
  tearDown(() {
    QHttp.dio.httpClientAdapter = oldAdapter;
    AutoBackup.reset();
    dev.delete();
  });

  testWidgets('书架备份: switching on registers the device (st 0), offers a first upload, 立即备份 PUTs the shelf', (t) async {
    await signIn(vip: false);
    Bookdata.books.add(Book(name: '书一', author: '某', bookUrl: 'https://x/1'));
    await t.pumpWidget(GetMaterialApp(home: const BackupSettingPage()));
    expect(find.text(BackupSettingPage.freeNote), findsOneWidget);
    await t.tap(find.byKey(const Key('bs_books')));
    await t.pumpAndSettle();
    expect(find.text('是否立即同步一次？'), findsOneWidget);
    await t.tap(find.byKey(const Key('dialog_confirm')));
    await t.pumpAndSettle();
    expect(UserSession.autoSyncEnabled, isTrue);
    expect(Storage.getBool(PrefKeys.autoSyncEnabled), isTrue);
    expect(server.calls, ['openAuto 0', 'PUT books-phone-1']);
    expect(jsonDecode(server.blobs['books-phone-1']!)[0]['name'], '书一');
    expect(Toast.log, contains('同步完成'));
    expect(find.textContaining('上次备份：20'), findsOneWidget);
    // 书源备份 is a member feature
    await t.tap(find.byKey(const Key('bs_sources')));
    await t.pump();
    expect(Toast.log, contains('书源备份是会员功能。'));
    expect(UserSession.auto2SyncEnabled, isFalse);
  });

  testWidgets('书架备份 is refused while 云端书架 is on; 立即备份 needs the switch', (t) async {
    await signIn(vip: true);
    await UserSession.setSwitch(PrefKeys.cloudbookself, true);
    await t.pumpWidget(GetMaterialApp(home: const BackupSettingPage()));
    await t.tap(find.byKey(const Key('bs_books')));
    await t.pump();
    expect(Toast.log, contains('书架备份无法和云端书架同时打开'));
    await t.tap(find.byKey(const Key('bs_books_now')));
    await t.pump();
    expect(Toast.log, contains('请先开启备份'));
    expect(server.calls, isEmpty);
  });

  testWidgets('source backup for members: newopenAuto2, both lists uploaded', (t) async {
    await signIn(vip: true);
    await t.pumpWidget(GetMaterialApp(home: const BackupSettingPage()));
    await t.tap(find.byKey(const Key('bs_sources')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('dialog_confirm')));
    await t.pumpAndSettle();
    expect(server.calls, ['newopenAuto2 0', 'PUT src-phone-1', 'PUT rss-phone-1']);
    expect(Storage.getString(PrefKeys.lastSyncTime2), isNotEmpty);
    expect(Storage.getString(PrefKeys.lastSyncTimer3), isNotEmpty);
  });

  testWidgets('device dialog: empty hint, list, remove; a bookshelf device opens BackbookPage with its books', (t) async {
    await signIn(vip: false);
    await t.pumpWidget(GetMaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => BackbookPage.open(c), child: const Text('备份导入')))));
    await t.tap(find.text('备份导入'));
    await t.pumpAndSettle();
    expect(find.text('暂无设备'), findsOneWidget);
    expect(find.text('在书架同步页面开启自动同步功能\n以添加备份设备'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();

    server.devices['1']!
      ..add({'appid': 'pad-2', 'platform': 'ios', 'model': 'iPad'})
      ..add({'appid': 'old-3', 'platform': 'ios', 'model': ''});
    server.blobs['books-pad-2'] = jsonEncode([Book(name: '平板上的书', author: '甲', bookUrl: 'https://x/pad').toJson()]);
    await t.tap(find.text('备份导入'));
    await t.pumpAndSettle();
    expect(find.text('书架备份'), findsOneWidget);
    expect(find.text('管理或者查看你的书架备份'), findsOneWidget);
    expect(find.text('未知设备'), findsOneWidget);
    await t.tap(find.byKey(const Key('adm_remove_old-3')));
    await t.pumpAndSettle();
    expect(find.text('确定要从书架备份中移除 未知设备 设备吗？'), findsOneWidget);
    await t.tap(find.byKey(const Key('dialog_confirm')));
    await t.pumpAndSettle();
    expect(Toast.log, contains('已移除 未知设备'));
    expect(find.text('未知设备'), findsNothing);
    await t.tap(find.byKey(const Key('adm_device_pad-2')));
    await t.pumpAndSettle();
    expect(find.byType(BackbookPage), findsOneWidget);
    expect(find.text('平板上的书'), findsWidgets);
    expect(server.calls, containsAllInOrder(['getBookSelf', 'GET books-pad-2']));
  });

  testWidgets('source device: 请选择类型 → import the sources; an empty RSS backup says 此设备订阅源备份为空', (t) async {
    await signIn(vip: true);
    server.devices['2']!.add({'appid': 'pad-2', 'platform': 'ios', 'model': 'iPad'});
    server.blobs['src-pad-2'] = jsonEncode([
      {'bookSourceUrl': 'https://s.example', 'bookSourceName': '源S'},
    ]);
    final imported = <String>[];
    final old = AutoDeviceManagementDialog.importBackup;
    AutoDeviceManagementDialog.importBackup = (text, {required rss}) async {
      imported.add('${rss ? 'rss' : 'source'}:$text');
      return '导入完成';
    };
    addTearDown(() => AutoDeviceManagementDialog.importBackup = old);
    await t.pumpWidget(GetMaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => AutoDeviceManagementDialog.show(c, isSource: true), child: const Text('open')))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('管理或者查看你的书源备份'), findsOneWidget);
    await t.tap(find.byKey(const Key('adm_device_pad-2')));
    await t.pumpAndSettle();
    expect(find.text('请选择类型'), findsOneWidget);
    await t.tap(find.byKey(const Key('adm_type_source')));
    await t.pumpAndSettle();
    expect(imported.single, startsWith('source:[{"bookSourceUrl":"https://s.example"'));
    expect(Toast.log, contains('导入完成'));
    await t.tap(find.byKey(const Key('adm_device_pad-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('adm_type_rss')));
    await t.pumpAndSettle();
    expect(Toast.log, contains('此设备订阅源备份为空'));
  });

  test('scheduleBooks: only with the switch on, a known url and 云端书架 off; uploads after the delay', () async {
    await signIn(vip: false);
    AutoBackup.delay = const Duration(milliseconds: 10);
    addTearDown(() => AutoBackup.delay = const Duration(seconds: 10));
    AutoBackup.scheduleBooks();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(server.calls, isEmpty);
    await UserSession.setSwitch(PrefKeys.autoSyncEnabled, true);
    await UserApi.openAuto();
    Bookdata.books.add(Book(name: '书二', bookUrl: 'https://x/2'));
    AutoBackup.scheduleBooks();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(server.calls, ['openAuto 0', 'PUT books-phone-1']);
  });
}
