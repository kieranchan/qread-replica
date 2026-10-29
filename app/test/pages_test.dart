import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/userinfo.dart';
import 'package:newread/pages/login_page.dart';
import 'package:newread/pages/me_page.dart';
import 'package:newread/pages/user/cloud_setting_page.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget home) => GetMaterialApp(home: home);

Future<void> signIn({required bool vip}) => UserSession.apply(Userinfo(
    username: 'alice', vip: vip ? '2030-01-01' : '', tockenid: 't', email: 'a@x.io', nickname: '艾丽丝', avatarUrl: '', isvip: vip));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    await UserSession.clear();
    Toast.log.clear();
  });

  testWidgets('「我的」 shows the login prompt when signed out and hides the 会员中心 entry', (t) async {
    await t.pumpWidget(app(const MePage()));
    expect(find.text('登录同步阅读数据'), findsOneWidget);
    expect(find.byKey(const Key('me_member')), findsNothing);
  });

  testWidgets('「我的」 for a non-member offers 立即开通; for a member shows the expiry', (t) async {
    await signIn(vip: false);
    await t.pumpWidget(app(const MePage()));
    expect(find.text('艾丽丝'), findsOneWidget);
    expect(find.text('非会员'), findsOneWidget);
    expect(find.text('立即开通'), findsOneWidget);

    await signIn(vip: true);
    await t.pump();
    expect(find.textContaining('会员 · 到期 2030-01-01'), findsOneWidget);
    expect(find.text('立即开通'), findsNothing);
  });

  testWidgets('cloud switches are member-only: a non-member only gets the toast, nothing is turned on', (t) async {
    await signIn(vip: false);
    await t.pumpWidget(app(const CloudSettingPage()));
    await t.scrollUntilVisible(find.byKey(Key('sw_${PrefKeys.cloudmark}')), 200);
    await t.tap(find.byKey(Key('sw_${PrefKeys.cloudmark}')));
    await t.pump();
    expect(Toast.log, contains('此功能为会员功能'));
    expect(UserSession.cloudmark, isFalse);
    expect(Storage.getBool(PrefKeys.cloudmark), isFalse);
  });

  testWidgets('login page validates empty input before calling the server', (t) async {
    await t.pumpWidget(app(const LoginPage()));
    await t.tap(find.byKey(const Key('login_go')));
    await t.pump();
    expect(Toast.log.last, '请输入用户名或邮箱');
    await t.enterText(find.byKey(const Key('login_user')), 'alice');
    await t.tap(find.byKey(const Key('login_go')));
    await t.pump();
    expect(Toast.log.last, '请输入密码');
  });
}
