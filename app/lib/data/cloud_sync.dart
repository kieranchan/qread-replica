// data/cloud_sync.dart — the generic cloud list sync every synced list uses (bookshelf, sources, RSS, notes, groups).
//
// Wire contract (docs/API.md "Cloud sync", result codes): per list kind an etag getter, an update-url getter that takes the client's
// last etag, and a list getter returning the JSON text the client uploaded; `setItemJsonFile(item=<kind>)` replaces the list.
// The original's bookshelf flow (0xe6766c): switch check -> `getBookUpdateurl(etag)` -> `更新书架` -> list -> merge -> upload ->
// status check (`获取云端信息失败` / `云端书架同步失败`).
//
// Update-url result, as the original reads it (0xe6766c: `== "-1"` or `== ""` enters the 更新书架 merge branch, any other value
// skips it and is remembered in static 0x1f4c): `'-1'` = failure, `''` = the cloud has newer data or nothing yet, any other value =
// the client's etag is current (the value is the server etag). The owner's server answers exactly that.
//   1. `updateUrl(kind, lastEtag)`; `'-1'` -> [CloudSyncException] `获取云端信息失败`
//   2. `''` -> download the list (if any) and let the caller merge it into the local list
//   3. when the local list differs from what was last synchronised (or the cloud was empty / never synced) -> upload it
//   4. store the cloud etag (prefs [etagKey]) and the md5 of the synchronised local text for the next dirty check
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../api/userapi.dart';
import '../storage/storage.dart';
import 'cloud_api.dart';

class CloudSyncException implements Exception {
  final String message;
  const CloudSyncException(this.message);
  @override
  String toString() => message;
}

class CloudSyncResult {
  /// The cloud had newer data and it was merged into the local list.
  final bool pulled;

  /// The local list was uploaded.
  final bool pushed;

  /// The local list changed because of the merge (the caller already saved it).
  final bool localChanged;

  /// The etag stored after the sync.
  final String etag;
  const CloudSyncResult({this.pulled = false, this.pushed = false, this.localChanged = false, this.etag = ''});

  bool get nothingToDo => !pulled && !pushed;
  @override
  String toString() => 'pulled=$pulled pushed=$pushed localChanged=$localChanged etag=$etag';
}

abstract class CloudSync {
  static String md5Of(String text) => crypto.md5.convert(utf8.encode(text)).toString();

  static String _syncedKey(String etagKey) => '$etagKey.syncedmd5';

  /// The keys that were present after the last successful sync of a list (the "base" of the three-way merge). Without it a
  /// merge cannot tell "added on one device" from "deleted on the other".
  static Future<Set<String>> loadBase(String name) async {
    final text = await Storage.read('syncbase_$name');
    return {for (final e in Storage.jsondecode(text)) '$e'};
  }

  static Future<void> saveBase(String name, Iterable<String> keys) async {
    Storage.keepOnClean('syncbase_$name');
    await Storage.write('syncbase_$name', jsonEncode(keys.toList()));
  }

  /// Three-way merge of two lists identified by [key]:
  ///  * in both: [both] decides (default: keep the local item)
  ///  * only local: kept when it is new (not in [base]); dropped when [base] has it (the other side deleted it)
  ///  * only remote: added when it is new; dropped when [base] has it (this side deleted it)
  /// Local order is kept; new remote items follow in remote order.
  static List<T> merge3<T>({
    required List<T> local,
    required List<T> remote,
    required String Function(T) key,
    required Set<String> base,
    T Function(T local, T remote)? both,
  }) {
    final remoteByKey = <String, T>{for (final r in remote) key(r): r};
    final localKeys = <String>{for (final l in local) key(l)};
    final out = <T>[];
    final added = <String>{};
    for (final l in local) {
      final k = key(l);
      if (!added.add(k)) continue; // duplicate key in the local list: keep the first
      final r = remoteByKey[k];
      if (r == null) {
        if (base.contains(k)) {
          added.remove(k);
        } else {
          out.add(l);
        }
      } else {
        out.add(both == null ? l : both(l, r));
      }
    }
    for (final r in remote) {
      final k = key(r);
      if (!localKeys.contains(k) && !base.contains(k) && added.add(k)) out.add(r);
    }
    return out;
  }

  /// `yyyy-MM-dd HH:mm:ss` (local time), the text stored under `lastSyncTime`.
  static String formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Runs one sync of [kind].
  ///
  /// [encodeLocal] gives the current local list as JSON text. [mergeRemote] receives the downloaded text, merges it into the
  /// local list, saves it and returns true when the local list changed; it is only called when newer cloud data exists.
  /// [itemName] is the `setItemJsonFile` item (`books|rss|sources|notes|groups`).
  static Future<CloudSyncResult> syncList({
    required CloudApi api,
    required CloudKind kind,
    required String itemName,
    required String etagKey,
    required String Function() encodeLocal,
    required Future<bool> Function(String remoteText) mergeRemote,
  }) async {
    final lastEtag = Storage.getString(etagKey);
    final upd = await api.updateUrl(kind, lastEtag);
    if (upd == '-1') throw const CloudSyncException('获取云端信息失败');

    var pulled = false;
    var localChanged = false;
    var cloudEtag = upd;
    if (upd.isEmpty) {
      final text = await api.list(kind);
      if (text.isNotEmpty) {
        localChanged = await mergeRemote(text);
        pulled = true;
        cloudEtag = await api.etag(kind);
      }
    }

    final localText = encodeLocal();
    final localMd5 = md5Of(localText);
    final neverSynced = lastEtag.isEmpty;
    final dirty = neverSynced || localChanged || localMd5 != Storage.getString(_syncedKey(etagKey));
    var pushed = false;
    if (dirty && !(pulled && cloudEtag == localMd5)) {
      await api.setItemJsonFile(itemName, localText);
      pushed = true;
      final fresh = await api.etag(kind);
      if (fresh.isEmpty) throw const CloudSyncException('云端同步失败');
      cloudEtag = fresh;
    } else if (cloudEtag.isEmpty) {
      // nothing stored in the cloud and nothing to upload (an empty local list): still record the state
      cloudEtag = await api.etag(kind);
    }
    await Storage.setString(etagKey, cloudEtag);
    await Storage.setString(_syncedKey(etagKey), localMd5);
    return CloudSyncResult(pulled: pulled, pushed: pushed, localChanged: localChanged, etag: cloudEtag);
  }
}
