import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/userinfo.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Userinfo info({bool vip = false, String token = 'tok-1', String nick = ''}) =>
    Userinfo(username: 'alice', id: '7', tockenid: token, email: 'a@example.com', nickname: nick, avatarUrl: '', isvip: vip, vipExpire: vip ? '2030-01-01' : '');

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await UserSession.clear();
  });

  test('Userinfo reads the token from the `vip` key (docs/API.md) and falls back to nickname = username', () {
    final u = Userinfo.fromJson({'username': 'bob', 'id': 3, 'vip': 'T0K', 'isvip': true, 'avatar_url': 'x', 'nickname': '', 'email': 'b@x.io', 'vipExpire': '2031-02-03'});
    expect(u.tockenid, 'T0K');
    expect(u.id, '3');
    expect(u.isvip, isTrue);
    expect(u.nickname, 'bob');
    expect(u.vipExpire, '2031-02-03');
    expect(Userinfo.fromJson({'username': 'c', 'tockenid': 'ALIAS'}).tockenid, 'ALIAS');
    expect(Userinfo.fromJson({'username': 'c'}).isvip, isFalse);
  });

  test('apply copies the record, persists it under the original prefs keys, restore brings it back', () async {
    await UserSession.apply(info(vip: true, nick: '小A'));
    expect(UserSession.isLoggedIn, isTrue);
    expect(UserSession.tockenid, 'tok-1');
    expect(UserSession.nickname, '小A');
    expect(Storage.getString(PrefKeys.tockenid), 'tok-1');
    expect(Storage.getBool(PrefKeys.isvip), isTrue);
    expect(Storage.getString(PrefKeys.username), 'alice');

    UserSession.isLoggedIn = false;
    UserSession.tockenid = '';
    UserSession.isvip = false;
    await UserSession.restore();
    expect(UserSession.isLoggedIn, isTrue);
    expect(UserSession.tockenid, 'tok-1');
    expect(UserSession.isvip, isTrue);
  });

  test('non-members get the three member-only cloud switches forced off (applyUserinfo), members keep them', () async {
    await UserSession.apply(info(vip: true));
    await UserSession.setSwitch(PrefKeys.cloudtheme, true);
    await UserSession.setSwitch(PrefKeys.cloudmark, true);
    await UserSession.setSwitch(PrefKeys.cloudtts, true);
    await UserSession.setSwitch(PrefKeys.cloudbookself, true);
    await UserSession.apply(info(vip: true));
    expect([UserSession.cloudtheme, UserSession.cloudmark, UserSession.cloudtts], [true, true, true]);

    await UserSession.apply(info(vip: false)); // membership ended
    expect(UserSession.isvip, isFalse);
    expect([UserSession.cloudtheme, UserSession.cloudmark, UserSession.cloudtts], [false, false, false]);
    expect(Storage.getBool(PrefKeys.cloudmark), isFalse);
    expect(UserSession.cloudbookself, isTrue); // not one of the three
  });

  test('restore re-applies the rule when stale prefs still say a non-member has cloud switches on', () async {
    SharedPreferences.setMockInitialValues({'isLoggedIn': true, 'tockenid': 'x', 'isvip': false, 'cloudmark': true, 'cloudtts': true});
    await Storage.init();
    await UserSession.restore();
    expect(UserSession.cloudmark, isFalse);
    expect(UserSession.cloudtts, isFalse);
    expect(Storage.getBool(PrefKeys.cloudmark), isFalse);
  });

  test('a failed cloud call switches bookshelf and source sync off', () async {
    await UserSession.apply(info(vip: true));
    await UserSession.setSwitch(PrefKeys.cloudbookself, true);
    await UserSession.setSwitch(PrefKeys.cloudsource, true);
    await UserSession.disableCloudSync();
    expect([UserSession.cloudbookself, UserSession.cloudsource], [false, false]);
    expect(Storage.getBool(PrefKeys.cloudsource), isFalse);
  });

  test('clear ends the session and wipes every key', () async {
    await UserSession.apply(info(vip: true));
    await Storage.setString(PrefKeys.etag, 'e1');
    await UserSession.clear();
    expect(UserSession.isLoggedIn, isFalse);
    expect(UserSession.tockenid, '');
    expect(UserSession.isvip, isFalse);
    expect(Storage.getString(PrefKeys.tockenid), '');
    expect(Storage.getString(PrefKeys.etag), '');
    // a session with an empty token never restores as logged in
    await Storage.setBool(PrefKeys.isLoggedIn, true);
    await UserSession.restore();
    expect(UserSession.isLoggedIn, isFalse);
  });

  test('revision changes on every transition so pages rebuild', () async {
    final r0 = UserSession.revision.value;
    await UserSession.apply(info());
    expect(UserSession.revision.value, greaterThan(r0));
  });
}
