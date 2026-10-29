// 编辑书架 guard (BookSelfN.cloudIsCurrent, original 0xf75494 `云端数据已更新请先刷新书架`): refused only when the cloud shelf is on,
// a user is signed in and the server says newer data exists; failures and switched-off sync never block.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/userapi.dart' show CloudKind;
import 'package:newread/data/bookself.dart';
import 'package:newread/data/user.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_cloud.dart';

void main() {
  late Directory tmp;
  late FakeCloud cloud;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qread_shelfcur_');
    SharedPreferences.setMockInitialValues({});
    await Storage.init(prefs: await SharedPreferences.getInstance(), root: tmp);
    cloud = FakeCloud();
    cloud.lists[CloudKind.books] = '[{"bookUrl":"u1"}]';
    UserSession.isLoggedIn = true;
    UserSession.cloudbookself = true;
  });

  tearDown(() {
    UserSession.isLoggedIn = false;
    UserSession.cloudbookself = false;
    tmp.deleteSync(recursive: true);
  });

  test('current etag → editable; stale etag → not; failure / switches off → editable without asking', () async {
    await Storage.setString(PrefKeys.etag, md5Of('[{"bookUrl":"u1"}]'));
    expect(await BookSelfN.cloudIsCurrent(api: cloud), isTrue);
    await Storage.setString(PrefKeys.etag, 'old');
    expect(await BookSelfN.cloudIsCurrent(api: cloud), isFalse);
    cloud.failUpdate = true;
    expect(await BookSelfN.cloudIsCurrent(api: cloud), isTrue);
    expect(cloud.updateCalls, 3);
    UserSession.cloudbookself = false;
    expect(await BookSelfN.cloudIsCurrent(api: cloud), isTrue);
    UserSession.cloudbookself = true;
    UserSession.isLoggedIn = false;
    expect(await BookSelfN.cloudIsCurrent(api: cloud), isTrue);
    expect(cloud.updateCalls, 3);
  });
}
