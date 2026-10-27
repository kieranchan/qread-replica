// read/api/read_storage_root.dart — the directory every per-book store of the reader lives under.
//
// The original keeps these directories below the app documents directory (docs/STORAGE.md: `/bookcache2 /bookrule /bookmark
// /bookai /high /epub /covers /book_reading_time ...`). The storage owner (data/ + storage/) provides the real documents
// directory; the reader engine only needs "a root", so it is injectable: the app sets it once at start-up
// (`ReadStorageRoot.dir = Directory(docsPath)`), tests point it at a temporary directory.
import 'dart:io';

abstract class ReadStorageRoot {
  static Directory? _dir;

  /// The root directory. Throws [StateError] when nobody set it (a programming error, not a runtime condition).
  static Directory get dir {
    final d = _dir;
    if (d == null) {
      throw StateError('ReadStorageRoot.dir is not set; call ReadStorageRoot.dir = Directory(<documents>) at start-up');
    }
    return d;
  }

  static set dir(Directory value) => _dir = value;

  static bool get isSet => _dir != null;

  /// Convenience for tests / start-up code.
  static void use(String path) => _dir = Directory(path);

  /// `<root>/<name>` (not created).
  static Directory sub(String name) => Directory('${dir.path}/$name');

  /// `<root>/<name>`, created when missing.
  static Directory ensureSub(String name) {
    final d = sub(name);
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  // Directory names as in docs/STORAGE.md.
  static const String bookcache2 = 'bookcache2';
  static const String bookrule = 'bookrule';
  static const String bookmark = 'bookmark';
  static const String bookai = 'bookai';
  static const String high = 'high';
  static const String epub = 'epub';
  static const String covers = 'covers';
  static const String images = 'images';
  static const String item = 'item';
}
