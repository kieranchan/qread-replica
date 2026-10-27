// data/note_data_n.dart — reading notes and bookmarks (划线笔记 / 书签). File-store key `notes` (JSON list of [BookNote]);
// cloud list `getBjs` (etag prefs key `bjetag`, md5 key `markmd5`).
//
// Original: `NoteDataN` (static `_notes` 0x4060, `_lock` 0x4068). Bookmarks are notes whose id starts with `bm_`
// (`NoteDataN.isBookmark` 0x57cf2c, id built with the prefix at 0x24e954); everything else is a text note. Add/update stamp
// `updateTime` with the current time in ms (0xed3590); the original saves through a debounce timer, the replica saves at once.
import 'dart:convert';

import '../api/userapi.dart' show CloudKind;
import '../models/note.dart';
import '../storage/storage.dart';
import 'cloud_api.dart';
import 'cloud_sync.dart';
import 'list_store.dart';
import 'user.dart';

abstract class NoteDataN {
  static const String bookmarkPrefix = 'bm_';

  static final ListStore<BookNote> store = ListStore<BookNote>(
    'notes',
    fromJson: BookNote.fromJson,
    toJson: (n) => n.toJson(),
    label: '笔记',
  );

  static List<BookNote> get notes => store.items;

  static Future<List<BookNote>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  static bool isBookmark(BookNote n) => n.id.startsWith(bookmarkPrefix);

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Notes (not bookmarks) of one book, ordered by chapter then position (`startStableId`).
  static Future<List<BookNote>> notesOfBook(String bookUrl) async {
    final list = await load();
    final r = [for (final n in list) if (n.bookUrl == bookUrl && !isBookmark(n)) n];
    r.sort((a, b) {
      final c = a.chapterIndex.compareTo(b.chapterIndex);
      return c != 0 ? c : a.startStableId.compareTo(b.startStableId);
    });
    return r;
  }

  /// Bookmarks of one book ordered by chapter then position.
  static Future<List<BookNote>> bookmarksOfBook(String bookUrl) async {
    final list = await load();
    final r = [for (final n in list) if (n.bookUrl == bookUrl && isBookmark(n)) n];
    r.sort((a, b) {
      final c = a.chapterIndex.compareTo(b.chapterIndex);
      return c != 0 ? c : a.startStableId.compareTo(b.startStableId);
    });
    return r;
  }

  /// Notes of one chapter (the reader draws them as underlines).
  static Future<List<BookNote>> notesOfChapter(String bookUrl, int chapterIndex) async {
    final list = await notesOfBook(bookUrl);
    return [for (final n in list) if (n.chapterIndex == chapterIndex) n];
  }

  /// Stores a copy with a fresh id (`bm_…` for bookmarks when [bookmark]), `createTime` / `updateTime` stamped now.
  static Future<BookNote> add(BookNote note, {bool bookmark = false}) => store.run((list) {
        final copy = BookNote.fromJson(note.toJson());
        if (copy.id.isEmpty || list.any((e) => e.id == copy.id)) copy.id = (bookmark ? bookmarkPrefix : '') + newId();
        final now = _now;
        if (copy.createTime == 0) copy.createTime = now;
        copy.updateTime = now;
        list.add(copy);
        return copy;
      });

  /// Replaces the note with the same id and stamps `updateTime`; unknown ids are appended.
  static Future<void> update(BookNote note) => store.run((list) {
        final copy = BookNote.fromJson(note.toJson())..updateTime = _now;
        final i = list.indexWhere((e) => e.id == note.id);
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  static Future<void> delete(String id) => store.run((list) => list.removeWhere((e) => e.id == id));

  static Future<void> deleteOfBook(String bookUrl) => store.run((list) => list.removeWhere((e) => e.bookUrl == bookUrl));

  /// Merge for the cloud list: same id -> the one with the later `updateTime` wins, unknown ids are added.
  /// Returns whether anything changed.
  static Future<bool> mergeRemote(List<BookNote> remote) => store.run((list) {
        var changed = false;
        for (final r in remote) {
          final i = list.indexWhere((e) => e.id == r.id);
          if (i < 0) {
            list.add(r);
            changed = true;
          } else if (r.updateTime > list[i].updateTime) {
            list[i] = r;
            changed = true;
          }
        }
        return changed;
      });

  static String exportJson() => jsonEncode([for (final n in store.items) n.toJson()]);

  /// Cloud sync of notes and bookmarks (`getBjs`, etag prefs key `bjetag`, switch `cloudmark`, member only like the switch).
  /// Three-way merge by note id; a note on both sides keeps the copy with the later `updateTime`. Null when the switch is off.
  static Future<CloudSyncResult?> syncCloud({CloudApi? api}) async {
    if (!UserSession.cloudmark) return null;
    await load();
    return store.lock.synchronized(() async {
      final result = await CloudSync.syncList(
        api: api ?? defaultCloudApi,
        kind: CloudKind.notes,
        itemName: 'notes',
        etagKey: PrefKeys.bjetag,
        encodeLocal: exportJson,
        mergeRemote: (text) async {
          final remote = [for (final e in Storage.jsondecode(text)) if (e is Map) BookNote.fromJson(Map<String, dynamic>.from(e))];
          final base = await CloudSync.loadBase('notes');
          final before = exportJson();
          store.items = CloudSync.merge3<BookNote>(
            local: store.items,
            remote: remote,
            key: (n) => n.id,
            base: base,
            both: (l, r) => r.updateTime > l.updateTime ? r : l,
          );
          final changed = exportJson() != before;
          if (changed) await store.save();
          return changed;
        },
      );
      await CloudSync.saveBase('notes', store.items.map((n) => n.id));
      return result;
    });
  }
}
