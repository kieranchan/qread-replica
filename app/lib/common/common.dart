// Global app state shared by the account code (the original keeps these as statics of `Common` and library-level fields).
import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;

abstract class Common {
  /// `Common.cleanwhite` (static 0x3cc8 in the original): md5 hex of every file-store key that must survive a "clean items".
  /// Each data manager adds its key when it loads (`Storage.keepOnClean(key)`); AppInit adds the account/sync keys
  /// (docs/SETTINGS.md section 1: isLoggedIn username tockenid autoSyncEnabled ... avatar_url).
  static final Set<String> cleanwhite = <String>{};

  /// Run when the app returns to the foreground (static 0x3cb8).
  static final List<void Function(dynamic)> appResumedCallbacks = <void Function(dynamic)>[];

  /// Image urls that failed to load, so lists do not retry them (static 0x3c30).
  static final Set<String> imgerrors = <String>{};

  /// Bumped to make the floating notice (download / tts progress) repaint (static 0x3be0).
  static final ValueNotifier<int> floatingnoticy = ValueNotifier<int>(0);

  /// Bottom-bar state: [index] selected tab, [active] route/page name, [isleft] one-hand side, [islistenpage2] (0x3ba0/0x3bf0/0x3be8/0x3c78).
  static final ValueNotifier<int> index = ValueNotifier<int>(0);
  static final ValueNotifier<String> active = ValueNotifier<String>('');
  static final ValueNotifier<bool> isleft = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> islistenpage2 = ValueNotifier<bool>(false);

  /// Per-book "in shelf" flags the lists listen to (static 0x3c00): key = bookUrl.
  static final Map<String, ValueNotifier<bool>> bookUrls = <String, ValueNotifier<bool>>{};

  /// Built-in reading backgrounds (static 0x3ce8 / 0x3cf8 / 0x3cf0); filled by the theme code from the assets.
  static List<String> background = <String>[];
  static List<String> backgroundimages = <String>[];
  static Map<int, String> showbackground = <int, String>{};

  /// Pool size handed to the Legado-compatible backend (static 0x3c18).
  static int qreadpool = 0;

  /// App bar colour of the current theme (static 0x3c48).
  static Color appbarcolor = const Color(0xFFFFFFFF);

  /// Base URL of the account/cloud API, with trailing slash (endpoints and `vip?tockenid=` are appended directly, as in the
  /// original). The original ships a fixed host; the replica points at the owner's server and can be overridden with
  /// `--dart-define=QREAD_BASE_URL=http://127.0.0.1:8920/`.
  static String apiBase = const String.fromEnvironment('QREAD_BASE_URL', defaultValue: 'https://qread.forfine.me/');

  /// Device id sent as `appid` (set at start-up, see init/appinit.dart).
  static String appid = '';

  /// Sent as `model` on login.
  static String deviceModel = 'unknown';

  /// Sent as `platform` on login (`ios` on iOS, as the original does).
  static String get platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'other';
  }

  static String url(String endpoint) => '$apiBase$endpoint';
}
