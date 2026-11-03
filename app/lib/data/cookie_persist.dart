// data/cookie_persist.dart — keeps the engine's cookie store across launches. The original holds its cookies in dio's
// `PersistCookieJar` on disk; the replica's [CookieStore] (every source request, the login web page's cookies) only lived in memory,
// so each time iOS ended the process (memory pressure, a swipe-away, a reboot) every source login was gone and the source asked the
// owner to log in again (2026-11-03: "我明明已经登陆过了，但是偶尔又会需要我登录").
import 'dart:async';
import 'dart:convert';

import '../storage/storage.dart';
import '../util/legado/cookie_jar.dart';

abstract class CookiePersist {
  static const String key = 'cookieStore';

  /// Loads the saved cookies into [CookieStore] and writes the store back on every change.
  static Future<void> init() async {
    final raw = Storage.getString(key);
    if (raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw);
        if (m is Map) CookieStore.load({for (final e in m.entries) '${e.key}': '${e.value}'});
      } catch (_) {
        // a damaged record: start empty, the next change overwrites it
      }
    }
    CookieStore.onSave = (_, _) => unawaited(flush());
    CookieStore.onRemove = (_) => unawaited(flush());
  }

  /// Writes the whole store (a few domains, a few KB).
  static Future<void> flush() => Storage.setString(key, jsonEncode(CookieStore.all));
}
