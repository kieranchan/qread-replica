// theme/extras_init.dart — start-up hook of the extras area. The lead calls `await ExtrasInit.init()` after `AppInit.init()` (or adds
// it to `AppInit.extraTasks`): fills the built-in reading backgrounds (`Common.background`), loads the applied themes / fonts into
// [ThemeProvider] and installs the reload that runs after a backup restore (the original restarts the app instead).
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
import '../data/theme.dart';
import '../data/tts.dart';
import '../data/txtrule.dart';
import '../data/user.dart';
import '../data/webdav.dart';
import '../init/appinit.dart';
import '../pages/background_manager_page.dart';
import '../pages/setting/backup_service.dart';
import 'theme_provider.dart';

abstract class ExtrasInit {
  static Future<void> init() async {
    BackgroundManagerPage.builtin();
    BackupService.onRestored = reloadAfterRestore;
    await ThemeProvider.instance.init();
  }

  /// Forgets every in-memory list and loads them again from the restored files, then refreshes the session and the theme.
  static Future<void> reloadAfterRestore() async {
    Bookdata.reset();
    Groupdata.reset();
    QSources.reset();
    for (final s in [
      Sourcedata.store, Rssdata.store, ReplaceData.store, Txtruledata.store, HighlightData.store, NoteDataN.store, FontsData.store,
      Ground.store, Svg.store, ThemeManager.store, TTSData.store, WebDav.store, ExplorationData.store, Chromemarks.store,
      BackgroundMusicManager.store, BackupService.store,
    ]) {
      s.reset();
    }
    await UserSession.restore();
    await AppInit.loadAllData();
    await ThemeProvider.instance.init();
  }
}
