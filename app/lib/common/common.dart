// Global app state shared by the account code (the original keeps these as statics of `Common` and library-level fields).
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

abstract class Common {
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
