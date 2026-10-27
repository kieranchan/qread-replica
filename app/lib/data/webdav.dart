// data/webdav.dart — the user's network-drive servers (WebDAV, plus the token based Baidu / Weiyun / CloudDrive2 entries).
// File-store key `webdav` (JSON list of [WebDavServer]); the server chosen for "cloud books" is the string key
// `cloudBooksWebDavServer` (a server id).
//
// Original: `WebDav` (`_servers` 0x49a0, `_lock` 0x4990; load 0x10db36c, save 0x10a52a8 / 0x10a53c0, closures 0x10a5088 0x10a5440 0x10a6d70).
import '../models/webdavserver.dart';
import '../storage/storage.dart';
import 'list_store.dart';

abstract class WebDav {
  static const String selectedKey = 'cloudBooksWebDavServer';

  static final ListStore<WebDavServer> store = ListStore<WebDavServer>(
    'webdav',
    fromJson: WebDavServer.fromJson,
    toJson: (s) => s.toJson(),
    label: 'WebDAV',
  );

  static List<WebDavServer> get servers => store.items;

  static Future<List<WebDavServer>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  static WebDavServer? byId(String id) {
    for (final s in store.items) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Adds a server (fresh id when empty or taken) and returns the stored copy.
  static Future<WebDavServer> add(WebDavServer server) => store.run((list) {
        final copy = WebDavServer.fromJson(server.toJson());
        if (copy.id.isEmpty || list.any((e) => e.id == copy.id)) copy.id = newId();
        list.add(copy);
        return copy;
      });

  /// Replaces the server with the same id (appends when unknown).
  static Future<void> update(WebDavServer server) => store.run((list) {
        final copy = WebDavServer.fromJson(server.toJson());
        final i = list.indexWhere((e) => e.id == server.id);
        if (i < 0) {
          list.add(copy);
        } else {
          list[i] = copy;
        }
      });

  /// Deletes a server; the "cloud books" selection is cleared when it pointed at it.
  static Future<void> delete(String id) async {
    await store.run((list) => list.removeWhere((e) => e.id == id));
    if (selectedId == id) await Storage.remove(selectedKey);
  }

  /// The id of the server used for cloud books, `''` when none.
  static String get selectedId => Storage.getString(selectedKey);

  static WebDavServer? get selected => byId(selectedId);

  static Future<void> select(String id) => Storage.setString(selectedKey, id);
}
