// init/appinit.dart — start-up: storage, device id (`appid`), device model, session restore, background refresh.
import 'dart:io' show Platform;
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../common/common.dart';
import '../data/user.dart';
import '../storage/storage.dart';

abstract class AppInit {
  static const _appidKey = 'appid';

  static Future<void> init() async {
    await Storage.init();
    await _initDevice();
    await UserSession.restore();
    if (UserSession.isLoggedIn) {
      // the original refreshes the account in the background; a failure keeps the cached state
      UserSession.refresh();
    }
  }

  /// `appid` = the device identifier (iOS identifierForVendor in the original via device_info_plus); a random id is kept
  /// in prefs when the plugin has nothing.
  static Future<void> _initDevice() async {
    String id = '';
    String model = 'unknown';
    try {
      if (!kIsWeb) {
        final info = DeviceInfoPlugin();
        if (Platform.isIOS) {
          final d = await info.iosInfo;
          id = d.identifierForVendor ?? '';
          model = d.utsname.machine;
        } else if (Platform.isAndroid) {
          final d = await info.androidInfo;
          id = d.id;
          model = d.model;
        } else if (Platform.isWindows) {
          final d = await info.windowsInfo;
          id = d.deviceId;
          model = d.productName;
        }
      }
    } catch (_) {}
    if (id.isEmpty) id = Storage.getString(_appidKey);
    if (id.isEmpty) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    }
    await Storage.setString(_appidKey, id);
    Common.appid = id;
    Common.deviceModel = model;
  }
}
