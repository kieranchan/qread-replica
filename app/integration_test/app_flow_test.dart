// End-to-end UI flow on a device / simulator against a real local server (started by the CI workflow):
//   signed out -> login page -> login (non-member) -> member-only cloud switch is gated -> activation code -> member
//   -> self-check page (cloud round trip) -> report -> 会员中心 page opens.
// Inputs come from --dart-define: QREAD_BASE_URL, QREAD_TEST_USER, QREAD_TEST_PASS, QREAD_TEST_VIPCODE.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:newread/api/userapi.dart';
import 'package:newread/data/user.dart';
import 'package:newread/main.dart' as app;

const testUser = String.fromEnvironment('QREAD_TEST_USER');
const testPass = String.fromEnvironment('QREAD_TEST_PASS');
const testVipCode = String.fromEnvironment('QREAD_TEST_VIPCODE');

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 150));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timed out waiting for $f');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('account and membership flow', (tester) async {
    expect(testUser, isNotEmpty, reason: 'pass --dart-define=QREAD_TEST_USER=...');

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('登录同步阅读数据'), findsOneWidget);
    await binding.takeScreenshot('01_me_signed_out');

    await tester.tap(find.byKey(const Key('me_account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login_go')), findsOneWidget);
    await binding.takeScreenshot('02_login');

    await tester.enterText(find.byKey(const Key('login_user')), testUser);
    await tester.enterText(find.byKey(const Key('login_pass')), testPass);
    await tester.pump();
    await tester.tap(find.byKey(const Key('login_go')));
    await pumpUntil(tester, find.text('非会员'));
    await tester.pumpAndSettle();
    expect(UserSession.isLoggedIn, isTrue);
    expect(UserSession.isvip, isFalse);
    await binding.takeScreenshot('03_me_non_member');

    // member-only switch: gated with the original's message, nothing turns on
    await tester.tap(find.byKey(const Key('me_cloud')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sw_cloudmark')));
    await pumpUntil(tester, find.text('此功能为会员功能'));
    expect(UserSession.cloudmark, isFalse);
    await binding.takeScreenshot('04_cloud_gate');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // become a member with an activation code (the 会员中心 page does the same through /redeem)
    await UserApi.redeem(testVipCode);
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(tester, find.textContaining('会员 · 到期'));
    expect(UserSession.isvip, isTrue);
    await binding.takeScreenshot('05_me_member');

    // the same switch now turns on
    await tester.tap(find.byKey(const Key('me_cloud')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sw_cloudmark')));
    await pumpUntil(tester, find.byWidgetPredicate((w) => w is SwitchListTile && w.key == const Key('sw_cloudmark') && w.value));
    expect(UserSession.cloudmark, isTrue);
    await binding.takeScreenshot('06_cloud_on');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // self-check with the cloud round trip, then report it to the server
    await tester.tap(find.byKey(const Key('me_self_check')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('全部通过'), timeout: const Duration(seconds: 40));
    await binding.takeScreenshot('07_self_check');
    await tester.tap(find.byKey(const Key('self_check_report')));
    await pumpUntil(tester, find.textContaining('已上报'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // the 会员中心 page opens in the in-app web view (the workflow checks the server log for the requests)
    await tester.tap(find.byKey(const Key('me_member')));
    await tester.pump(const Duration(seconds: 4));
    await binding.takeScreenshot('08_member_center');
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await binding.takeScreenshot('09_back_on_me');
  });
}
