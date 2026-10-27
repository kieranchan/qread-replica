// data/chromemark.dart — bookmarks (收藏夹) of the in-app browser. File-store key `chromemark` (JSON list of [Chromemark]).
//
// Original: `Chromemarks` (`_bookmarks` 0x4978, `_debookmarks` 0x4980 = defaults, `_lock` 0x4968; load 0x10dadf4: an empty stored
// list gives the defaults; save 0xfc8c5c prints `收藏夹保存失败…`, and `更新至云端` when the cloud flag is on).
// The four default bookmarks come from the initializer sub_923250 (ids 0, 11, 2, 3; `createdAt` = now).
import '../models/chromemark.dart';
import 'list_store.dart';

abstract class Chromemarks {
  /// `_debookmarks`: 源仓库, 源论坛, 百度, bing.
  static List<Chromemark> defaults() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      Chromemark(id: '0', title: '源仓库', url: 'https://yckceo.vip/', createdAt: now),
      Chromemark(id: '11', title: '源论坛', url: 'https://ycoo.net', createdAt: now),
      Chromemark(id: '2', title: '百度', url: 'https://m.baidu.com', createdAt: now),
      Chromemark(id: '3', title: 'bing', url: 'https://www.bing.com/', createdAt: now),
    ];
  }

  static final ListStore<Chromemark> store = ListStore<Chromemark>(
    'chromemark',
    fromJson: Chromemark.fromJson,
    toJson: (c) => c.toJson(),
    defaults: defaults,
    label: '收藏夹',
  );

  static List<Chromemark> get bookmarks => store.items;

  static Future<List<Chromemark>> load({bool force = false}) => store.load(force: force);

  static Future<bool> save() => store.save();

  /// Adds a bookmark unless the url is already there (then the title is updated). Returns the stored bookmark.
  static Future<Chromemark> add(String title, String url) => store.run((list) {
        final i = list.indexWhere((e) => e.url == url);
        if (i >= 0) {
          list[i].title = title;
          return list[i];
        }
        final c = Chromemark(id: newId(), title: title, url: url, createdAt: DateTime.now().millisecondsSinceEpoch);
        list.add(c);
        return c;
      });

  static Future<void> delete(String id) => store.run((list) => list.removeWhere((e) => e.id == id));

  static bool contains(String url) => store.items.any((e) => e.url == url);

  /// Moves the bookmark to a new index (drag and drop in the list).
  static Future<void> move(int from, int to) => store.run((list) {
        if (from < 0 || from >= list.length) return;
        final c = list.removeAt(from);
        list.insert(to.clamp(0, list.length), c);
      });
}
