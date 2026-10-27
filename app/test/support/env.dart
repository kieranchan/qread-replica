// Shared test fixture for the storage / data tests: a temp storage root, mock SharedPreferences, all static managers reset.
import 'dart:io';

import 'package:newread/common/app_dirs.dart';
import 'package:newread/common/common.dart';
import 'package:newread/data/background_music_manager.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/data/chromemark.dart';
import 'package:newread/data/exploration.dart';
import 'package:newread/data/fonts.dart';
import 'package:newread/data/ground.dart';
import 'package:newread/data/highlight.dart';
import 'package:newread/data/note_data_n.dart';
import 'package:newread/data/qsource.dart';
import 'package:newread/data/replace.dart';
import 'package:newread/data/rss.dart';
import 'package:newread/data/source.dart';
import 'package:newread/data/svg.dart';
import 'package:newread/data/tts.dart';
import 'package:newread/data/txtrule.dart';
import 'package:newread/data/user.dart';
import 'package:newread/data/webdav.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Forgets everything the managers hold in memory (what a fresh process would not have).
void resetManagers() {
  Bookdata.reset();
  Groupdata.reset();
  QSources.reset();
  BookSelfN.notifyListenerlist.clear();
  for (final s in [
    Sourcedata.store,
    Rssdata.store,
    ReplaceData.store,
    Txtruledata.store,
    HighlightData.store,
    NoteDataN.store,
    FontsData.store,
    Ground.store,
    Svg.store,
    TTSData.store,
    WebDav.store,
    ExplorationData.store,
    Chromemarks.store,
    BackgroundMusicManager.store,
  ]) {
    s.reset();
  }
}

/// A storage root + prefs, like one device. Use [switchTo] to move the process "to another device".
class TestDevice {
  final Directory dir;
  final Map<String, Object> prefs;
  TestDevice(this.dir, [Map<String, Object>? prefs]) : prefs = prefs ?? {};

  /// Makes this device the current one (fresh in-memory state, its own prefs and files).
  Future<void> activate() async {
    resetManagers();
    Common.cleanwhite.clear();
    SharedPreferences.setMockInitialValues(Map<String, Object>.of(prefs));
    await Storage.init(root: dir);
    await AppDirs.init(root: dir);
    await UserSession.restore();
  }

  /// Copies the current prefs back (so a later [activate] sees them).
  void capture() {
    prefs
      ..clear()
      ..addAll({for (final e in Storage.dumpPrefs().entries) e.key: e.value});
  }

  void delete() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<TestDevice> newDevice() async {
  final d = TestDevice(Directory.systemTemp.createTempSync('qread_test_'));
  await d.activate();
  return d;
}
