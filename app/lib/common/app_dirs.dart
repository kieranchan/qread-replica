// common/app_dirs.dart — the app's directories below the documents folder (original: sub_90bbe8 creates them at start-up).
//
// The root is injectable so unit tests run on a temp directory without plugins:
//   AppDirs.root = Directory.systemTemp.createTempSync();   // tests
//   await AppDirs.init();                                    // app: path_provider documents directory
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class AppDirs {
  /// The 19 directories sub_90bbe8 builds from `<documents>` + literal (docs/STORAGE.md).
  static const List<String> startup = [
    'covers_cache', 'images', 'tab_icons', 'themes', 'item', 'epub', 'bookcache', 'bookcache2', 'audio2', 'books',
    'bookrule', 'epubrule', 'bookmark', 'chinese', 'audio', 'cache', 'covers', 'tts_analysis', 'backup',
  ];

  /// Directories other parts of the original create on first use (fonts, highlight rules, AI chat, reading time, ...).
  /// The replica creates them at start-up too: an empty folder costs nothing and backups can rely on it.
  static const List<String> extra = [
    'fonts', 'background_music', 'high', 'bookai', 'book_reading_time', 'reading_time', 'local_tts',
  ];

  /// Staging folders of backup / restore (main_page.dart 0x10bac64). Created on demand only.
  static const String backupTemp = 'backup_temp';
  static const String restoreTemp = 'restore_temp';

  /// Everything a backup zip contains (settings_keys/SETTINGS.md section 2); `settings.json` sits next to them.
  static const List<String> backupDirs = [
    'bookcache2', 'bookrule', 'bookmark', 'bookai', 'book_reading_time', 'books', 'cache', 'audio2', 'covers',
    'covers_cache', 'fonts', 'epub', 'images', 'item', 'high', 'reading_time', 'tab_icons', 'themes', 'background_music',
  ];

  static Directory? _root;

  /// Sets the storage root (a documents-like directory). Tests point it at a temp directory.
  static set root(Directory dir) => _root = dir;

  static bool get hasRoot => _root != null;

  /// The root directory; throws until [init] ran or [root] was set.
  static Directory get root {
    final r = _root;
    if (r == null) throw StateError('AppDirs.root is not set: call AppDirs.init() first');
    return r;
  }

  /// Absolute path of `<root>/<name>` (several segments allowed).
  static String path(String name, [String? a, String? b]) => p.joinAll([root.path, name, ?a, ?b]);

  static Directory dir(String name) => Directory(path(name));

  /// `<root>/item`, where the file store keeps its files.
  static Directory get item => dir('item');

  /// Resolves the root (documents directory through path_provider unless [root] is given or already set) and creates all
  /// directories. Safe to call again.
  static Future<Directory> init({Directory? root}) async {
    if (root != null) {
      _root = root;
    } else {
      _root ??= await getApplicationDocumentsDirectory();
    }
    final r = _root!;
    if (!r.existsSync()) await r.create(recursive: true);
    for (final name in [...startup, ...extra]) {
      final d = Directory(p.join(r.path, name));
      if (!d.existsSync()) await d.create(recursive: true);
    }
    return r;
  }

  /// Creates and returns `<root>/<name>` (for staging folders and per-feature folders).
  static Future<Directory> ensure(String name) async {
    final d = dir(name);
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }
}
