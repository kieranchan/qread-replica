// data/cloud/auto_backup.dart — automatic backups of this device to the own server: 书架备份 (`autoSyncEnabled`, free accounts keep
// 2 devices) and 书源备份 (`auto2SyncEnabled`, member feature: sources + RSS). Recovered from the original:
//   statics       0x1f4c booksUrl (set by `openAuto`), 0x1f50 sourceUrl / 0x1f54 rssUrl (set by `newopenAuto2`)
//   0xf22200      reopen(): at start-up re-open the switched-on backups with st "1" (toasts 开启书源同步成功 / 开启书架同步成功 /
//                 开启书架同步失败:<e>; the source failure toast of the original also says 开启书源同步成功:<e>)
//   0xe65010      backupBooks(): the whole shelf as JSON → `putCos` to booksUrl, then `lastSyncTime` = yyyy-MM-dd HH:mm:ss
//   0xe7665c / 0xe72958  backupSources() / backupRss(): the source / RSS list → sourceUrl / rssUrl (`lastSyncTime2` / `lastSyncTimer3`)
//   0x1bc564 / 0x1c7e34 / 0x1c5610  scheduleBooks/Sources/Rss(): after a save, 10 s debounce, only when the switch is on and
//                 the url is known (the shelf only when 云端书架 is off: Bookdata.save 0xe64c00 takes the cloud branch otherwise)
//   0x1048068 / 0x1047b98  performSync() / performSync2(): the 立即备份 buttons (请先开启备份, 获取上传路径失败, 同步完成)
// The urls are handed out by the server (`<base>/autobackup/<key>`); other devices list the backup devices (`getAutoDevice` /
// `getAuto2Device`) and download through `getBookSelf` / `getSources` / `getRss` (pages/user/auto_device_management_dialog.dart).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';

import '../../api/userapi.dart';
import '../../storage/storage.dart';
import '../../util/toast.dart';
import '../bookself.dart';
import '../rss.dart';
import '../source.dart';
import '../user.dart';

abstract class AutoBackup {
  /// Upload urls of this device's backups ('' until opened).
  static String booksUrl = '';
  static String sourceUrl = '';
  static String rssUrl = '';

  /// Debounce of the automatic upload after a save (0x1bc5fc: `Duration(seconds: 10)`).
  static Duration delay = const Duration(seconds: 10);

  static Timer? _books;
  static Timer? _sources;
  static Timer? _rss;
  static bool _reopening = false;

  /// Shows / hides the blocking progress of the 立即备份 buttons (the original's loading overlay). Pages replace it.
  static void Function(bool show) loading = (_) {};

  static String now() => DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  /// Forgets the urls and timers (logout, tests).
  static void reset() {
    booksUrl = sourceUrl = rssUrl = '';
    for (final t in [_books, _sources, _rss]) {
      t?.cancel();
    }
    _books = _sources = _rss = null;
  }

  /// 0xf22200: re-opens the backups that are switched on (st "1"), once per call; nothing when signed out.
  static Future<void> reopen() async {
    if (!UserSession.isLoggedIn) return;
    if (!UserSession.autoSyncEnabled && !UserSession.auto2SyncEnabled) return;
    if (_reopening) return;
    _reopening = true;
    try {
      if (UserSession.auto2SyncEnabled) {
        try {
          await UserApi.newopenAuto2(st: '1');
          Toast.show('开启书源同步成功');
        } catch (e) {
          Toast.show('开启书源同步成功:$e', iserror: true); // sic: the original's failure text
        }
      }
      if (UserSession.autoSyncEnabled) {
        try {
          await UserApi.openAuto(st: '1');
          Toast.show('开启书架同步成功');
        } catch (e) {
          Toast.show('开启书架同步失败:$e', iserror: true);
        }
      }
    } finally {
      _reopening = false;
    }
  }

  /// 0xe65010: uploads the shelf (all books, as stored); an empty shelf only updates the time.
  static Future<void> backupBooks() async {
    final books = await Bookdata.load();
    if (books.isNotEmpty) {
      await UserApi.putBackup(booksUrl, jsonEncode([for (final b in books) b.toJson()]));
    }
    await Storage.setString(PrefKeys.lastSyncTime, now());
  }

  /// 0xe7665c: uploads the book sources.
  static Future<void> backupSources() async {
    final list = await Sourcedata.load();
    await UserApi.putBackup(sourceUrl, jsonEncode(list));
    await Storage.setString(PrefKeys.lastSyncTime2, now());
  }

  /// 0xe72958: uploads the RSS sources (`"[" + items.join(",") + "]"`).
  static Future<void> backupRss() async {
    final list = await Rssdata.load();
    await UserApi.putBackup(rssUrl, jsonEncode(list));
    await Storage.setString(PrefKeys.lastSyncTimer3, now());
  }

  /// 0x1bc564: call after the shelf was saved (cloud bookshelf off).
  static void scheduleBooks() {
    _books?.cancel();
    _books = null;
    if (!UserSession.autoSyncEnabled || booksUrl.isEmpty || UserSession.cloudbookself) return;
    _books = Timer(delay, () => _run('书架', backupBooks));
  }

  /// 0x1c7e34: call after the book sources were saved.
  static void scheduleSources() {
    _sources?.cancel();
    _sources = null;
    if (!UserSession.auto2SyncEnabled || sourceUrl.isEmpty || UserSession.cloudsource) return;
    _sources = Timer(delay, () => _run('书源', backupSources));
  }

  /// 0x1c5610: call after the RSS sources were saved.
  static void scheduleRss() {
    _rss?.cancel();
    _rss = null;
    if (!UserSession.auto2SyncEnabled || rssUrl.isEmpty) return;
    _rss = Timer(delay, () => _run('订阅源', backupRss));
  }

  static Future<void> _run(String what, Future<void> Function() job) async {
    try {
      await job();
      debugPrint('同步$what成功');
    } catch (e) {
      debugPrint('同步$what失败$e');
    }
  }

  /// 0x1048068 `_performSync` (立即备份 of 书架备份). Returns true when the upload ran.
  static Future<bool> performSync() async {
    if (!UserSession.autoSyncEnabled) {
      Toast.show('请先开启备份', iserror: true);
      return false;
    }
    try {
      if (booksUrl.isEmpty) await UserApi.openAuto();
    } catch (e) {
      Toast.show('$e', iserror: true);
      return false;
    }
    if (booksUrl.isEmpty) {
      Toast.show('获取上传路径失败');
      return false;
    }
    loading(true);
    try {
      await backupBooks();
      loading(false);
      Toast.show('同步完成');
      return true;
    } catch (e) {
      loading(false);
      Toast.show('$e', iserror: true);
      return false;
    }
  }

  /// 0x1047b98 `_performSync2` (立即备份 of 书源备份): sources, then RSS.
  static Future<bool> performSync2() async {
    if (!UserSession.auto2SyncEnabled) {
      Toast.show('请先开启备份', iserror: true);
      return false;
    }
    try {
      if (sourceUrl.isEmpty || rssUrl.isEmpty) await UserApi.newopenAuto2();
    } catch (e) {
      Toast.show('$e', iserror: true);
      return false;
    }
    if (sourceUrl.isEmpty || rssUrl.isEmpty) {
      Toast.show('获取上传路径失败');
      return false;
    }
    loading(true);
    try {
      await backupSources();
      await backupRss();
      loading(false);
      Toast.show('同步完成');
      return true;
    } catch (e) {
      loading(false);
      Toast.show('$e', iserror: true);
      return false;
    }
  }
}
