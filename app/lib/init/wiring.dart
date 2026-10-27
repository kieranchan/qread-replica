// init/wiring.dart — lead-owned glue between the page areas: points the `Nav` hooks (common/nav.dart) and the start-up hooks of each
// area at the real implementations. Each area stays importable on its own; only this file (and main.dart) knows all of them.
import 'package:flutter/widgets.dart';

import '../common/app_dirs.dart';
import '../common/nav.dart';
import '../data/bookself.dart';
import '../pages/main_page.dart';
import '../pages/read/read_page.dart';
import '../pages/read/reader_ai.dart';
import '../pages/read/reader_routes.dart';
import '../pages/setting/extras_routes.dart';
import '../read/api/read_storage_root.dart';
import '../read/api/readapi.dart';
import '../theme/extras_init.dart';
import '../util/legado/js_engines.dart';
import 'reader_ai_adapter.dart';

typedef RouteTable = Future<bool> Function(BuildContext context, String name, {Object? arguments});

abstract class Wiring {
  static bool _done = false;

  static Future<bool> _readerRoutes(BuildContext context, String name, {Object? arguments}) async {
    final f = ReaderRoutes.open(context, name, arguments: arguments);
    if (f == null) return false;
    await f;
    return true;
  }

  /// Area route tables tried in order by `Nav.openNamed`; each returns true when it handled the name.
  static final List<RouteTable> routeTables = [ExtrasRoutes.open, _readerRoutes];

  /// Runs once after `AppInit.init()`.
  static Future<void> init() async {
    if (_done) return;
    _done = true;
    JsEngines.install();

    // reader: per-book stores live under the app root; progress goes back into the shelf; the AI chat uses the AI module
    if (!ReadStorageRoot.isSet) ReadStorageRoot.dir = AppDirs.root;
    ReadApi.onProgress = (book) => BookSelfN.updateProgress(book.bookUrl,
        index: book.durChapterIndex, pos: book.durChapterPos, title: book.durChapterTitle, readchapter: book.readchapter);
    ReaderAi.instance = ReaderAiAdapter();

    await ExtrasInit.init();

    Nav.openReader = (context, book, {chapterIndex, chapters}) async {
      await MainPage.stampReading();
      if (!context.mounted) return;
      await ReadPage.open(context, book, chapterIndex: chapterIndex, chapters: chapters);
      await MainPage.stampReading();
    };

    final fallback = Nav.openNamed;
    Nav.openNamed = (context, name, {arguments}) async {
      for (final open in routeTables) {
        if (!context.mounted) return;
        if (await open(context, name, arguments: arguments)) return;
      }
      if (context.mounted) await fallback(context, name, arguments: arguments);
    };
  }
}
