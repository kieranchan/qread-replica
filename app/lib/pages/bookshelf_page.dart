// pages/bookshelf_page.dart — 书架, the first tab.
//
// Original `_BookshelfPageState` (mixins BookApiPage, keep-alive, WidgetsBindingObserver, RouteAware). Recovered pieces:
//   app bar        sub_53a38c: title 「书架」 or the group drop-down (「分组」, groupStyle 0), layout toggle 「列表排序」/「宫格排序」,
//                  「搜索」, 「更多」 (sub_53b57c: 添加书籍 addbook, 添加配置 addconfig, 编辑书架 editbookshelf, 刷新书架 refreshbookshelf,
//                  分组管理 groupmanager, 查看日志 viewlog; handler 0xf75494)
//   group pages    PageView over the group tabs (`_pageController`, `group` pref), filter rules 0xe65d78 (see ShelfGroups)
//   sort           `_sortingbook` 0xe65494 / 0xe66264 with `booklistordrer`
//   list           BookList (`bookshelf_list<group>`), RefreshIndicator → update check (startNextTask 0xf6ede8: 「开始刷新:」,
//                  「刷新书籍失败: 」), empty state sub_533758 (「书架还是空的」 / 「分组还是空的」 / 「点击右上角导入书籍后开始阅读吧  :)」)
//   edit mode      bottom bar sub_52ea30 (「全选 (n/m)」, 「反选」, 「删除」, 「更多」) and the batch sheet 0x52f748 (移入分组, 刷新目录,
//                  批量下载, 刷新详情, 开启更新, 取消更新; 0xf6ac14 「确定要要开启/关闭这些书本的更新吗？」 [sic])
//   long press     `_showBookOperations` 0x53492c: cover + 「作者: 」「来源: 」「分组: 」, quick actions 本地文件 / 跳转网址 / 移动分组 /
//                  删除书籍, grid 0x53852c + handler 0xf736c4 (书本详情, 编辑书本, 更换书源, 关闭更新/开启更新, 书源登录, 编辑书源,
//                  书本变量, 清除缓存)
//   import         0xf78ca8 (「正在导入文件」, 「第n本书，导入失败:…!」, 「选择文件失败:」), url import dialog 0x53c8e0 (「网址导入」,
//                  「输入书籍网址链接」, 「例如：https://example.com/book」, 「请输入网址」), progress json 0xf7713c / 0xf771c8.
// Book `update == true` means "updates switched off" (0x5388c0 shows 开启更新 for it); local books are never refreshed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../common/nav.dart';
import '../data/bookself.dart';
import '../data/source.dart';
import '../data/user.dart';
import '../models/book.dart';
import '../read/local_book_importer.dart';
import '../util/toast.dart';
import '../widget/base_page.dart';
import '../widget/book/addbook.dart';
import '../widget/book/addset.dart';
import '../widget/book/book_file_picker.dart';
import '../widget/book/booklist.dart';
import '../widget/book/grouplist.dart';
import '../widget/book/shelf_prefs.dart';
import '../widget/book/toc_cache.dart';
import '../widget/book/url_save_book.dart';
import '../widget/book_page.dart';
import '../widget/image/cached_cover_image.dart';
import '../widget/ui/q_popup_menu_button.dart';
import 'book/book_change_yuan.dart';
import 'book/book_detail_page.dart';
import 'book/book_edit_page.dart';
import 'book/download_manager_page.dart';
import 'search/backbook_page.dart';
import 'search/book_search_service.dart';
import 'search/search_book_page.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => BookshelfPageState();
}

class BookshelfPageState extends BookApiPage<BookshelfPage> with AutomaticKeepAliveClientMixin {
  bool _loaded = false;
  bool _isGrid = true;
  String _group = kAllGroup;
  bool _isedit = false;
  final Set<String> _selected = {};
  final Set<String> _updating = {};
  final Set<String> _cancelled = {};
  bool _refreshing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    BookSelfN.revision.addListener(_changed);
    _isGrid = ShelfPrefs.isGrid;
    final g = ShelfPrefs.group;
    if (g.isNotEmpty) _group = g;
    _load();
  }

  @override
  void dispose() {
    BookSelfN.revision.removeListener(_changed);
    super.dispose();
  }

  void _changed() => update();

  Future<void> _load() async {
    await BookSelfN.load();
    await Groupdata.load();
    if (!groups.contains(_group)) _group = kAllGroup;
    update(() => _loaded = true);
  }

  /// Group tabs: 「全部」 then the visible groups.
  List<String> get groups => Groupdata.visible;

  /// `_sortingbook`: the books of [group] in the configured order.
  List<Book> booksOf(String group) {
    final list = [for (final b in BookSelfN.books) if (ShelfGroups.matches(b, group)) b];
    final mode = ShelfPrefs.sort;
    final sort = switch (mode) { 0 => BookSort.recentRead, 1 => BookSort.name, 4 => BookSort.recentUpdate, _ => BookSort.manual };
    return BookSelfN.sorted(list, sort);
  }

  /// `moveCallback` (0x534530 → 0xf6fc8c): dropping [dragged] on [target] switches the shelf to 手动排序 (`booklistordrer` = 3), keeps
  /// the order shown so far as the stored order and puts [dragged] at [target]'s place.
  Future<void> moveCallback(Book dragged, Book target) async {
    if (dragged.bookUrl == target.bookUrl) return;
    if (!ShelfPrefs.isManualSort) {
      // the order on screen becomes the stored order
      final shown = booksOf(kAllGroup).map((b) => b.bookUrl).toList();
      for (var i = 0; i < shown.length; i++) {
        final from = BookSelfN.books.indexWhere((b) => b.bookUrl == shown[i]);
        if (from >= 0 && from != i) await BookSelfN.move(from, i);
      }
    }
    await ShelfPrefs.setSort(ShelfPrefs.manualSort);
    final from = BookSelfN.books.indexWhere((b) => b.bookUrl == dragged.bookUrl);
    final to = BookSelfN.books.indexWhere((b) => b.bookUrl == target.bookUrl);
    if (from >= 0 && to >= 0) await BookSelfN.move(from, to);
    if (mounted) setState(() {});
  }

  Future<void> _selectGroup(String g) async {
    setState(() {
      _group = g;
      _selected.clear();
    });
    await ShelfPrefs.setGroup(g);
  }

  // ------------------------------------------------------------------------------------------------ open / operations

  Future<void> _open(Book b) => Nav.openReader(context, b);

  void showBookOperations(Book b) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => _BookOperationsSheet(book: b, onAction: (a) {
        Navigator.of(c).pop();
        _bookAction(b, a);
      }),
    );
  }

  /// 0xf736c4 and the quick actions of 0x53492c.
  Future<void> _bookAction(Book b, String action) async {
    switch (action) {
      case '书本详情':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: b)));
      case '编辑书本':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookEditPage(book: b)));
      case '更换书源':
        final found = await Navigator.of(context).push(MaterialPageRoute<Book>(builder: (_) => BookChangeYuan(book: b)));
        if (found != null) {
          await replaceShelfBook(b, found);
          Toast.show('换源成功');
        }
      case '关闭更新':
      case '开启更新':
        try {
          await BookSelfN.setUpdate(b.bookUrl, action == '关闭更新');
          Toast.show('操作成功');
        } catch (e) {
          Toast.show('操作失败:$e', iserror: true);
        }
      case '书源登录':
        await Nav.openNamed(context, 'source_login', arguments: b.origin);
      case '编辑书源':
        await Nav.openSourceEdit(context, Sourcedata.sourceByUrl(b.origin));
      case '书本变量':
        await editBookVariable(b);
      case '清除缓存':
        await clearBookCache(b);
      case '本地文件':
        final f = LocalBookImporter.fileOf(b);
        if (!f.existsSync()) {
          Toast.show('书本文件丢失', iserror: true);
          return;
        }
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
      case '跳转网址':
        if (b.bookUrl.startsWith('http')) await Nav.openNamed(context, 'webview', arguments: b.bookUrl);
      case '移动分组':
        await moveToGroup([b]);
      case '删除书籍':
        await deleteBooks([b]);
    }
  }

  // ---------------------------------------------------------------------------------------------- update check

  /// Pull to refresh (startNextTask 0xf6ede8): refreshes the table of contents of every web book whose updates are on, a few at a
  /// time (`searchpppl`), marking new chapters (`isredupdate`) through the shelf.
  Future<void> refreshBooks([List<Book>? only]) async {
    if (_refreshing) {
      Toast.show('你的操作太快了，请稍后再试');
      return;
    }
    final todo = (only ?? booksOf(_group)).where((b) => !isLocalShelfBook(b) && (only != null || !b.update)).toList();
    if (todo.isEmpty) return;
    _refreshing = true;
    update(() {
      _cancelled.clear();
      _updating.addAll(todo.map((b) => b.bookUrl));
    });
    var next = 0;
    Future<void> worker() async {
      while (next < todo.length && mounted) {
        final b = todo[next++];
        debugPrint('开始刷新:${b.name}');
        try {
          await TocCache.load(b, refresh: true);
        } catch (e) {
          debugPrint('刷新书籍失败: ${b.name}, 错误: $e');
          _cancelled.add(b.bookUrl);
        }
        update(() => _updating.remove(b.bookUrl));
      }
    }

    // thread count: `searchpppl` (搜索线程); the original's 更新线程 key is not recovered
    final n = ShelfPrefs.searchThreads.clamp(1, 16);
    try {
      await Future.wait([for (var i = 0; i < n; i++) worker()]);
    } catch (e) {
      debugPrint('批量刷新书籍异常: $e');
    } finally {
      _refreshing = false;
      update(() => _updating.clear());
    }
  }

  /// 「刷新详情」 of the selected books.
  Future<void> _refreshInfo(List<Book> books) async {
    for (final b in books.where((b) => !isLocalShelfBook(b))) {
      try {
        final info = await BookSearchService.instance.bookInfo(b);
        await BookSelfN.updateInfo(info);
      } catch (e) {
        debugPrint('刷新书籍失败: ${b.name}, 错误: $e');
      }
    }
    Toast.show('操作成功');
  }

  // ---------------------------------------------------------------------------------------------- import

  /// Imports book files (0xf78ca8) into the shelf; returns how many were added.
  Future<int> importFiles(List<File> files) async {
    if (files.isEmpty) return 0;
    Toast.show('正在导入文件');
    var n = 0;
    for (var i = 0; i < files.length; i++) {
      try {
        final local = await const LocalBookImporter().import(files[i]);
        final group = ShelfGroups.builtin.contains(_group) || _group == kAllGroup ? '' : _group;
        await BookSelfN.add(local.book..bookgroup = group);
        n++;
      } catch (e) {
        Toast.show('第${i + 1}本书，导入失败:$e!', iserror: true);
      }
    }
    if (n > 0) Toast.show('导入成功');
    return n;
  }

  Future<void> _importLocal() async {
    List<File> files;
    try {
      files = await BookFilePicker.instance.pickBooks();
    } catch (e) {
      Toast.show('选择文件失败:$e', iserror: true);
      return;
    }
    await importFiles(files);
  }

  /// 0x53c8e0: 「网址导入」 — the url is opened as a book page (detail through the engine).
  Future<void> _importUrl() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(children: [Icon(Icons.link), SizedBox(width: 12), Text('网址导入')]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('输入书籍网址链接'),
          const SizedBox(height: 8),
          TextField(key: const Key('url_import'), controller: ctl, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: '例如：https://example.com/book', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              if (ctl.text.trim().isEmpty) {
                Toast.show('请输入网址', iserror: true);
                return;
              }
              Navigator.of(c).pop(ctl.text.trim());
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (url == null || !mounted) return;
    // 0xf7701c → urlsaveBook (0xe69f74 / 0xe6a130): the first enabled local source whose bookUrlPattern matches opens the detail page
    await urlSaveBook(context, url, (bookUrl, origin) async {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: Book(bookUrl: bookUrl, origin: origin))));
    });
  }

  /// 0xf7713c / 0xf771c8: 「进度导入」 — a JSON list of books whose reading progress overwrites the shelf's (matched by bookUrl, then
  /// name + author).
  Future<void> _importProgress() async {
    if (!await confirm('操作确认', '确认要导入进度 json文件吗？')) return;
    File? f;
    try {
      f = await BookFilePicker.instance.pickJson();
    } catch (e) {
      Toast.show('选择文件失败:$e', iserror: true);
      return;
    }
    if (f == null) return;
    try {
      final list = jsonDecode(await f.readAsString());
      var n = 0;
      for (final e in (list is List ? list : const [])) {
        if (e is! Map) continue;
        final p = Book.fromJson(Map<String, dynamic>.from(e));
        final b = BookSelfN.get(p.bookUrl) ?? BookSelfN.books.where((x) => x.name == p.name && x.author == p.author).firstOrNull;
        if (b == null) continue;
        await BookSelfN.updateProgress(b.bookUrl, index: p.durChapterIndex, pos: p.durChapterPos, title: p.durChapterTitle);
        n++;
      }
      Toast.show(n > 0 ? '导入成功' : '导入失败:没有匹配的书籍!');
    } catch (e) {
      Toast.show('打开文件失败:$e', iserror: true);
    }
  }

  Future<void> _addBook() async {
    final r = await AddBookDialog.show(context);
    if (r == null || !mounted) return;
    switch (r.type) {
      case AddBookType.local:
        await _importLocal();
      case AddBookType.url:
        await _importUrl();
      case AddBookType.progress:
        await _importProgress();
      case AddBookType.backup:
        await BackbookPage.open(context); // 备份导入: pick a backup device first (AutoDeviceManagementDialog)
      case AddBookType.remote:
        await Nav.openNamed(context, 'wifi_page');
      case AddBookType.backend:
        await Nav.openNamed(context, 'qread_import');
    }
  }

  /// 「刷新书架」: cloud sync of shelf and groups when the cloud shelf is on, else a reload plus the update check.
  Future<void> _refreshShelf() async {
    try {
      if (UserSession.cloudbookself) {
        await Groupdata.syncCloud();
        await BookSelfN.syncCloud();
        Toast.show('同步书架成功');
      } else {
        await Bookdata.load(force: true);
        await refreshBooks();
      }
      update();
    } catch (e) {
      Toast.show('刷新书架失败:$e', iserror: true);
    }
  }

  Future<void> _more(String v) async {
    switch (v) {
      case 'addbook':
        await _addBook();
      case 'addconfig':
        final r = await AddConfigDialog.show(context);
        if (r != null && mounted) await Nav.openNamed(context, 'config_import', arguments: {'type': r.type.name});
      case 'editbookshelf':
        setState(() {
          _isedit = true;
          _selected.clear();
        });
      case 'refreshbookshelf':
        await _refreshShelf();
      case 'groupmanager':
        await Grouplist.show(context);
        if (!groups.contains(_group)) await _selectGroup(kAllGroup);
        update();
      case 'viewlog':
        await Nav.openNamed(context, 'viewlog');
      case 'sort':
        await _chooseSort();
      case 'download':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadManagerPage()));
    }
  }

  Future<void> _chooseSort() async {
    final cur = ShelfPrefs.sort;
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('书架排序'), children: [
        for (final e in ShelfPrefs.sortModes.entries)
          ChoiceOption<int>(value: e.key, current: cur, title: e.value),
      ]),
    );
    if (v != null) {
      await ShelfPrefs.setSort(v);
      update();
    }
  }

  // --------------------------------------------------------------------------------------------- edit mode

  void toggleSourceSelection(String bookUrl) => setState(() => _selected.contains(bookUrl) ? _selected.remove(bookUrl) : _selected.add(bookUrl));

  List<Book> get _selectedBooks => [for (final b in BookSelfN.books) if (_selected.contains(b.bookUrl)) b];

  void selectAll() => setState(() {
        final all = booksOf(_group).map((b) => b.bookUrl).toSet();
        if (_selected.containsAll(all)) {
          _selected.removeAll(all);
        } else {
          _selected.addAll(all);
        }
      });

  void invertSelection() => setState(() {
        for (final b in booksOf(_group)) {
          if (!_selected.remove(b.bookUrl)) _selected.add(b.bookUrl);
        }
      });

  Future<void> _delall() async {
    if (_selected.isEmpty) return;
    if (await deleteBooks(_selectedBooks)) setState(() => _selected.clear());
  }

  Future<void> _setUpdates(bool on) async {
    final books = _selectedBooks;
    if (books.isEmpty) return;
    if (!await confirm('操作提示', on ? '确定要要开启这些书本的更新吗？' : '确定要要关闭这些书本的更新吗？')) return;
    try {
      for (final b in books) {
        await BookSelfN.setUpdate(b.bookUrl, !on);
      }
      Toast.show('修改成功');
    } catch (e) {
      Toast.show('修改失败: $e', iserror: true);
    }
  }

  Future<void> _download(List<Book> books) async {
    Toast.show('准备缓存...');
    for (final b in books.where((b) => !isLocalShelfBook(b))) {
      await DownloadTasks.start(b);
    }
    Toast.show('操作成功');
  }

  /// 0x52f748: the batch sheet of the edit mode.
  Future<void> _showMoreActions() async {
    final books = _selectedBooks;
    if (books.isEmpty) return;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (icon, text) in const [
              (Icons.folder_outlined, '移入分组'),
              (Icons.list, '刷新目录'),
              (Icons.download, '批量下载'),
              (Icons.info_outline, '刷新详情'),
              (Icons.sync, '开启更新'),
              (Icons.sync_disabled, '取消更新'),
            ])
              ListTile(leading: Icon(icon), title: Text(text), onTap: () => Navigator.of(c).pop(text)),
          ]),
        ),
      ),
    );
    switch (v) {
      case '移入分组':
        await moveToGroup(books);
      case '刷新目录':
        await refreshBooks(books);
      case '批量下载':
        await _download(books);
      case '刷新详情':
        await _refreshInfo(books);
      case '开启更新':
        await _setUpdates(true);
      case '取消更新':
        await _setUpdates(false);
    }
  }

  Widget _editBar() {
    final books = booksOf(_group);
    final n = books.where((b) => _selected.contains(b.bookUrl)).length;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          TextButton(key: const Key('sel_all'), onPressed: selectAll, child: Text('全选 ($n/${books.length})')),
          TextButton(key: const Key('sel_invert'), onPressed: invertSelection, child: const Text('反选')),
          const Spacer(),
          TextButton(key: const Key('sel_delete'), onPressed: _delall, child: Text('删除', style: TextStyle(color: scheme.error))),
          TextButton(key: const Key('sel_more'), onPressed: _showMoreActions, child: const Text('更多')),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------ build

  Widget _empty(String group) {
    return LayoutBuilder(
      builder: (c, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: box.maxHeight,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.book_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(group == kAllGroup ? '书架还是空的' : '分组还是空的', key: const Key('shelf_empty'), style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 6),
              const Text('点击右上角导入书籍后开始阅读吧  :)', style: TextStyle(color: Colors.grey)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _groupTabs() {
    final gs = groups;
    if (gs.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final g in gs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(key: Key('group_$g'), label: Text(g), selected: g == _group, onSelected: (_) => _selectGroup(g)),
            ),
        ],
      ),
    );
  }

  Widget _title() {
    if (ShelfPrefs.groupStyle != 0 || groups.length <= 1) return const Text('书架');
    return QPopupMenuButton<String>(
      items: [for (final g in groups) QPopupMenuItem.check(value: g, title: g, checked: g == _group)],
      onSelected: _selectGroup,
      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(_group == kAllGroup ? '书架' : _group), const Icon(Icons.keyboard_arrow_down)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final books = booksOf(_group);
    return Scaffold(
      appBar: AppBar(
        title: _title(),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: _isedit
            ? [IconButton(key: const Key('shelf_done'), icon: const Icon(Icons.check), onPressed: () => setState(() => _isedit = false))]
            : [
                IconButton(
                  key: const Key('shelf_layout'),
                  tooltip: _isGrid ? '列表排序' : '宫格排序',
                  icon: Icon(_isGrid ? Icons.list : Icons.grid_view),
                  onPressed: () async {
                    setState(() => _isGrid = !_isGrid);
                    await ShelfPrefs.setGrid(_isGrid);
                  },
                ),
                IconButton(
                  key: const Key('shelf_search'),
                  tooltip: '搜索',
                  icon: const Icon(Icons.search),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchBookPage())),
                ),
                QPopupMenuButton<String>(
                  key: const Key('shelf_more'),
                  tooltip: '更多',
                  items: const [
                    QPopupMenuItem(value: 'addbook', title: '添加书籍', icon: Icons.add, sfSymbol: 'plus'),
                    QPopupMenuItem(value: 'addconfig', title: '添加配置', icon: Icons.library_add_outlined, sfSymbol: 'gearshape'),
                    QPopupMenuItem(value: 'editbookshelf', title: '编辑书架', icon: Icons.edit, sfSymbol: 'pencil'),
                    QPopupMenuItem(value: 'refreshbookshelf', title: '刷新书架', icon: Icons.refresh, sfSymbol: 'arrow.clockwise'),
                    QPopupMenuItem(value: 'groupmanager', title: '分组管理', icon: Icons.group, sfSymbol: 'person.2'),
                    QPopupMenuItem(value: 'sort', title: '书架排序', icon: Icons.sort),
                    QPopupMenuItem(value: 'download', title: '下载管理', icon: Icons.download),
                    QPopupMenuItem(value: 'viewlog', title: '查看日志', icon: Icons.info_outline, sfSymbol: 'info.circle'),
                  ],
                  onSelected: _more,
                ),
              ],
        bottom: ShelfPrefs.groupStyle == 0 ? null : PreferredSize(preferredSize: Size.fromHeight(groups.length > 1 ? 44 : 0), child: _groupTabs()),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: refreshBooks,
              child: books.isEmpty
                  ? _empty(_group)
                  : BookList(
                      key: Key('bookshelf_list$_group'),
                      books: books,
                      islist: !_isGrid,
                      isedit: _isedit,
                      isbookshelf: true,
                      showBookTypeOnCover: ShelfPrefs.showType,
                      selected: _selected,
                      updating: _updating,
                      cancelled: _cancelled,
                      onTap: _open,
                      showBookOperations: showBookOperations,
                      toggleSourceSelection: toggleSourceSelection,
                      moveCallback: moveCallback,
                    ),
            ),
      bottomNavigationBar: _isedit ? _editBar() : null,
    );
  }
}

/// 0x53492c: the long-press sheet.
class _BookOperationsSheet extends StatelessWidget {
  final Book book;
  final ValueChanged<String> onAction;

  const _BookOperationsSheet({required this.book, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local = isLocalShelfBook(book);
    Widget quick(String text, IconData icon, {Color? color}) => Expanded(
          child: InkWell(
            key: Key('op_$text'),
            onTap: () => onAction(text),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [Icon(icon, color: color), const SizedBox(height: 4), Text(text, style: TextStyle(fontSize: 12, color: color))]),
            ),
          ),
        );
    final ops = <(String, IconData)>[
      ('书本详情', Icons.info),
      ('编辑书本', Icons.edit),
      if (!local) ('更换书源', Icons.swap_horiz),
      if (!local) book.update ? ('开启更新', Icons.notifications) : ('关闭更新', Icons.notifications_off),
      if (!local) ('书源登录', Icons.login),
      if (!local) ('编辑书源', Icons.source),
      if (!local) ('书本变量', Icons.settings),
      if (!local) ('清除缓存', Icons.delete_sweep),
    ];
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 48, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CachedCoverImage(url: book.coverUrl, title: book.name, width: 65, height: 100, borderRadius: BorderRadius.circular(6)),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text('作者: ${book.author}', style: const TextStyle(fontSize: 14)),
                  Text('来源: ${sourceName(book)}', style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('分组: ${book.bookgroup.isEmpty ? kAllGroup : book.bookgroup}', style: const TextStyle(fontSize: 14)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              if (local) quick('本地文件', Icons.file_download) else quick('跳转网址', Icons.open_in_browser),
              quick('移动分组', Icons.layers),
              quick('删除书籍', Icons.delete, color: Colors.redAccent),
            ]),
            const Divider(height: 16),
            LayoutBuilder(builder: (c, box) {
              final per = (box.maxWidth / 70).floor().clamp(4, 8);
              final w = box.maxWidth / per;
              return Wrap(children: [
                for (final (title, icon) in ops)
                  SizedBox(
                    width: w,
                    child: InkWell(
                      key: Key('op_$title'),
                      onTap: () => onAction(title),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                            child: Icon(icon, size: 28),
                          ),
                          const SizedBox(height: 6),
                          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
              ]);
            }),
          ]),
        ),
      ),
    );
  }
}
