// 备份设置 / 恢复设置: the reading-setting prefs of the original key list go to cloud item `readitems` and come back.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/views/reader_host.dart';
import 'package:newread/pages/read/pages/novel/views/top_menu.dart';
import 'package:newread/read/setting/read_setting.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

class _Host implements ReaderHost {
  @override
  final ReadSetting setting = ReadSetting();
  int relayouts = 0;
  @override
  Future<void> relayout() async => relayouts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await newDevice();
    Toast.log.clear();
    Toast.sink = (_, _) {};
  });

  test('upload and restore through the item store', () async {
    final store = <String, String>{};
    TopMenuActions.uploadItem = (item, content) async => store[item] = content;
    TopMenuActions.downloadItem = (item) async => store[item] ?? '';
    final host = _Host();
    final ctx = _FakeContext();

    await TopMenuActions.restoreSetting(ctx, host);
    expect(Toast.log.last, '您还没有备份');

    await host.setting.setFontSize(24);
    await host.setting.setFan(42);
    await Storage.setString('notAReaderKey', 'x');
    await TopMenuActions.backupSetting(ctx, host);
    expect(Toast.log.last, '上传成功');
    final map = jsonDecode(store['readitems']!) as Map;
    expect(map['fontSizedefault'], '24');
    expect(map['fan'], '42');
    expect(map.containsKey('notAReaderKey'), isFalse);
    expect(readerBackupKeys, hasLength(80));

    await host.setting.setFontSize(40);
    await TopMenuActions.restoreSetting(ctx, host);
    expect(Toast.log.last, '恢复成功');
    expect(host.setting.fontSize, 24);
    expect(host.relayouts, 1);
  });
}

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
