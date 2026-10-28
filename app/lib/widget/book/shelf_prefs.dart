// widget/book/shelf_prefs.dart — the bookshelf's prefs keys (docs/SETTINGS.md, settings_keys.tsv) with their defaults.
// All values are strings in prefs (Storage.getString/setString), typed here.
import '../../storage/storage.dart';

abstract class ShelfPrefs {
  /// `listtype`: 2 = grid (宫格, sized by `bookshelfScale2`, toggle 0xf82b90), anything else = list (列表); 0x8ee0e4 reads it with
  /// `toInt` and turns 0 (unset) into 1, so a fresh shelf is a list.
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

  /// 未读章节 (「书架页是否显示未读章节红点」, read settings 0x7fe684): prefs `needupdate` read with `toInt` at start-up (0x10dbb68)
  /// into a static: 1 = 完整显示 (the count), 2 = 不显示, anything else (0 = unset) = 缩略显示 (a red dot).
  static const String unreadKey = 'needupdate';
  static const int unreadFull = 1;
  static const int unreadHidden = 2;
  static const int unreadDot = 0;

  /// Sort modes of `booklistordrer` (comparators of 0xe66264): 0 last read first (`durChapterTime`), 1 name, 4 latest update
  /// first (`latestChapterTime`), anything else = stored (manual) order; dragging a book writes 3 (0xf6fdf4).
  static const int manualSort = 3;
  static const Map<int, String> sortModes = {0: '最近阅读', 1: '书名', 4: '最近更新', manualSort: '手动排序'};

  /// Whether the stored order is shown (drag to reorder is on).
  static bool get isManualSort => !const {0, 1, 4}.contains(sort);

  static String _s(String k) => Storage.getString(k);
  static int _i(String k, int def) => _s(k).isEmpty ? def : Storage.getInt(k, def);
  static bool _b(String k, bool def) => _s(k).isEmpty ? def : Storage.getBool(k, def);

  static bool get isGrid => _i(listtypeKey, 1) == 2;
  static Future<void> setGrid(bool grid) => Storage.setString(listtypeKey, grid ? '2' : '1');

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
