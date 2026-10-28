// End-to-end UI flow on a device / simulator against a real local server (started by the CI workflow):
//   privacy agreement -> signed out -> login page -> login (non-member) -> member-only cloud switch is gated -> activation code
//   -> member -> self-check page (cloud round trip) -> report -> 会员中心 page opens
//   -> books on a demo site (integration_test/demo_site.dart): import source -> search -> detail -> add to shelf -> read, turn a
//      page, menus -> shelf -> the other tabs.
// Inputs come from --dart-define: QREAD_BASE_URL, QREAD_TEST_USER, QREAD_TEST_PASS, QREAD_TEST_VIPCODE.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:newread/api/userapi.dart';
import 'package:newread/common/nav.dart';
import 'package:newread/data/source.dart';
import 'package:newread/data/user.dart';
import 'package:newread/main.dart' as app;
import 'package:newread/pages/main_page.dart';

import 'demo_site.dart';

const testUser = String.fromEnvironment('QREAD_TEST_USER');
const testPass = String.fromEnvironment('QREAD_TEST_PASS');
const testVipCode = String.fromEnvironment('QREAD_TEST_VIPCODE');

/// Pumps frames for [d] without waiting for animations to settle (the reader and loaders keep animating).
Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 150));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('timed out waiting for $f');
}

/// Book-flow steps that did not reach their expected state; the flow keeps going (so every screenshot is taken) and fails at the end.
final List<String> softFailures = [];

Future<void> softUntil(WidgetTester t, Finder f, String step, {Duration timeout = const Duration(seconds: 25)}) async {
  try {
    await pumpUntil(t, f, timeout: timeout);
  } on TestFailure {
    softFailures.add(step);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('account and membership flow', (tester) async {
    expect(testUser, isNotEmpty, reason: 'pass --dart-define=QREAD_TEST_USER=...');

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // first launch: the privacy agreement of the original, then the app opens on 书架
    await pumpUntil(tester, find.byKey(const Key('privacy_dialog')));
    await binding.takeScreenshot('00_privacy');
    await tester.tap(find.byKey(const Key('privacy_agree')));
    await tester.pumpAndSettle();
    // then the 沉浸光感 choice of the original (asked once)
    await pumpUntil(tester, find.byKey(const Key('immersive_dialog')));
    await binding.takeScreenshot('00b_immersive_light');
    await tester.tap(find.byKey(const Key('immersive_2')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('immersive_ok')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('00_shelf_empty');
    await tester.tap(find.byKey(const Key('tab_我的')));
    await tester.pumpAndSettle();
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

    // ---- books: a demo book site inside the test process, its source imported like a user would paste it
    final site = await tester.runAsync(DemoSite.start);
    addTearDown(() => site!.close());
    await tester.runAsync(() => Sources.importJson(site!.sourceJson()));

    await tester.tap(find.byKey(const Key('tab_书架')));
    await pumpFor(tester, const Duration(seconds: 1));
    await binding.takeScreenshot('10_shelf_empty');

    final ctx = tester.element(find.byType(MainPage));
    unawaited(Nav.openSearch(ctx, key: '星河'));
    await softUntil(tester, find.text('星河旅人'), 'search result');
    await pumpFor(tester, const Duration(seconds: 1));
    await binding.takeScreenshot('11_search');

    if (find.text('星河旅人').evaluate().isNotEmpty) {
      await tester.tap(find.text('星河旅人').first);
      await softUntil(tester, find.byKey(const Key('detail_name')), 'detail page');
      await pumpFor(tester, const Duration(seconds: 3)); // book info + table of contents load
      await binding.takeScreenshot('12_book_detail');

      if (find.byKey(const Key('detail_add')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('detail_add')));
        // the original asks first: 加入书架 / 确定要将《…》加入书架吗？ (group choice, 确定)
        await softUntil(tester, find.byKey(const Key('add_ok')), 'add-to-shelf dialog');
        await pumpFor(tester, const Duration(milliseconds: 600));
        await binding.takeScreenshot('12b_add_to_shelf');
        if (find.byKey(const Key('add_ok')).evaluate().isNotEmpty) await tester.tap(find.byKey(const Key('add_ok')));
        await pumpFor(tester, const Duration(seconds: 1));
      }
      if (find.byKey(const Key('detail_read')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('detail_read')));
        // the reader paints the text itself (no Text widgets): wait for the chapter request instead
        final end = DateTime.now().add(const Duration(seconds: 30));
        while (!site!.requests.any((r) => r.startsWith('/chapter/1/1')) && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        if (!site.requests.any((r) => r.startsWith('/chapter/1/1'))) softFailures.add('chapter request');
        await pumpFor(tester, const Duration(seconds: 2));
        await binding.takeScreenshot('13_reader');

        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        await tester.tapAt(Offset(size.width * 0.85, size.height * 0.5)); // right third: next page
        await pumpFor(tester, const Duration(seconds: 2));
        await binding.takeScreenshot('14_reader_page2');
        await tester.tapAt(Offset(size.width * 0.5, size.height * 0.5)); // centre: menus
        await pumpFor(tester, const Duration(seconds: 2));
        await binding.takeScreenshot('15_reader_menu');
      } else {
        softFailures.add('read button');
      }
    }

    // back to the tabs: the book is on the shelf with its progress
    Get.until((route) => route.isFirst);
    await pumpFor(tester, const Duration(seconds: 2));
    await softUntil(tester, find.text('星河旅人'), 'book on the shelf');
    await binding.takeScreenshot('16_shelf_with_book');

    // 订阅 is hidden by default (as in the original); switch it on like the 底栏标签配置 sheet does
    await tester.runAsync(() => MainTabs.save(MainTabs.configured(), found: true, ding: true));
    await pumpFor(tester, const Duration(seconds: 1));
    for (final (tab, shot) in [('发现', '17_tab_discovery'), ('探索', '18_tab_explore'), ('订阅', '19_tab_rss')]) {
      await tester.tap(find.byKey(Key('tab_$tab')));
      await pumpFor(tester, const Duration(seconds: 3));
      await binding.takeScreenshot(shot);
    }
    // ---- a look at the settings pages (each opened through the same route names the 我的 page uses)
    await tester.tap(find.byKey(const Key('tab_我的')));
    await pumpFor(tester, const Duration(seconds: 1));
    final meCtx = tester.element(find.byType(MainPage));
    for (final (name, shot) in [
      ('read_setting_page', '20_read_settings'),
      ('source_page', '21_source_manager'),
      ('tts_setting', '22_tts_engines'),
      ('theme_manager', '23_themes'),
      ('icon_plaza_page', '24_icon_plaza'),
      ('backup_setting_page', '25_backup_settings'),
      ('reading_statistics_page', '26_statistics'),
      ('ai_model_page', '27_ai_models'),
      ('about_page', '28_about'),
    ]) {
      unawaited(Nav.openNamed(meCtx, name));
      await pumpFor(tester, const Duration(seconds: 2));
      await binding.takeScreenshot(shot);
      Get.until((route) => route.isFirst);
      await pumpFor(tester, const Duration(milliseconds: 800));
    }

    expect(softFailures, isEmpty, reason: 'book flow steps that failed');
  });
}
