// pages/setting/extras_routes.dart — the route names of the extras area for `Nav.openNamed` (common/nav.dart). The lead chains
// [ExtrasRoutes.open] into `Nav.openNamed`: `if (await ExtrasRoutes.open(context, name, arguments: arguments)) return;`.
// Names are the original file stems (plus the short aliases docs/PORTING.md lists: `theme_manager`, `webdav_page`).
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../about_page.dart';
import '../background_manager_page.dart';
import '../fonts/fouts_setting.dart';
import '../me_page.dart';
import '../reading_statistics_page.dart';
import '../theme/font_setting_page.dart';
import '../theme/icon_plaza_page.dart';
import '../theme/new_theme_page.dart';
import '../theme/theme_manager_page.dart';
import '../theme/theme_plaza_page.dart';
import '../tts/dialogue_line_edit_page.dart';
import '../tts/multi_role_edit.dart';
import '../tts/tts_edit.dart';
import '../tts/tts_setting.dart';
import '../user/backup_setting_page.dart';
import '../user/cloud_setting_page.dart';
import '../user/security_privacy_page.dart';
import '../user/user_setting_page.dart';
import '../webdav/webdav_manager_page.dart';
import '../wifi_page.dart';
import 'ai_model_page.dart';
import 'background_music_page.dart';
import 'backup_page.dart';
import 'choose_svg.dart';
import 'clean_page.dart';
import 'hotkey_setting_page.dart';
import 'listem_setting_page.dart';
import 'search_setting_page.dart';
import 'user_ys.dart';

abstract class ExtrasRoutes {
  static T? _arg<T>(Object? arguments, String key) => arguments is Map && arguments[key] is T ? arguments[key] as T : null;

  /// name → page builder (arguments: a `Map<String, Object?>` where a page takes parameters).
  static final Map<String, Widget Function(Object? arguments)> pages = {
    'me_page': (_) => const MePage(),
    'ai_model_page': (_) => const AiModelPage(),
    'background_music_page': (_) => const BackgroundMusicPage(),
    'backup_page': (_) => const BackupPage(),
    'choose_svg': (a) => ChooseSvgPage(svg: _arg<String>(a, 'svg') ?? ''),
    'clean_page': (_) => const CleanPage(),
    'hotkey_setting_page': (_) => const HotkeySettingPage(),
    'listem_setting_page': (_) => const ListenSettingPage(),
    'search_setting_page': (_) => const SeachSettingPage(),
    'user_ys': (a) => UserAgreementPage(title: _arg<String>(a, 'title') ?? '免责声明'),
    'theme_manager': (a) => ThemeManagerPage(isLight: _arg<bool>(a, 'isLight') ?? true),
    'theme_manager_page': (a) => ThemeManagerPage(isLight: _arg<bool>(a, 'isLight') ?? true),
    'theme_plaza_page': (_) => const ThemePlazaPage(),
    'font_setting_page': (_) => const FontSettingPage(),
    'icon_plaza_page': (_) => const IconPlazaPage(),
    'new_theme_page': (a) => NewThemePage(isLight: _arg<bool>(a, 'isLight') ?? true),
    'fouts_setting': (_) => const FontsSetting(),
    'tts_setting': (_) => const TTsSetting(),
    'tts_edit': (_) => const EditTts(),
    'multi_role_edit': (a) => MultiRoleEdit(bookUrl: _arg<String>(a, 'bookUrl') ?? '', bookKey: _arg<String>(a, 'bookKey') ?? ''),
    'dialogue_line_edit_page': (a) => DialogueLineEditPage(
          loadLines: _arg<Future<Map<String, String>> Function(int)>(a, 'loadLines') ?? (_) async => <String, String>{},
          chapterCount: _arg<int>(a, 'chapterCount') ?? 1,
          initialChapter: _arg<int>(a, 'initialChapter') ?? 0,
          cacheKey: _arg<String>(a, 'cacheKey') ?? '',
        ),
    'webdav_page': (_) => const WebDavManagerPage(),
    'webdav_manager_page': (_) => const WebDavManagerPage(),
    'reading_statistics_page': (_) => const ReadingStatisticsPage(),
    'about_page': (_) => const AboutPage(),
    'background_manager_page': (_) => const BackgroundManagerPage(),
    'wifi_page': (_) => const WiFiPage(),
    'user_setting_page': (_) => const UserSettingPage(),
    'cloud_setting_page': (_) => const CloudSettingPage(),
    'backup_setting_page': (_) => const BackupSettingPage(),
    'security_privacy_page': (_) => const SecurityPrivacyPage(),
  };

  /// Opens [name] when it belongs to this area; false otherwise (the caller falls through to the other areas).
  static Future<bool> open(BuildContext context, String name, {Object? arguments}) async {
    final b = pages[name];
    if (b == null) return false;
    await Get.to(() => b(arguments));
    return true;
  }
}
