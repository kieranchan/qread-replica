// data/bookself.dart — the bookshelf: books, groups, reading progress, update flags, sort, and the cloud sync glue.
//
// File-store keys: `bookself` (JSON list of [Book]), `bookgroup` (JSON list of group names), `hidegroups` (JSON list of hidden group
// names). Cloud: `getBooks` / `getGroups` (etag prefs keys `etag` / `grouptag`), switch `cloudbookself`.
//
// Original classes (static members, operations under a `Lock`; method names were dropped by the AOT build, the address of the
// closure body that implements each operation is given on the replica method):
//   Bookdata   `_books` 0x3ff8; load 0x10dce94 (also loads groups, hidden groups, history and notes and adds their md5 keys to
//              `cleanwhite`); save 0xe64c00 (`书架保存失败…`, cloud check `获取云端信息失败`); auto-sync timer 0xe64eb0
//              (`同步书架成功` / `同步书架失败`)
//   BookSelfN  `_lock` 0x4020, `_grouplock` 0x4028, `ygroups` 0x4010 (cloud groups), `mybooks` 0x4008 (per-group lists),
//              `notifyListenerlist` 0x4040 (id -> async callback(Book), called when a book changes)
//   Groupdata  `_groups` 0x4050, `_hidegroups` 0x4058
//   syncCloud  0xe6766c (bookshelf), group sync 0x104a604 (`更新分组`)
//
// Local books (imported files) have `origin == 'phone_book'`; their identity across devices is name + author (their `bookUrl`
// is a device path), every other book is identified by `bookUrl` (0xe6766c builds the merge map with that rule).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;

import '../api/userapi.dart' show CloudKind;
import '../common/lock.dart';
import '../models/book.dart';
import '../storage/storage.dart';
import 'cloud_api.dart';
import 'cloud_sync.dart';
import 'user.dart';

/// Shelf sort modes (the pages choose; the data layer only provides the comparators).
enum BookSort { recentRead, recentUpdate, name, author, manual }

/// Group name shown for "everything"; it is implicit and never stored.
const String kAllGroup = '全部';

/// `origin` value of books imported from files on the phone.
const String kPhoneBook = 'phone_book';

String bookKey(Book b) => b.origin == kPhoneBook ? '$kPhoneBook:${b.name}|${b.author}' : b.bookUrl;

/// A list of strings persisted as a JSON array in the file store (groups, hidden groups).
class _StringStore {
  final String key;
  List<String> items = <String>[];
  bool loaded = false;
  _StringStore(this.key);

  Future<void> load({bool force = false}) async {
    if (loaded && !force) return;
    Storage.keepOnClean(key);
    items = [for (final e in Storage.jsondecode(await Storage.read(key))) '$e'];
    loaded = true;
  }

  Future<bool> save() async {
    try {
      await Storage.write(key, jsonEncode(items));
      return true;
    } catch (e) {
      debugPrint('分组保存失败 $e');
      return false;
    }
  }
}

abstract class Groupdata {
  static final _StringStore _groups = _StringStore('bookgroup');
  static final _StringStore _hidegroups = _StringStore('hidegroups');
  static final Lock _lock = Lock();

  /// Group names in display order (without the implicit 「全部」).
  static List<String> get groups => _groups.items;
  static List<String> get hidegroups => _hidegroups.items;

  static Future<void> load({bool force = false}) async {
    await _groups.load(force: force);
    await _hidegroups.load(force: force);
  }

  /// 0x6e1568: is [name] a known group.
  static bool contains(String name) => _groups.items.contains(name);

  static bool isHidden(String name) => _hidegroups.items.contains(name);

  /// 0x104b624: adds a group; false for an empty / reserved / existing name.
  static Future<bool> add(String name) => _lock.synchronized(() async {
        await load();
        final n = name.trim();
        if (n.isEmpty || n == kAllGroup || _groups.items.contains(n)) return false;
        _groups.items.add(n);
        await _groups.save();
        BookSelfN._bump();
        return true;
      });

  /// Removes a group; its books go back to "no group".
  static Future<void> remove(String name) => _lock.synchronized(() async {
        await load();
        if (!_groups.items.remove(name)) return;
        _hidegroups.items.remove(name);
        await _groups.save();
        await _hidegroups.save();
        await BookSelfN._clearGroup(name);
        BookSelfN._bump();
      });

  /// Renames a group (books follow). False when [to] is empty/reserved/taken or [from] is unknown.
  static Future<bool> rename(String from, String to) => _lock.synchronized(() async {
        await load();
        final n = to.trim();
        final i = _groups.items.indexOf(from);
        if (i < 0 || n.isEmpty || n == kAllGroup || (n != from && _groups.items.contains(n))) return false;
        _groups.items[i] = n;
        final h = _hidegroups.items.indexOf(from);
        if (h >= 0) _hidegroups.items[h] = n;
        await _groups.save();
        await _hidegroups.save();
        await BookSelfN._renameGroup(from, n);
        BookSelfN._bump();
        return true;
      });

  /// Moves a group to a new position (drag and drop).
  static Future<void> move(int from, int to) => _lock.synchronized(() async {
        await load();
        if (from < 0 || from >= _groups.items.length) return;
        final g = _groups.items.removeAt(from);
        _groups.items.insert(to.clamp(0, _groups.items.length), g);
        await _groups.save();
        BookSelfN._bump();
      });

  /// 0x104b028 / 0x104b2f8: hide or show a group tab.
  static Future<void> setHidden(String name, bool hidden) => _lock.synchronized(() async {
        await load();
        if (hidden) {
          if (!_hidegroups.items.contains(name)) _hidegroups.items.add(name);
        } else {
          _hidegroups.items.remove(name);
        }
        await _hidegroups.save();
        BookSelfN._bump();
      });

  /// The visible group tabs: 「全部」 first, then the groups that are not hidden.
  static List<String> get visible => [kAllGroup, for (final g in _groups.items) if (!_hidegroups.items.contains(g)) g];

  /// Cloud sync of the group list (0x104a604 `更新分组`; item `groups`, etag prefs key `grouptag`). Groups that the cloud
  /// holds and this device never had are added, groups deleted on the other device are dropped.
  static Future<CloudSyncResult> syncCloud({CloudApi? api}) => _lock.synchronized(() async {
        await load();
        final a = api ?? defaultCloudApi;
        final result = await CloudSync.syncList(
          api: a,
          kind: CloudKind.groups,
          itemName: 'groups',
          etagKey: PrefKeys.grouptag,
          encodeLocal: () => jsonEncode(_groups.items),
          mergeRemote: (text) async {
            final remote = [for (final e in Storage.jsondecode(text)) '$e'].where((g) => g.isNotEmpty && g != kAllGroup).toList();
            final base = await CloudSync.loadBase('groups');
            final merged = CloudSync.merge3<String>(local: _groups.items, remote: remote, key: (g) => g, base: base);
            final changed = merged.length != _groups.items.length || [for (var i = 0; i < merged.length; i++) merged[i] != _groups.items[i]].contains(true);
            if (changed) {
              _groups.items = merged;
              await _groups.save();
            }
            return changed;
          },
        );
        await CloudSync.saveBase('groups', _groups.items);
        BookSelfN._bump();
        return result;
      });
}

abstract class Bookdata {
  static const String key = 'bookself';

  static List<Book> _books = <Book>[];
  static bool _loaded = false;
  static Timer? _syncTimer;

  /// Delay before an auto sync runs after a change (the original keeps a `Timer` with a fixed duration, 0xe64eb0).
  static Duration syncDelay = const Duration(seconds: 5);

  /// Turned off in tests that must not start timers.
  static bool autoSync = true;

  /// All books in stored order.
  static List<Book> get books => _books;

  /// 0x10dce94: loads the shelf, the groups and the hidden groups (idempotent unless [force]).
  static Future<List<Book>> load({bool force = false}) async {
    if (_loaded && !force) return _books;
    Storage.keepOnClean(key);
    Storage.keepOnClean('historybook');
    final out = <Book>[];
    for (final e in Storage.jsondecode(await Storage.read(key))) {
      if (e is Map) {
        try {
          out.add(Book.fromJson(Map<String, dynamic>.from(e)));
        } catch (err) {
          debugPrint('书架解析失败 $err');
        }
      }
    }
    _books = out;
    _loaded = true;
    await Groupdata.load(force: force);
    return _books;
  }

  static String encode() => jsonEncode([for (final b in _books) b.toJson()]);

  /// 0xe64c00: writes the shelf; [need] false skips scheduling the cloud sync (used by the sync itself).
  static Future<bool> save({bool need = true}) async {
    var ok = true;
    try {
      await Storage.write(key, encode());
    } catch (e) {
      debugPrint('书架保存失败 $e');
      ok = false;
    }
    if (need) scheduleSync();
    return ok;
  }

  /// Starts (or restarts) the debounce timer of the auto sync; does nothing unless the bookshelf sync switch is on and a user
  /// is signed in.
  static void scheduleSync() {
    if (!autoSync || !UserSession.cloudbookself || !UserSession.isLoggedIn) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(syncDelay, () async {
      try {
        await BookSelfN.syncCloud();
        debugPrint('同步书架成功');
      } catch (e) {
        debugPrint('同步书架失败 $e');
      }
    });
  }

  static void cancelSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Forgets the loaded state (tests, logout).
  static void reset() {
    cancelSync();
    _books = <Book>[];
    _loaded = false;
  }
}

abstract class BookSelfN {
  static final Lock _lock = Lock();

  /// Cloud groups (0x4010), as downloaded by the last group sync.
  static List<String> ygroups = <String>[];

  /// id -> callback, called (after the lock is released) with the changed book (0x4040).
  static final Map<int, Future<void> Function(Book)> notifyListenerlist = {};

  /// Bumped on every change of books or groups, so list widgets can rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bump() => revision.value++;

  static Future<void> _notify(Book b) async {
    for (final cb in List.of(notifyListenerlist.values)) {
      try {
        await cb(b);
      } catch (e) {
        debugPrint('书架监听失败 $e');
      }
    }
  }

  static Future<T> _op<T>(FutureOr<T> Function(List<Book> books) body, {bool need = true}) {
    return _lock.synchronized(() async {
      await Bookdata.load();
      final r = await body(Bookdata.books);
      await Bookdata.save(need: need);
      _bump();
      return r;
    });
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static int _indexOf(List<Book> list, String bookUrl) => list.indexWhere((b) => b.bookUrl == bookUrl);

  // ------------------------------------------------------------------------------------------------ queries

  static Future<List<Book>> load() => Bookdata.load();

  /// All books in stored order.
  static List<Book> get books => Bookdata.books;

  static Book? get(String bookUrl) {
    for (final b in Bookdata.books) {
      if (b.bookUrl == bookUrl) return b;
    }
    return null;
  }

  static bool contains(String bookUrl) => get(bookUrl) != null;

  /// True when [group] holds the book (`bookgroup` may list several groups separated by `,`); 「全部」 holds everything and
  /// `''` means "books without a group".
  static bool inGroup(Book b, String group) {
    if (group == kAllGroup) return true;
    final groups = b.bookgroup.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    if (group.isEmpty) return groups.isEmpty;
    return groups.contains(group);
  }

  /// `mybooks[group]`: the books of a group in the requested order (a copy).
  static List<Book> booksOf(String group, {BookSort sort = BookSort.manual, bool reverse = false}) {
    return sorted([for (final b in Bookdata.books) if (inGroup(b, group)) b], sort, reverse: reverse);
  }

  /// Number of books per group (「全部」 included).
  static Map<String, int> groupCounts() {
    final m = <String, int>{kAllGroup: Bookdata.books.length};
    for (final g in Groupdata.groups) {
      m[g] = Bookdata.books.where((b) => inGroup(b, g)).length;
    }
    return m;
  }

  /// The most recently read book (largest `durChapterTime`), null when nothing was read yet.
  static Book? get lastRead {
    Book? best;
    for (final b in Bookdata.books) {
      if (b.durChapterTime > 0 && (best == null || b.durChapterTime > best.durChapterTime)) best = b;
    }
    return best;
  }

  /// A stable sort (ties keep the stored order). `recentRead`: last read first; `recentUpdate`: newest chapter first;
  /// `name` / `author`: ascending; `manual`: stored order.
  static List<Book> sorted(Iterable<Book> books, BookSort mode, {bool reverse = false}) {
    final src = books.toList();
    final idx = {for (var i = 0; i < src.length; i++) src[i]: i};
    int tie(Book a, Book b) => idx[a]!.compareTo(idx[b]!);
    int cmp(Book a, Book b) {
      switch (mode) {
        case BookSort.recentRead:
          final c = b.durChapterTime.compareTo(a.durChapterTime);
          return c != 0 ? c : tie(a, b);
        case BookSort.recentUpdate:
          final c = b.latestChapterTime.compareTo(a.latestChapterTime);
          return c != 0 ? c : tie(a, b);
        case BookSort.name:
          final c = a.name.compareTo(b.name);
          return c != 0 ? c : tie(a, b);
        case BookSort.author:
          final c = a.author.compareTo(b.author);
          return c != 0 ? c : tie(a, b);
        case BookSort.manual:
          return tie(a, b);
      }
    }

    src.sort(cmp);
    return reverse ? src.reversed.toList() : src;
  }

  // ----------------------------------------------------------------------------------------- add / remove

  /// Adds a book (a copy is stored and returned). A book that is already on the shelf (same [bookKey]) keeps its progress and
  /// group; its descriptive fields are refreshed. 0xfb3e60 / 0xf74c24 cover the "info loaded" refresh.
  static Future<Book> add(Book book) => _op((list) {
        final copy = Book.fromJson(book.toJson());
        final k = bookKey(copy);
        final i = list.indexWhere((b) => bookKey(b) == k);
        if (i >= 0) {
          final old = list[i];
          _mergeInfo(old, copy);
          return old;
        }
        list.add(copy);
        return copy;
      });

  /// Adds many books in one write; returns how many were new.
  static Future<int> addAll(Iterable<Book> books) => _op((list) {
        var n = 0;
        for (final b in books) {
          final copy = Book.fromJson(b.toJson());
          final k = bookKey(copy);
          final i = list.indexWhere((x) => bookKey(x) == k);
          if (i >= 0) {
            _mergeInfo(list[i], copy);
          } else {
            list.add(copy);
            n++;
          }
        }
        return n;
      });

  /// 0xf777c4 / 0xf720ac (`removeWhere`): removes one book; returns whether it was on the shelf.
  static Future<bool> remove(String bookUrl) => _op((list) {
        final before = list.length;
        list.removeWhere((b) => b.bookUrl == bookUrl);
        return list.length != before;
      });

  static Future<int> removeMany(Iterable<String> bookUrls) {
    final set = bookUrls.toSet();
    return _op((list) {
      final before = list.length;
      list.removeWhere((b) => set.contains(b.bookUrl));
      return before - list.length;
    });
  }

  /// Moves a book in the stored order (manual sort).
  static Future<void> move(int from, int to) => _op((list) {
        if (from < 0 || from >= list.length) return;
        final b = list.removeAt(from);
        list.insert(to.clamp(0, list.length), b);
      });

  // --------------------------------------------------------------------------------------- progress / info

  /// 0xea9108 (read): stores the reading position of the book — chapter index, offset in the chapter, chapter title — and stamps
  /// `durChapterTime` with now; clears the "has update" marks. Listeners are notified.
  static Future<void> updateProgress(String bookUrl, {required int index, required double pos, String? title, String? readchapter}) async {
    Book? changed;
    await _op((list) {
      final i = _indexOf(list, bookUrl);
      if (i < 0) return;
      final b = list[i];
      b.durChapterIndex = index;
      b.durChapterPos = pos;
      if (title != null) b.durChapterTitle = title;
      if (readchapter != null) b.readchapter = readchapter;
      b.durChapterTime = _now;
      b.isredupdate = false;
      changed = b;
    });
    if (changed != null) await _notify(changed!);
  }

  /// 0xed97bc: a catalog refresh finished. Always stamps `lastCheckTime`; when the latest chapter title changed it also stores
  /// title / count, stamps `latestChapterTime` and marks the book as updated (`isredupdate`).
  static Future<bool> updateLatest(String bookUrl, {required String latestTitle, required int totalChapters}) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i < 0) return false;
        final b = list[i];
        b.lastCheckTime = _now;
        var updated = false;
        if (latestTitle.isNotEmpty && latestTitle != b.latestChapterTitle) {
          b.latestChapterTime = _now;
          b.latestChapterTitle = latestTitle;
          b.totalChapterNum = totalChapters;
          b.isredupdate = true;
          updated = true;
        } else if (totalChapters > b.totalChapterNum) {
          b.totalChapterNum = totalChapters;
        }
        return updated;
      });

  /// 0xfb58b8: the table of contents was re-read: charset, toc url, current/latest chapter titles and the chapter count.
  static Future<void> updateToc(String bookUrl, {String? charset, String? tocUrl, String? durTitle, String? latestTitle, int? totalChapters}) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i < 0) return;
        final b = list[i];
        if (charset != null) b.charset = charset;
        if (tocUrl != null) b.tocUrl = tocUrl;
        if (durTitle != null) b.durChapterTitle = durTitle;
        if (latestTitle != null) b.latestChapterTitle = latestTitle;
        if (totalChapters != null) b.totalChapterNum = totalChapters;
      });

  /// 0xf74c24: book info was loaded from the source: copies `origin` / `isqread`, marks `isinfo`, and fills kind, cover,
  /// intro, toc url and word count when the new value is not empty.
  static Future<void> updateInfo(Book info) => _op((list) {
        final i = _indexOf(list, info.bookUrl);
        if (i < 0) return;
        _mergeInfo(list[i], info);
      });

  static void _mergeInfo(Book dst, Book src) {
    dst.origin = src.origin.isNotEmpty ? src.origin : dst.origin;
    dst.isqread = src.isqread;
    dst.isinfo = true;
    if (src.kind.isNotEmpty) dst.kind = src.kind;
    if (src.coverUrl.isNotEmpty) dst.coverUrl = src.coverUrl;
    if (src.intro.isNotEmpty) dst.intro = src.intro;
    if (src.tocUrl.isNotEmpty) dst.tocUrl = src.tocUrl;
    if (src.wordCount.isNotEmpty) dst.wordCount = src.wordCount;
    if (src.name.isNotEmpty && dst.name.isEmpty) dst.name = src.name;
    if (src.author.isNotEmpty && dst.author.isEmpty) dst.author = src.author;
  }

  /// 0x100652c: edit name, cover and intro.
  static Future<void> setBasic(String bookUrl, {String? name, String? coverUrl, String? intro}) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i < 0) return;
        final b = list[i];
        if (name != null) b.name = name;
        if (coverUrl != null) b.coverUrl = coverUrl;
        if (intro != null) b.intro = intro;
      });

  /// 0xfb666c: book type and cover.
  static Future<void> setType(String bookUrl, int type, {String? coverUrl}) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i < 0) return;
        list[i].type_ = type;
        if (coverUrl != null) list[i].coverUrl = coverUrl;
      });

  // ------------------------------------------------------------------------------------------ flags

  /// 0xf6aea8 / 0xf751d0: the `update` flag (the user switched "check for updates" on/off for the book).
  static Future<void> setUpdate(String bookUrl, bool value) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i >= 0) list[i].update = value;
      });

  /// Clears the red "updated" mark (`isredupdate`) of one book (0x104a508 for the whole shelf).
  static Future<void> clearRedUpdate({String? bookUrl}) => _op((list) {
        for (final b in list) {
          if (bookUrl == null || b.bookUrl == bookUrl) b.isredupdate = false;
        }
      });

  /// 0x1081478: `reverseCatalog`.
  static Future<void> setReverseCatalog(String bookUrl, bool value) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i >= 0) list[i].reverseCatalog = value;
      });

  /// 0x10e866c: `useReplaceRule`.
  static Future<void> setUseReplaceRule(String bookUrl, bool value) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i >= 0) list[i].useReplaceRule = value;
      });

  /// 0x10e8aa8: `useai`.
  static Future<void> setUseAi(String bookUrl, bool value) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i >= 0) list[i].useai = value;
      });

  /// 0x104a2a0 / 0xf724f0 / 0xf6f680: moves the book into a group (`''` = no group).
  static Future<void> setGroup(String bookUrl, String group) => _op((list) {
        final i = _indexOf(list, bookUrl);
        if (i >= 0) list[i].bookgroup = group == kAllGroup ? '' : group;
      });

  /// Moves several books into a group.
  static Future<void> setGroupMany(Iterable<String> bookUrls, String group) {
    final set = bookUrls.toSet();
    return _op((list) {
      for (final b in list) {
        if (set.contains(b.bookUrl)) b.bookgroup = group == kAllGroup ? '' : group;
      }
    });
  }

  static Future<void> _clearGroup(String group) => _op((list) {
        for (final b in list) {
          if (inGroup(b, group) && group != kAllGroup) {
            final rest = b.bookgroup.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && s != group);
            b.bookgroup = rest.join(',');
          }
        }
      }, need: true);

  static Future<void> _renameGroup(String from, String to) => _op((list) {
        for (final b in list) {
          final parts = b.bookgroup.split(',').map((s) => s.trim()).toList();
          if (parts.contains(from)) b.bookgroup = parts.map((s) => s == from ? to : s).join(',');
        }
      });

  // -------------------------------------------------------------------------------------------- cloud

  /// `BookSelfN.syncCloud` (0xe6766c), see data/cloud_sync.dart for the flow. Does nothing unless the bookshelf sync switch
  /// (`UserSession.cloudbookself`) is on. The cloud list is the JSON of the shelf; the merge is a three-way merge keyed by
  /// [bookKey] (so a book removed on another device disappears here and a removal here is not undone):
  ///  * progress comes from the side with the later `durChapterTime`
  ///  * latest-chapter info comes from the side with the larger chapter count / later `latestChapterTime`; `lastCheckTime` is the max
  ///  * everything else (group, flags, descriptive fields) stays as it is locally, empty fields are filled from the cloud copy
  ///
  /// TODO(asm 0xe6766c): the original proceeds into its merge branch when the update-url reply is `""` or `"-1"` and treats a
  /// non-empty reply as the new etag; that reads like the opposite of the owner's server contract (docs/API.md says the sync
  /// proceeds only when the reply is neither). The replica follows docs/API.md; see report.
  static Future<CloudSyncResult?> syncCloud({CloudApi? api}) => _lock.synchronized(() async {
        if (!UserSession.cloudbookself) return null;
        await Bookdata.load();
        final a = api ?? defaultCloudApi;
        final result = await CloudSync.syncList(
          api: a,
          kind: CloudKind.books,
          itemName: 'books',
          etagKey: PrefKeys.etag,
          encodeLocal: Bookdata.encode,
          mergeRemote: (text) async {
            final remote = <Book>[];
            for (final e in Storage.jsondecode(text)) {
              if (e is Map) remote.add(Book.fromJson(Map<String, dynamic>.from(e)));
            }
            final base = await CloudSync.loadBase('books');
            final before = Bookdata.encode();
            Bookdata._books = CloudSync.merge3<Book>(local: Bookdata.books, remote: remote, key: bookKey, base: base, both: mergeBooks);
            final changed = Bookdata.encode() != before;
            if (changed) await Bookdata.save(need: false);
            return changed;
          },
        );
        await CloudSync.saveBase('books', Bookdata.books.map(bookKey));
        await Storage.setString(PrefKeys.lastSyncTime, CloudSync.formatTime(DateTime.now()));
        _bump();
        return result;
      });

  /// Merge of the same book from this device ([l]) and the cloud ([r]); returns [l] updated in place.
  static Book mergeBooks(Book l, Book r) {
    if (r.durChapterTime > l.durChapterTime) {
      l.durChapterTime = r.durChapterTime;
      l.durChapterIndex = r.durChapterIndex;
      l.durChapterPos = r.durChapterPos;
      l.durChapterTitle = r.durChapterTitle;
      l.readchapter = r.readchapter.isNotEmpty ? r.readchapter : l.readchapter;
    }
    if (r.totalChapterNum > l.totalChapterNum || r.latestChapterTime > l.latestChapterTime) {
      l.latestChapterTitle = r.latestChapterTitle;
      l.latestChapterTime = r.latestChapterTime > l.latestChapterTime ? r.latestChapterTime : l.latestChapterTime;
      l.totalChapterNum = r.totalChapterNum > l.totalChapterNum ? r.totalChapterNum : l.totalChapterNum;
    }
    if (r.lastCheckTime > l.lastCheckTime) l.lastCheckTime = r.lastCheckTime;
    void fill(String Function(Book) get, void Function(String) set) {
      if (get(l).isEmpty && get(r).isNotEmpty) set(get(r));
    }

    fill((b) => b.kind, (v) => l.kind = v);
    fill((b) => b.coverUrl, (v) => l.coverUrl = v);
    fill((b) => b.intro, (v) => l.intro = v);
    fill((b) => b.tocUrl, (v) => l.tocUrl = v);
    fill((b) => b.wordCount, (v) => l.wordCount = v);
    fill((b) => b.charset, (v) => l.charset = v);
    fill((b) => b.bookgroup, (v) => l.bookgroup = v);
    return l;
  }
}
