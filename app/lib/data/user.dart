// data/user.dart — the signed-in session: the statics the whole app reads (token, appid, VIP flag, sync switches), their
// persistence under the original SharedPreferences keys, and the three transitions recovered from the original:
//   applyUserinfo (0xf64ebc)  restore from prefs (0x11284a8)  logout/clear (0x10487c4)
//
// The VIP flag is the single bool every member-only feature checks (487 reads in the original); there is no client-side
// expiry logic: membership is whatever the server last said.
import 'package:flutter/foundation.dart' show ValueNotifier;

import '../api/userapi.dart';
import '../models/userinfo.dart';
import '../storage/storage.dart';

/// SharedPreferences keys of the original (docs/STORAGE.md).
abstract class PrefKeys {
  static const isLoggedIn = 'isLoggedIn';
  static const username = 'username';
  static const tockenid = 'tockenid';
  static const autoSyncEnabled = 'autoSyncEnabled';
  static const auto2SyncEnabled = 'auto2SyncEnabled';
  static const autoSyncProgressEnabled = 'autoSyncProgressEnabled';
  static const lastSyncTime = 'lastSyncTime';
  static const lastSyncTime2 = 'lastSyncTime2';
  static const lastSyncTimer3 = 'lastSyncTimer3';
  static const cloudbookself = 'cloudbookself';
  static const cloudsource = 'cloudsource';
  static const etag = 'etag';
  static const grouptag = 'grouptag';
  static const bjetag = 'bjetag';
  static const rsstag = 'rsstag';
  static const sourcetag = 'sourcetag';
  static const isvip = 'isvip';
  static const cloudtheme = 'cloudtheme';
  static const cloudmark = 'cloudmark';
  static const groundmd5 = 'groundmd5';
  static const svgmd5 = 'svgmd5';
  static const markmd5 = 'markmd5';
  static const cloudtts = 'cloudtts';
  static const ttsmd5 = 'ttsmd5';
  static const email = 'email';
  static const nickname = 'nickname';
  static const avatarUrl = 'avatar_url';
  // not in the original (its vip text is a static refreshed by getUserInfo): the replica persists it for offline display
  static const vipText = 'vipText';
}

abstract class UserSession {
  static bool isLoggedIn = false;
  static String username = '';
  static String tockenid = '';
  static String email = '';
  static String nickname = '';
  static String avatarUrl = '';
  /// JSON `vip`: membership text (`永久`, a date or empty); static 0x1f90 in the original.
  static String vipText = '';

  /// Text for the account lines: `会员 · 永久` / `会员 · 到期 2030-01-01` / `非会员`.
  static String get vipLabel => !isvip ? '非会员' : (vipText.contains('永久') ? '会员 · 永久' : '会员 · 到期 $vipText');

  /// The VIP flag.
  static bool isvip = false;

  // Sync switches. Which static is which prefs key is an inference (docs/API.md): the three the original forces off for
  // non-members are the "cloud theme / bookmarks / tts" switches; the two a failed bookshelf/source sync turns off are
  // "cloud bookshelf / cloud source".
  static bool autoSyncEnabled = false;
  static bool auto2SyncEnabled = false;
  static bool autoSyncProgressEnabled = false;
  static bool cloudbookself = false;
  static bool cloudsource = false;
  static bool cloudtheme = false;
  static bool cloudmark = false;
  static bool cloudtts = false;

  /// Bumped whenever the session changes (login, refresh, logout, switches); pages listen to rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _notify() => revision.value++;

  /// applyUserinfo: copy the record into the statics, switch member-only cloud flags off for non-members, persist.
  static Future<void> apply(Userinfo u) async {
    isLoggedIn = true;
    username = u.username;
    tockenid = u.tockenid;
    email = u.email;
    nickname = u.nickname.isEmpty ? u.username : u.nickname;
    avatarUrl = u.avatarUrl;
    isvip = u.isvip;
    vipText = u.vip;
    await _save();
    await enforceMembership();
    _notify();
  }

  /// `if (!isvip && flag) { flag = false; persist }` for the three member-only cloud switches.
  static Future<void> enforceMembership() async {
    if (isvip) return;
    if (cloudtheme) {
      cloudtheme = false;
      await Storage.setBool(PrefKeys.cloudtheme, false);
    }
    if (cloudmark) {
      cloudmark = false;
      await Storage.setBool(PrefKeys.cloudmark, false);
    }
    if (cloudtts) {
      cloudtts = false;
      await Storage.setBool(PrefKeys.cloudtts, false);
    }
  }

  /// A cloud call failed: the original switches the bookshelf/source sync flags off (and shows the error).
  static Future<void> disableCloudSync() async {
    cloudbookself = false;
    cloudsource = false;
    await Storage.setBool(PrefKeys.cloudbookself, false);
    await Storage.setBool(PrefKeys.cloudsource, false);
    _notify();
  }

  static Future<void> setSwitch(String key, bool value) async {
    switch (key) {
      case PrefKeys.cloudbookself:
        cloudbookself = value;
      case PrefKeys.cloudsource:
        cloudsource = value;
      case PrefKeys.cloudtheme:
        cloudtheme = value;
      case PrefKeys.cloudmark:
        cloudmark = value;
      case PrefKeys.cloudtts:
        cloudtts = value;
      case PrefKeys.autoSyncEnabled:
        autoSyncEnabled = value;
      case PrefKeys.auto2SyncEnabled:
        auto2SyncEnabled = value;
      case PrefKeys.autoSyncProgressEnabled:
        autoSyncProgressEnabled = value;
      default:
        throw ArgumentError('unknown switch $key');
    }
    await Storage.setBool(key, value);
    _notify();
  }

  static Future<void> _save() async {
    await Storage.setBool(PrefKeys.isLoggedIn, isLoggedIn);
    await Storage.setString(PrefKeys.username, username);
    await Storage.setString(PrefKeys.tockenid, tockenid);
    await Storage.setBool(PrefKeys.isvip, isvip);
    await Storage.setString(PrefKeys.email, email);
    await Storage.setString(PrefKeys.nickname, nickname);
    await Storage.setString(PrefKeys.avatarUrl, avatarUrl);
    await Storage.setString(PrefKeys.vipText, vipText);
  }

  /// Restore from prefs at start-up (0x11284a8), then re-apply the membership rule.
  static Future<void> restore() async {
    isLoggedIn = Storage.getBool(PrefKeys.isLoggedIn);
    username = Storage.getString(PrefKeys.username);
    tockenid = Storage.getString(PrefKeys.tockenid);
    isvip = Storage.getBool(PrefKeys.isvip);
    email = Storage.getString(PrefKeys.email);
    nickname = Storage.getString(PrefKeys.nickname);
    avatarUrl = Storage.getString(PrefKeys.avatarUrl);
    vipText = Storage.getString(PrefKeys.vipText);
    autoSyncEnabled = Storage.getBool(PrefKeys.autoSyncEnabled);
    auto2SyncEnabled = Storage.getBool(PrefKeys.auto2SyncEnabled);
    autoSyncProgressEnabled = Storage.getBool(PrefKeys.autoSyncProgressEnabled);
    cloudbookself = Storage.getBool(PrefKeys.cloudbookself);
    cloudsource = Storage.getBool(PrefKeys.cloudsource);
    cloudtheme = Storage.getBool(PrefKeys.cloudtheme);
    cloudmark = Storage.getBool(PrefKeys.cloudmark);
    cloudtts = Storage.getBool(PrefKeys.cloudtts);
    if (tockenid.isEmpty) isLoggedIn = false;
    await enforceMembership();
    _notify();
  }

  /// Logout / expired token (0x10487c4): token "", flags off, prefs cleared.
  static Future<void> clear() async {
    isLoggedIn = false;
    username = '';
    tockenid = '';
    email = '';
    nickname = '';
    avatarUrl = '';
    vipText = '';
    isvip = false;
    autoSyncEnabled = auto2SyncEnabled = autoSyncProgressEnabled = false;
    cloudbookself = cloudsource = cloudtheme = cloudmark = cloudtts = false;
    for (final k in [
      PrefKeys.isLoggedIn, PrefKeys.username, PrefKeys.tockenid, PrefKeys.isvip, PrefKeys.email,
      PrefKeys.nickname, PrefKeys.avatarUrl, PrefKeys.vipText, PrefKeys.autoSyncEnabled, PrefKeys.auto2SyncEnabled,
      PrefKeys.autoSyncProgressEnabled, PrefKeys.cloudbookself, PrefKeys.cloudsource, PrefKeys.cloudtheme,
      PrefKeys.cloudmark, PrefKeys.cloudtts, PrefKeys.etag, PrefKeys.grouptag, PrefKeys.bjetag, PrefKeys.rsstag,
      PrefKeys.sourcetag, PrefKeys.groundmd5, PrefKeys.svgmd5, PrefKeys.markmd5, PrefKeys.ttsmd5,
    ]) {
      await Storage.remove(k);
    }
    _notify();
  }

  /// getUserInfo + apply. Returns false when the call fails; an expired token ends the session (see UserApi).
  static Future<bool> refresh() async {
    if (tockenid.isEmpty) return false;
    final info = await UserApi.getUserInfo();
    if (info == null) return false;
    await apply(info);
    return true;
  }
}
