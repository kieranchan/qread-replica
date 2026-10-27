// init/appinit.dart — start-up: storage, app directories, device id (`appid`), device model, session restore, data managers,
// background refresh. The original (0x10d37c0) also starts the audio session, notifications and the audio service; those belong
// to the pages/util areas and hook in through [AppInit.extraTasks].
import 'dart:io' show Directory, Platform;
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../common/app_dirs.dart';
import '../common/common.dart';
import '../data/background_music_manager.dart';
import '../data/bookself.dart';
import '../data/chromemark.dart';
import '../data/exploration.dart';
import '../data/fonts.dart';
import '../data/ground.dart';
import '../data/highlight.dart';
import '../data/note_data_n.dart';
import '../data/qsource.dart';
import '../data/replace.dart';
import '../data/rss.dart';
import '../data/source.dart';
import '../data/svg.dart';
import '../data/tts.dart';
import '../data/txtrule.dart';
import '../data/user.dart';
import '../data/webdav.dart';
import '../storage/storage.dart';

abstract class AppInit {
  static const _appidKey = 'appid';

  /// Keys that survive "clean items" besides the ones the data managers register themselves: the account / sync state
  /// (docs/SETTINGS.md section 1, set built at the top of 0x11284a8) and the two AES keys (0x10d9b4c).
  static const List<String> accountKeys = [
    'isLoggedIn', 'username', 'tockenid', 'autoSyncEnabled', 'auto2SyncEnabled', 'autoSyncProgressEnabled', 'lastSyncTime',
    'lastSyncTime2', 'lastSyncTimer3', 'cloudbookself', 'cloudsource', 'etag', 'grouptag', 'bjetag', 'rsstag', 'sourcetag', 'isvip',
    'cloudtheme', 'cloudmark', 'groundmd5', 'svgmd5', 'markmd5', 'cloudtts', 'ttsmd5', 'email', 'nickname', 'avatar_url',
    'encrypt_key', 'encrypt_iv',
  ];

  /// Extra start-up tasks other areas register (audio session, notifications, ...); run after the data is loaded.
  static final List<Future<void> Function()> extraTasks = [];

  /// Full start-up. [prefs] / [root] inject SharedPreferences and the storage root (tests); [loadData] false skips the data
  /// managers (tests that only need storage).
  static Future<void> init({SharedPreferences? prefs, Directory? root, bool loadData = true}) async {
    await Storage.init(prefs: prefs);
    await AppDirs.init(root: root);
    keepAccountKeys();
    await _initDevice();
    await UserSession.restore();
    if (loadData) await loadAllData();
    for (final task in extraTasks) {
      try {
        await task();
      } catch (e) {
        debugPrint('appinit task failed $e');
      }
    }
    if (UserSession.isLoggedIn) {
      // the original refreshes the account in the background; a failure keeps the cached state
      UserSession.refresh();
    }
  }

  /// Fills `Common.cleanwhite` with the md5 of the account / sync keys.
  static void keepAccountKeys() {
    for (final k in accountKeys) {
      Storage.keepOnClean(k);
    }
  }

  /// Loads every data manager (each registers its own key in `Common.cleanwhite`). Failures of one store do not stop the others.
  static Future<void> loadAllData() async {
    final loaders = <String, Future<Object?> Function()>{
      'bookself': Bookdata.load,
      'source': Sourcedata.load,
      'sourcedata': QSources.load,
      'rss': Rssdata.load,
      'replaces': ReplaceData.load,
      'txt_toc_rule': Txtruledata.load,
      'highlightRules': HighlightData.load,
      'notes': NoteDataN.load,
      'fonts': FontsData.load,
      'ground': Ground.load,
      'svg': Svg.load,
      'tts': TTSData.load,
      'webdav': WebDav.load,
      'exploration': ExplorationData.load,
      'chromemark': Chromemarks.load,
      'backgroundMusic': BackgroundMusicManager.load,
    };
    for (final e in loaders.entries) {
      try {
        await e.value();
      } catch (err) {
        debugPrint('load ${e.key} failed $err');
      }
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
