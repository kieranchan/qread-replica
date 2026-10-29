// pages/theme/theme_update_check.dart — the start-up theme update notice of the original (main_page 0x8e8438: `当前主题有新版本可用`).
// A theme installed from the plaza keeps the id `plaza_<id>` and the plaza version; at start-up the plaza is asked for that id and a
// different version is announced. Never blocks start-up: errors are only logged.
import 'package:flutter/foundation.dart';

import '../../models/theme.dart';
import '../../theme/theme_provider.dart';
import '../../util/toast.dart';
import 'theme_api.dart';

abstract class ThemeUpdateCheck {
  static const String prefix = 'plaza_';

  /// Fetches a plaza theme by id (tests replace it).
  static Future<PlazaTheme> Function(int id) fetch = (id) => ThemePlazaApi().theme(id);

  static int? plazaId(ThemeModel t) => t.id.startsWith(prefix) ? int.tryParse(t.id.substring(prefix.length)) : null;

  /// The newer plaza version of [theme] (the current one by default), or null when it is not a plaza theme or is up to date.
  static Future<String?> check({ThemeModel? theme}) async {
    final t = theme ?? ThemeProvider.instance.current;
    if (t == null) return null;
    final id = plazaId(t);
    if (id == null) return null;
    final remote = await fetch(id);
    if (remote.version.isEmpty || remote.version == t.version) return null;
    return remote.version;
  }

  /// Start-up: `当前主题有新版本可用` when the plaza has a newer version of the theme in use.
  static Future<void> notify() async {
    try {
      final v = await check();
      if (v != null) Toast.show('当前主题有新版本可用');
    } catch (e) {
      debugPrint('主题更新检查失败: $e');
    }
  }
}
