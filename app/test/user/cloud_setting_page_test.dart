// 云端设置 (pages/user/cloud_setting_page.dart): the original's texts, switching on merges at once, 删除云端数据 only while the switch
// is off (and empties the kind's server items), 开始同步 runs every enabled kind and stamps 上次同步.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/userapi.dart' show CloudKind;
import 'package:newread/data/cloud_api.dart';
import 'package:newread/data/user.dart';
import 'package:newread/pages/user/cloud_setting_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_cloud.dart';

void main() {
  late Directory tmp;
  late FakeCloud cloud;
  final synced = <String>[];

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qread_cloudpage_');
    SharedPreferences.setMockInitialValues({});
    await Storage.init(prefs: await SharedPreferences.getInstance(), root: tmp);
    cloud = FakeCloud();
    defaultCloudApi = cloud;
    UserSession.isLoggedIn = true;
    UserSession.isvip = true;
    for (final k in [PrefKeys.cloudbookself, PrefKeys.cloudsource, PrefKeys.cloudmark, PrefKeys.cloudtheme, PrefKeys.cloudtts]) {
      await UserSession.setSwitch(k, false);
    }
    synced.clear();
    CloudSettingPage.canOpenCloud = () async => true;
    CloudSettingPage.syncOf = {for (final c in CloudSettingPage.kinds) c.key: () async => synced.add(c.key)};
    Toast.log.clear();
  });

  tearDown(() {
    UserSession.isLoggedIn = false;
    UserSession.isvip = false;
    defaultCloudApi = const UserApiCloud();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('texts, switch-on merge, delete cloud data, 开始同步', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CloudSettingPage()));
    await tester.pumpAndSettle();
    expect(find.text('启用云端书架'), findsOneWidget);
    expect(find.text('将书架放在云端以达到同账号下所有设备书架一致，如无需多端书架一致请勿开启'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('上次同步: 从未'), 200);
    expect(find.text('上次同步: 从未'), findsOneWidget);

    // 删除云端数据 while off: confirm → the kind's items are emptied
    await tester.scrollUntilVisible(find.byKey(const Key('del_${PrefKeys.cloudbookself}')), -200);
    await tester.tap(find.byKey(const Key('del_${PrefKeys.cloudbookself}')));
    await tester.pumpAndSettle();
    expect(find.text('确定要删除云端书架所有数据吗？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dialog_confirm')));
    await tester.pumpAndSettle();
    // FakeCloud files the five list kinds under `lists`
    expect(cloud.lists[CloudKind.books], '[]');
    expect(cloud.lists[CloudKind.groups], '[]');
    expect(Toast.log, contains('删除成功'));

    // switching on merges right away
    await tester.scrollUntilVisible(find.byKey(const Key('sw_${PrefKeys.cloudbookself}')), -200);
    await tester.tap(find.byKey(const Key('sw_${PrefKeys.cloudbookself}')));
    await tester.pumpAndSettle();
    expect(UserSession.cloudbookself, isTrue);
    expect(synced, [PrefKeys.cloudbookself]);
    expect(Toast.log, contains('正在合并云端书架'));

    // while on, the cloud data cannot be deleted
    await tester.scrollUntilVisible(find.byKey(const Key('del_${PrefKeys.cloudbookself}')), 200);
    await tester.tap(find.byKey(const Key('del_${PrefKeys.cloudbookself}')));
    await tester.pumpAndSettle();
    expect(Toast.log.last, '请先关闭云端书架');

    // 开始同步 runs the enabled kinds only and stamps the time
    synced.clear();
    await UserSession.setSwitch(PrefKeys.cloudtts, true);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('cloud_sync_now')), 200);
    await tester.tap(find.byKey(const Key('cloud_sync_now')));
    await tester.pumpAndSettle();
    expect(synced.toSet(), {PrefKeys.cloudbookself, PrefKeys.cloudtts});
    expect(Toast.log.last, '同步时间已更新');
    expect(CloudSettingPage.lastSync, isNotEmpty);
    expect(find.text('上次同步: 从未'), findsNothing);
  });
}
