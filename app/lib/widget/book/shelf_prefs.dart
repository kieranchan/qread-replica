// widget/book/shelf_prefs.dart — the bookshelf's prefs keys (docs/SETTINGS.md, settings_keys.tsv) with their defaults.
// All values are strings in prefs (Storage.getString/setString), typed here.
import '../../storage/storage.dart';

abstract class ShelfPrefs {
  /// `listtype` (default 1): 1 = grid (宫格), 0 = list (列表). TODO(asm 0x8ee0e4): which value is the grid is inferred from the default.
  static const String listtypeKey = 'listtype';

  /// `group`: the last selected group tab.
  static const String groupKey = 'group';

  /// `groupStyle` (default 1): 1 = group tabs under the app bar, 0 = group drop-down in the title.
  static const String groupStyleKey = 'groupStyle';

  /// `booklistordrer` [sic]: shelf sort mode, see [sortModes].
  static const String sortKey = 'booklistordrer';

  /// `showBookTypeOnCover` (default true): 听书/漫画/短剧 pill on covers.
  static const String showTypeKey = 'showBookTypeOnCover';

  /// `bookCoverShadow` (default true).
  static const String coverShadowKey = 'bookCoverShadow';

  /// `bookshelfColumns` / `bookshelfColumns2`: items per row for list / grid, 0 = automatic.
  static const String listColumnsKey = 'bookshelfColumns';
  static const String gridColumnsKey = 'bookshelfColumns2';

  /// `bookshelfScale` / `bookshelfScale2`: list / grid size in percent (50..200, default 100).
  static const String listScaleKey = 'bookshelfScale';
  static const String gridScaleKey = 'bookshelfScale2';

  /// `gridCard`: grid items drawn as cards.
  static const String gridCardKey = 'gridCard';

  /// `searchpppl`: search threads (default 6).
  static const String searchThreadsKey = 'searchpppl';

  /// 未读章节 (完整显示 / 不显示 / 缩略显示). TODO(asm 0x7fe684): the prefs key of this switch is not in the pool string list;
  /// the replica uses `bookshelfUnread` (0 = full count, 1 = hidden, 2 = dot).
  static const String unreadKey = 'bookshelfUnread';

  /// Sort modes of `booklistordrer` (comparators of 0xe66264): 0 last read first (`durChapterTime`), 1 name, 4 latest update
  /// first (`latestChapterTime`), anything else = stored (manual) order.
  static const Map<int, String> sortModes = {0: '最近阅读', 1: '书名', 4: '最近更新', 2: '手动排序'};

  static String _s(String k) => Storage.getString(k);
  static int _i(String k, int def) => _s(k).isEmpty ? def : Storage.getInt(k, def);
  static bool _b(String k, bool def) => _s(k).isEmpty ? def : Storage.getBool(k, def);

  static bool get isGrid => _i(listtypeKey, 1) == 1;
  static Future<void> setGrid(bool grid) => Storage.setString(listtypeKey, grid ? '1' : '0');

  static String get group => _s(groupKey);
  static Future<void> setGroup(String g) => Storage.setString(groupKey, g);

  static int get groupStyle => _i(groupStyleKey, 1);
  static int get sort => _i(sortKey, 0);
  static Future<void> setSort(int v) => Storage.setString(sortKey, '$v');
  static bool get showType => _b(showTypeKey, true);
  static bool get coverShadow => _b(coverShadowKey, true);
  static int get listColumns => _i(listColumnsKey, 0).clamp(0, 10);
  static int get gridColumns => _i(gridColumnsKey, 0).clamp(0, 10);
  static int get listScale => _i(listScaleKey, 100).clamp(50, 200);
  static int get gridScale => _i(gridScaleKey, 100).clamp(50, 200);
  static bool get gridCard => _b(gridCardKey, false);
  static int get unreadMode => _i(unreadKey, 0);
  static int get searchThreads => _i(searchThreadsKey, 6).clamp(1, 32);
}
