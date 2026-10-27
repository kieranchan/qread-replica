// Widget tests of the extras pages: 「我的」 layout and keys, member gates for non-members (themes, network drive, SVG bubbles, local TTS),
// the AI model editor and check, settings dialogs, plus the reading statistics loader and hotkey rules.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/data/background_music_manager.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/data/fonts.dart';
import 'package:newread/data/ground.dart';
import 'package:newread/data/svg.dart';
import 'package:newread/data/theme.dart';
import 'package:newread/data/tts.dart';
import 'package:newread/data/user.dart';
import 'package:newread/data/webdav.dart';
import 'package:newread/models/ai_model_config.dart';
import 'package:newread/models/theme.dart';
import 'package:newread/models/userinfo.dart';
import 'package:newread/pages/me_page.dart';
import 'package:newread/pages/reading_statistics_page.dart';
import 'package:newread/pages/setting/ai_model_page.dart';
import 'package:newread/pages/setting/backup_page.dart';
import 'package:newread/pages/setting/choose_svg.dart';
import 'package:newread/pages/setting/clean_page.dart';
import 'package:newread/pages/setting/extras_routes.dart';
import 'package:newread/pages/setting/hotkey_setting_page.dart';
import 'package:newread/pages/setting/listem_setting_page.dart';
import 'package:newread/pages/setting/search_setting_page.dart';
import 'package:newread/pages/theme/font_setting_page.dart';
import 'package:newread/pages/theme/theme_api.dart';
import 'package:newread/pages/theme/theme_detail_page.dart';
import 'package:newread/pages/theme/theme_manager_page.dart';
import 'package:newread/pages/theme/theme_plaza_page.dart';
import 'package:newread/pages/tts/tts_setting.dart';
import 'package:newread/pages/webdav/webdav_manager_page.dart';
import 'package:newread/storage/book_reading_time_storage.dart';
import 'package:newread/storage/setting.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

Widget app(Widget home) => GetMaterialApp(home: home);

Future<void> signIn({required bool vip}) => UserSession.apply(Userinfo(
    username: 'alice', vip: vip ? '2030-01-01' : '', tockenid: 't', email: 'a@x.io', nickname: '艾丽丝', avatarUrl: '', isvip: vip));

/// Plaza client that answers from memory (no network inside widget tests).
class FakePlaza extends ThemePlazaApi {
  FakePlaza() : super(base: 'http://plaza.test/');
  static const PlazaTheme t7 = PlazaTheme(id: 7, name: '海盐', zipPath: 'public/files/7.zip', version: '2', themeMode: 'day', author: '');

  @override
  Future<PlazaPage> themes({int page = 1, int limit = 20, int categoryId = 0}) async => const PlazaPage([t7], page: 1, maxPage: 1);
  @override
  Future<List<ThemeCategory>> categories() async => const [ThemeCategory(1, '清新')];
  @override
  Future<PlazaTheme> theme(int id) async => t7;
  @override
  Future<Uint8List> download(String path, {void Function(double)? onProgress, dynamic cancelToken}) async => Uint8List(0);
}

void main() {
  late TestDevice dev;

  setUp(() async {
    dev = await newDevice();
    for (final load in [ThemeManager.load, TTSData.load, WebDav.load, Svg.load, FontsData.load, BackgroundMusicManager.load, Ground.load, Bookdata.load]) {
      await load();
    }
    Toast.log.clear();
    Toast.sink = (_, _) {};
    ThemePlazaPage.api = FakePlaza.new;
  });
  tearDown(() => dev.delete());

  group('「我的」', () {
    testWidgets('signed out: login prompts, the replica tiles near the top, and the original sections', (t) async {
      await t.pumpWidget(app(const MePage()));
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('登录同步阅读数据'), findsOneWidget);
      expect(find.text('登录同步阅读进度'), findsOneWidget);
      expect(find.byKey(const Key('me_member')), findsNothing);
      for (final k in ['me_account', 'me_cloud', 'me_self_check', 'me_theme']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.text('今日还没有读过书哦'), findsOneWidget);
      await t.scrollUntilVisible(find.text('关于我们'), 300);
      for (final s in ['书源管理', '朗读引擎', '网盘管理', '背景音乐', '阅读设置', '备份管理', '清除缓存', '关于我们', 'AI模型配置']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
    });

    testWidgets('member card: 立即开通 for non-members, 立即续费 / 会员中心 for members', (t) async {
      await signIn(vip: false);
      await t.pumpWidget(app(const MePage()));
      expect(find.text('立即开通'), findsOneWidget);
      expect(find.byKey(const Key('me_member')), findsOneWidget);
      await signIn(vip: true);
      await t.pump();
      expect(find.text('立即续费'), findsOneWidget);
      expect(find.textContaining('会员 · 到期 2030-01-01'), findsOneWidget);
    });

    testWidgets('theme button cycles prefs `dark`; daily goal dialog stores dailyReadingGoal', (t) async {
      await t.pumpWidget(app(const MePage()));
      await t.tap(find.byKey(const Key('me_dark')));
      await t.pump();
      expect(Storage.getString('dark'), isNot(''));
      await t.tap(find.byKey(const Key('me_goal')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('dialog_input')), '45');
      await t.tap(find.byKey(const Key('dialog_confirm')));
      await t.pumpAndSettle();
      expect(Storage.getString(MePage.dailyGoalKey), '45');
      expect(find.text('0/45 分钟'), findsOneWidget);
    });
  });

  group('member gates for non-members', () {
    setUp(() => signIn(vip: false));

    testWidgets('theme plaza detail: download and apply are member-only', (t) async {
      await t.runAsync(() => ThemeManager.install(ThemeModel(id: 'plaza_7', title: '海盐', version: '1', isLightMode: true)));
      await t.pumpWidget(app(ThemeDetailPage(theme: FakePlaza.t7, api: FakePlaza())));
      await t.pump();
      await t.scrollUntilVisible(find.byKey(const Key('theme_apply')), 200);
      expect(find.text('更新主题'), findsOneWidget); // installed version 1, plaza version 2
      await t.tap(find.byKey(const Key('theme_download')));
      await t.pump();
      expect(Toast.log, contains('仅会员允许下载主题'));
      await t.tap(find.byKey(const Key('theme_apply')));
      await t.pump();
      expect(Toast.log, contains('仅会员允许应用主题'));
      expect(Storage.getString('dayTheme'), '');
    });

    testWidgets('theme manager: create / import say 主题为会员功能！', (t) async {
      await t.pumpWidget(app(const ThemeManagerPage()));
      expect(find.text('暂无白天主题'), findsOneWidget);
      await t.tap(find.byKey(const Key('theme_create')));
      await t.pump();
      await t.tap(find.byKey(const Key('theme_import')));
      await t.pump();
      expect(Toast.log.where((m) => m == '主题为会员功能！').length, 2);
    });

    testWidgets('network drive: 网盘为会员独享功能！', (t) async {
      await t.pumpWidget(app(const WebDavManagerPage()));
      expect(find.text('暂无网盘账号'), findsOneWidget);
      await t.tap(find.byKey(const Key('wd_add')));
      await t.pump();
      expect(Toast.log, contains(WebDavManagerPage.vipText));
    });

    testWidgets('SVG bubbles: edit / import are member-only', (t) async {
      await t.pumpWidget(app(const ChooseSvgPage()));
      expect(find.text('暂无气泡'), findsOneWidget);
      await t.tap(find.byKey(const Key('svg_add')));
      await t.pump();
      await t.tap(find.byKey(const Key('svg_import')));
      await t.pump();
      expect(Toast.log, containsAll(['仅会员可编辑', '仅会员可导入']));
    });

    testWidgets('TTS: local engine gate; multi-role needs an AI model', (t) async {
      await t.pumpWidget(app(const TTsSetting()));
      expect(find.text('系统默认'), findsWidgets);
      await t.tap(find.byKey(const Key('tts_local')));
      await t.pump();
      expect(Toast.log, contains(TTsSetting.localGate));
      await t.tap(find.byKey(const Key('tts_add')));
      await t.pumpAndSettle();
      expect(find.text('请选择新建引擎类型'), findsOneWidget);
      for (final s in ['大声朗读', '中文角色', '火山引擎', 'MiMo引擎', '本地引擎']) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      await t.tap(find.byKey(const Key('tts_new_multiRole')));
      await t.pumpAndSettle();
      expect(Toast.log, contains('多角色引擎需要ai支持，请先配置ai接口'));
    });
  });

  testWidgets('members pass the local-engine gate and get the not-in-this-build message', (t) async {
    await signIn(vip: true);
    await t.pumpWidget(app(const TTsSetting()));
    await t.tap(find.byKey(const Key('tts_local')));
    await t.pump();
    expect(Toast.log, contains('当前版本不包含本地引擎（sherpa-onnx）'));
  });

  testWidgets('AI models: add through the editor, completions url rule, check hook', (t) async {
    AiModelPage.test = (m) async => m.model == 'bad' ? '检验失败: nope' : null;
    await t.pumpWidget(app(const AiModelPage()));
    await t.tap(find.byKey(const Key('ai_add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai_url')), 'https://api.example.com/v1');
    await t.tap(find.byKey(const Key('ai_ok')));
    await t.pumpAndSettle();
    expect(Toast.log.last, '接口地址必须以 completions 结尾');
    expect(Setting.getAiModels(), isEmpty);

    await t.tap(find.byKey(const Key('ai_add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai_name')), 'DeepSeek');
    await t.enterText(find.byKey(const Key('ai_url')), 'https://api.example.com/v1/chat/completions');
    await t.enterText(find.byKey(const Key('ai_key')), 'sk-12345678');
    await t.enterText(find.byKey(const Key('ai_model')), 'deepseek-chat');
    await t.tap(find.byKey(const Key('ai_ok')));
    await t.pumpAndSettle();
    final m = Setting.getAiModels().single;
    expect(m.name, 'DeepSeek');
    expect(m.isRoleAnalysis && m.isPurify, isTrue); // the first model becomes the default for both jobs
    expect(find.text('密钥：sk-1••••5678'), findsOneWidget);
    await t.tap(find.byKey(Key('ai_check_${m.id}')));
    await t.pumpAndSettle();
    expect(Toast.log, containsAllInOrder(['正在检验模型...', '检验成功，模型配置正常']));
    AiModelPage.test = (AiModelConfig c) async => null;
  });

  testWidgets('书源设置: thread counts are limited to 1 ~ 16', (t) async {
    await t.pumpWidget(app(const SeachSettingPage()));
    await t.scrollUntilVisible(find.byKey(const Key('ss_searchpppl')), 200);
    await t.tap(find.byKey(const Key('ss_searchpppl')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('dialog_input')), '20');
    await t.tap(find.byKey(const Key('dialog_confirm')));
    await t.pumpAndSettle();
    expect(Toast.log.last, '请输入 1 ~ 16 之间的整数');
    await t.tap(find.byKey(const Key('ss_searchpppl')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('dialog_input')), '8');
    await t.tap(find.byKey(const Key('dialog_confirm')));
    await t.pumpAndSettle();
    expect(Storage.getString('searchpppl'), '8');
  });

  testWidgets('听书设置 switches write allplay / canreadplay as text', (t) async {
    await t.pumpWidget(app(const ListenSettingPage()));
    await t.tap(find.byKey(const Key('listen_allplay')));
    await t.pump();
    await t.tap(find.byKey(const Key('listen_canreadplay')));
    await t.pump();
    expect(Storage.getString('allplay'), 'true');
    expect(Storage.getString('canreadplay'), 'false');
  });

  testWidgets('主题设置 shows the day / night slots and opens the plaza', (t) async {
    await t.pumpWidget(app(const FontSettingPage()));
    expect(find.text('日间模式'), findsOneWidget);
    expect(find.text('夜间模式'), findsOneWidget);
    expect(find.text('未选择'), findsNWidgets(2));
    await t.tap(find.byKey(const Key('fs_plaza')));
    await t.pumpAndSettle();
    expect(find.text('主题广场'), findsOneWidget);
    expect(find.byKey(const Key('plaza_7')), findsOneWidget);
    expect(find.text('匿名'), findsOneWidget);
  });

  testWidgets('backup and clean pages render their sections', (t) async {
    await t.pumpWidget(app(const BackupPage()));
    expect(find.text('快速备份'), findsOneWidget);
    expect(find.text('完整备份'), findsOneWidget);
    expect(find.text('暂无备份历史'), findsOneWidget);
    await t.pumpWidget(app(const CleanPage()));
    await t.pump();
    expect(find.text('总缓存大小'), findsOneWidget);
    expect(find.byKey(const Key('clean_图片缓存')), findsOneWidget);
    await t.scrollUntilVisible(find.text('恢复出厂设置'), 200);
    expect(find.text('恢复出厂设置'), findsOneWidget);
  });

  testWidgets('extras routes resolve their names and refuse foreign ones', (t) async {
    await t.pumpWidget(app(const Scaffold(body: SizedBox())));
    final ctx = t.element(find.byType(Scaffold));
    expect(await ExtrasRoutes.open(ctx, 'source_page'), isFalse);
    expect(ExtrasRoutes.pages.keys, containsAll(['tts_setting', 'theme_manager', 'webdav_page', 'ai_model_page', 'reading_statistics_page']));
    ExtrasRoutes.open(ctx, 'about_page');
    await t.pumpAndSettle();
    expect(find.text('关于轻悦时光'), findsOneWidget);
  });

  test('reading statistics: total, books in progress and the 30-day series', () async {
    final today = DateTime(2026, 10, 28);
    await BookReadingTimeStorage.addReading('book-a', 600, day: today);
    await BookReadingTimeStorage.addReading('book-b', 1200, day: today.subtract(const Duration(days: 3)));
    await BookReadingTimeStorage.addReading('book-a', 60, day: today.subtract(const Duration(days: 40)));
    final s = await ReadingStats.load(today: today);
    expect(s.totalSeconds, 1860);
    expect(s.books, 2);
    expect(s.days.length, 30);
    expect(s.days.last.$2, 600);
    expect(s.days[26].$2, 1200);
    expect(formatDuration(1860), '31分钟');
    expect(formatDuration(3900), '1小时5分钟');
  });

  test('hotkeys: defaults, duplicates refused, allowed key names', () async {
    expect(HotkeySettingPage.get('hotkeyNextPage'), 'arrowright');
    expect(await HotkeySettingPage.assign('hotkeyNextPage', 'f9'), '"f9" 已被其他快捷键占用');
    expect(await HotkeySettingPage.assign('hotkeyNextPage', 'd'), '快捷键已更新：d');
    expect(HotkeySettingPage.get('hotkeyNextPage'), 'd');
  });

  test('BookSelfN stays usable for the recent-reading row', () => expect(BookSelfN.books, isEmpty));
}
