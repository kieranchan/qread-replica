// pages/book/book_detail_page.dart — 书籍详情 (`BookDetailPage`, `_BookDetailPageState extends BookApiPage`, 156 functions).
//
// Recovered layout and behaviour (pool strings in code order): blurred cover header with name / author (long press → SearchBookPage;
// with 事件监听 the taps / long presses on name, author and kind labels go to the 时光源 page first, util/source/source_events.dart),
// 定制按钮 in the app bar, kind labels, intro (`@onclick:` buttons run their js in the source page) (简介, widget/book/intro_view.dart: `<useweb>` / `@html:` / `<usehtml>` / text), info rows 类型：/ 编码：/
// 规则：/ 分组：/ 最新：/ 进度： with 「修改」 (选择书本类型 / 修改编码 / 修改目录规则 for local TXT), the 目录 row opening
// BookCatalogPage, bottom buttons 加入书架 + 阅读; 「更多」 menu: 编辑书本, 关闭更新/开启更新, 更换书源, 重新载入, 阅读记录, 删除书本,
// 书籍信息 (书源地址 / 书籍地址 + 「复制地址」 → 「地址已复制」), 本地缓存 (range dialog: 「请输入要缓存的章节范围：」 …, errors
// 「请输入有效的数字！」「章节编号不能为负数！」「结束章节必须大于起始章节！」). Messages: 「当前书本已在书架，可点击右上角再点击更换书源进行快速换源」,
// 「是否重新载入书本，如果软件内置规则变化可能会导致目录或者正文变化？」 → 「正在重新载入」 / 「重新载入成功」 / 「载入失败:」, 「换源成功」,
// 「换源失败，书架已存在当前书本」, 「当前书本已被删除」.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/nav.dart';
import '../../data/bookself.dart';
import '../../data/source.dart';
import '../../data/txtrule.dart';
import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../read/local_book_importer.dart';
import '../../storage/book_reading_time_storage.dart';
import '../../util/source/image_meta.dart';
import '../../util/source/source_events.dart';
import '../../util/toast.dart';
import '../../widget/book/intro_view.dart';
import '../../widget/book/toc_cache.dart';
import '../../widget/book_page.dart';
import '../../widget/image/cached_cover_image.dart';
import '../../widget/ui/q_popup_menu_button.dart';
import '../search/book_search_service.dart';
import '../search/search_book_page.dart';
import 'book_catalog_page.dart';
import 'book_change_yuan.dart';
import 'book_edit_page.dart';
import 'download_manager_page.dart';

class BookDetailPage extends StatefulWidget {
  final Book book;

  /// Opened from the shelf (the original's `iscentos` flag): the book is known to be on the shelf.
  final bool iscentos;

  const BookDetailPage({super.key, required this.book, this.iscentos = false});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends BookApiPage<BookDetailPage> {
  late Book _book = Book.fromJson(widget.book.toJson());
  List<BookChapter>? _chapters;
  String _error = '';
  bool _loading = true;

  bool get _onShelf => BookSelfN.contains(_book.bookUrl);
  bool get _local => isLocalShelfBook(_book);

  @override
  void initState() {
    super.initState();
    BookSelfN.revision.addListener(_shelfChanged);
    _load();
  }

  @override
  void dispose() {
    BookSelfN.revision.removeListener(_shelfChanged);
    super.dispose();
  }

  void _shelfChanged() {
    final b = BookSelfN.get(_book.bookUrl);
    if (b != null) update(() => _book = Book.fromJson(b.toJson()));
  }

  Future<void> _load({bool refresh = false}) async {
    update(() {
      _loading = true;
      _error = '';
    });
    await BookSelfN.load();
    final shelf = BookSelfN.get(_book.bookUrl);
    if (shelf != null) _book = Book.fromJson(shelf.toJson());
    try {
      if (!_local && (refresh || !_book.isinfo || _book.intro.isEmpty)) {
        final info = await BookSearchService.instance.bookInfo(_book);
        _book = info..isinfo = true;
        if (_onShelf) await BookSelfN.updateInfo(_book);
      }
      _chapters = await TocCache.load(_book, refresh: refresh);
    } catch (e) {
      _error = '$e';
    }
    update(() => _loading = false);
  }

  Future<void> _addToShelf() async {
    if (_onShelf) {
      Toast.show('当前书本已在书架，可点击右上角再点击更换书源进行快速换源');
      return;
    }
    final c = _chapters;
    if (c != null && c.isNotEmpty) {
      _book
        ..totalChapterNum = c.length
        ..latestChapterTitle = c.last.name;
      if (_book.durChapterTitle.isEmpty) _book.durChapterTitle = c.first.name;
    }
    final stored = await addToShelf(_book);
    if (stored != null) update(() => _book = Book.fromJson(stored.toJson()));
  }

  Future<void> _read({int? index}) => Nav.openReader(context, _book, chapterIndex: index, chapters: _chapters);

  Future<void> _openCatalog() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookCatalogPage(book: _book, chapters: _chapters)));
    _shelfChanged();
  }

  Future<void> _changeSource() async {
    final found = await Navigator.of(context).push(MaterialPageRoute<Book>(builder: (_) => BookChangeYuan(book: _book)));
    if (found == null || !mounted) return;
    if (!await confirm('提示', '是否确认把书源更换为${sourceNameOf(found.origin)}?')) return;
    if (found.bookUrl != _book.bookUrl && BookSelfN.contains(found.bookUrl)) {
      Toast.show('换源失败，书架已存在当前书本', iserror: true);
      return;
    }
    try {
      final stored = _onShelf ? await replaceShelfBook(_book, found) : found;
      _book = Book.fromJson(stored.toJson());
      await _load(refresh: true);
      Toast.show('换源成功');
    } catch (e) {
      Toast.show('换源失败: $e', iserror: true);
    }
  }

  Future<void> _reload() async {
    if (!await confirm('操作提示', '是否重新载入书本，如果软件内置规则变化可能会导致目录或者正文变化？')) return;
    Toast.show('正在重新载入');
    await _load(refresh: true);
    Toast.show(_error.isEmpty ? '重新载入成功' : '载入失败:$_error', iserror: _error.isNotEmpty);
  }

  Future<void> _readRecord() async {
    final secs = await BookReadingTimeStorage.bookSeconds(bookKey(_book));
    if (!mounted) return;
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
    final text = secs == 0 ? '暂无阅读记录' : '${h > 0 ? '$h小时' : ''}${m > 0 ? '$m分钟' : ''}$s秒';
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('阅读记录'),
        content: Text(secs == 0 ? text : '总阅读时间 $text'),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('确定'))],
      ),
    );
  }

  Future<void> _bookInfoDialog() async {
    Widget row(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                Toast.show('地址已复制');
              },
              child: const Text('复制地址'),
            ),
          ]),
          SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          const SizedBox(height: 8),
        ]);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('书籍信息'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [row('书源地址', _book.origin), row('书籍地址', _book.bookUrl)])),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('确定'))],
      ),
    );
  }

  /// 「本地缓存」: chapter range dialog, then a download task.
  Future<void> _cacheToLocal() async {
    if (DownloadTasks.taskOf(_book.bookUrl) != null) {
      Toast.show('已有缓存任务正在进行中');
      return;
    }
    final a = TextEditingController(), b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('本地缓存'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('请输入要缓存的章节范围：'),
          TextField(key: const Key('cache_from'), controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '起始章节', hintText: '留空表示从第1章开始')),
          TextField(key: const Key('cache_to'), controller: b, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '结束章节', hintText: '留空表示缓存全部章节')),
          const SizedBox(height: 8),
          const Text('提示：章节编号从1开始，结束章节必须大于起始章节，留空则缓存全部', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          ElevatedButton(key: const Key('cache_ok'), onPressed: () => Navigator.of(c).pop(true), child: const Text('确认缓存')),
        ],
      ),
    );
    final fromText = a.text.trim(), toText = b.text.trim();
    a.dispose();
    b.dispose();
    if (ok != true) return;
    final from = fromText.isEmpty ? 1 : int.tryParse(fromText);
    final to = toText.isEmpty ? null : int.tryParse(toText);
    if (from == null || (toText.isNotEmpty && to == null)) {
      Toast.show('请输入有效的数字！', iserror: true);
      return;
    }
    if (from < 0 || (to ?? 0) < 0) {
      Toast.show('章节编号不能为负数！', iserror: true);
      return;
    }
    if (to != null && to <= from) {
      Toast.show('结束章节必须大于起始章节！', iserror: true);
      return;
    }
    Toast.show('准备缓存...');
    await DownloadTasks.start(_book, from: from - 1 < 0 ? 0 : from - 1, to: to == null ? null : to - 1, chapters: _chapters);
  }

  Future<void> _changeType() async {
    final t = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('选择书本类型'), children: [
        for (final e in const {0: '小说', 1: '听书', 2: '漫画', 4: '短剧'}.entries)
          SimpleDialogOption(onPressed: () => Navigator.of(c).pop(e.key), child: Text(e.value)),
      ]),
    );
    if (t == null) return;
    _book.type_ = t;
    if (_onShelf) await BookSelfN.setType(_book.bookUrl, t);
    Toast.show('书本类型已更新为: ${bookTypeLabel(t)}');
    update();
  }

  Future<void> _changeCharset() async {
    final cs = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('修改编码'), children: [
        for (final e in const ['UTF-8', 'GBK', 'UTF16BE', 'UTF16LE']) SimpleDialogOption(onPressed: () => Navigator.of(c).pop(e), child: Text(e)),
      ]),
    );
    if (cs == null) return;
    try {
      _book.charset = cs;
      await BookSelfN.updateToc(_book.bookUrl, charset: cs);
      _chapters = await const LocalBookImporter().loadChapters(_book, reparse: true);
      update();
    } catch (e) {
      Toast.show('修改编码失败！', iserror: true);
    }
  }

  Future<void> _changeTocRule() async {
    await Txtruledata.load();
    if (!mounted) return;
    final rules = Txtruledata.enabled;
    final r = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('修改目录规则'), children: [
        for (var i = 0; i < rules.length; i++) SimpleDialogOption(onPressed: () => Navigator.of(c).pop(i), child: Text(rules[i].name)),
      ]),
    );
    if (r == null) return;
    try {
      _chapters = await const LocalBookImporter().loadChapters(_book, txtRules: [rules[r]], reparse: true);
      final c = _chapters!;
      if (c.isNotEmpty) await BookSelfN.updateToc(_book.bookUrl, latestTitle: c.last.name, totalChapters: c.length);
      update();
    } catch (e) {
      Toast.show('修改目录规则失败！', iserror: true);
    }
  }

  Future<void> _more(String v) async {
    switch (v) {
      case 'edit_book':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookEditPage(book: _book)));
        _shelfChanged();
      case 'openupdate':
      case 'colseupdate':
        try {
          await BookSelfN.setUpdate(_book.bookUrl, v == 'colseupdate');
          Toast.show('操作成功');
        } catch (e) {
          Toast.show('操作失败:$e', iserror: true);
        }
      case 'change_source':
        await _changeSource();
      case 're':
        await _reload();
      case 'record':
        await _readRecord();
      case 'delete':
        if (await deleteBooks([_book]) && mounted) Navigator.of(context).pop();
      case 'bookurl':
        await _bookInfoDialog();
      case 'cachetolocal':
        await _cacheToLocal();
      case 'bookvariable':
        await editBookVariable(_book);
      case 'login':
        await Nav.openNamed(context, 'source_login', arguments: _book.origin);
    }
  }

  /// 事件监听 (util/source/source_events.dart): [event] goes to the source page with a loading veil when the source listens;
  /// true when the page consumed it.
  Future<bool> _event(String event) async {
    if (!SourceEvents.listens(_book.origin)) return false;
    return withLoading(() => SourceEvents.send(_book.origin, event, _book));
  }

  /// Long press on the name / author (0xfb797c / 0xfb7668): the event first, then (not consumed) a search for [key].
  Future<void> _longPressSearch(String event, String key) async {
    if (await _event(event) || !mounted || key.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchBookPage(searchKey: key)));
  }

  /// 定制按钮 (0xfb49e8): `clickCustomButton` whether the source listens or not.
  Future<void> _customButton() => withLoading(() => SourceEvents.send(_book.origin, SourceEvents.clickCustomButton, _book));

  /// `@onclick:` buttons of an html intro (0x5ad5f0): the js runs in the page of the book's 时光源 (not for 轻阅读 sources).
  Future<void> _introJs(String js) async {
    final raw = Sourcedata.byUrl(_book.origin);
    if (raw == null || raw['isqread'] == true || '${raw['isqread']}' == 'true') return;
    debugPrint('run $js');
    await ParagraphComments.click(js, sourceUrl: _book.origin);
  }

  String sourceNameOf(String url) {
    final m = Sourcedata.byUrl(url);
    return m == null ? url : '${m['bookSourceName'] ?? url}';
  }

  Widget _infoRow(String label, String value, {VoidCallback? onEdit}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Expanded(child: Text(value.isEmpty ? '无' : value, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (onEdit != null) InkWell(onTap: onEdit, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('修改', style: TextStyle(color: Color(0xFF7CB7B2))))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final b = _book;
    final scheme = Theme.of(context).colorScheme;
    final txt = _local && b.bookUrl.toLowerCase().endsWith('.txt');
    final c = _chapters;
    final progress = c == null || c.isEmpty ? '' : '${(b.durChapterIndex + 1).clamp(1, c.length)}/${c.length} ${b.durChapterTitle}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('书籍信息'),
        centerTitle: true,
        actions: [
          if (!_local && SourceEvents.hasCustomButton(b.origin))
            IconButton(key: const Key('detail_custom_button'), icon: const Icon(Icons.circle_outlined), onPressed: _customButton),
          QPopupMenuButton<String>(
            key: const Key('detail_more'),
            tooltip: '更多',
            items: [
              const QPopupMenuItem(value: 'edit_book', title: '编辑书本', icon: Icons.edit),
              if (!_local && _onShelf)
                b.update
                    ? const QPopupMenuItem(value: 'openupdate', title: '开启更新', icon: Icons.notifications)
                    : const QPopupMenuItem(value: 'colseupdate', title: '关闭更新', icon: Icons.notifications_off),
              if (!_local) const QPopupMenuItem(value: 'change_source', title: '更换书源', icon: Icons.swap_horiz),
              const QPopupMenuItem(value: 're', title: '重新载入', icon: Icons.refresh),
              const QPopupMenuItem(value: 'record', title: '阅读记录', icon: Icons.timer_outlined),
              if (!_local) const QPopupMenuItem(value: 'cachetolocal', title: '本地缓存', icon: Icons.download),
              if (!_local) const QPopupMenuItem(value: 'bookvariable', title: '书本变量', icon: Icons.settings),
              if (!_local) const QPopupMenuItem(value: 'login', title: '书源登录', icon: Icons.login),
              const QPopupMenuItem(value: 'bookurl', title: '书籍信息', icon: Icons.info_outline),
              if (_onShelf) const QPopupMenuItem(value: 'delete', title: '删除书本', icon: Icons.delete_outline, destructive: true),
            ],
            onSelected: _more,
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CachedCoverImage(url: b.coverUrl, title: b.name, author: b.author, width: 100, height: 140, borderRadius: BorderRadius.circular(8)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () => _event(SourceEvents.clickBookName),
                onLongPress: () => _longPressSearch(SourceEvents.longClickBookName, b.name),
                child: Text(b.name, key: const Key('detail_name'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 6),
              InkWell(
                key: const Key('detail_author'),
                onTap: () => _event(SourceEvents.clickAuthor),
                onLongPress: () => _longPressSearch(SourceEvents.longClickAuthor, b.author),
                child: Text(b.author.isEmpty ? '未知' : b.author, style: TextStyle(color: scheme.primary)),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final k in b.kind.split(RegExp('[,，\\s]+')).where((s) => s.isNotEmpty).take(6))
                  GestureDetector(
                    onTap: () => _event(SourceEvents.clickBookLabel),
                    onLongPress: () => _event(SourceEvents.longClickBookLabel),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(6)),
                      child: Text(k, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                if (b.wordCount.isNotEmpty) Text(b.wordCount, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        _infoRow('类型：', bookTypeLabel(b.type_), onEdit: _changeType),
        if (txt) _infoRow('编码：', b.charset, onEdit: _changeCharset),
        if (txt) _infoRow('规则：', '', onEdit: _changeTocRule),
        if (!_local) _infoRow('来源：', sourceNameOf(b.origin)),
        if (_onShelf) _infoRow('分组：', b.bookgroup.isEmpty ? kAllGroup : b.bookgroup, onEdit: () => moveToGroup([BookSelfN.get(b.bookUrl) ?? b])),
        _infoRow('最新：', b.latestChapterTitle.isNotEmpty ? b.latestChapterTitle : (c?.isNotEmpty == true ? c!.last.name : '')),
        if (_onShelf) _infoRow('进度：', progress),
        const Divider(height: 24),
        const Text('简介', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 6),
        if (b.intro.isEmpty) Text(_loading ? '加载中' : '无', style: const TextStyle(height: 1.6)) else IntroView(intro: b.intro, onClickJs: _introJs),
        const Divider(height: 24),
        ListTile(
          key: const Key('detail_toc'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.list),
          title: const Text('目录'),
          subtitle: _loading
              ? const Text('加载中')
              : _error.isNotEmpty
                  ? Text('加载失败: $_error', maxLines: 2, overflow: TextOverflow.ellipsis)
                  : Text('共 ${c?.length ?? 0} 章'),
          trailing: _error.isNotEmpty ? TextButton(onPressed: () => _load(refresh: true), child: const Text('重试')) : const Icon(Icons.chevron_right),
          onTap: c == null ? null : _openCatalog,
        ),
        if (c != null)
          for (final ch in c.take(5))
            ListTile(dense: true, contentPadding: const EdgeInsets.only(left: 16), title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => _read(index: ch.index)),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('detail_add'),
                onPressed: _onShelf ? (_local ? null : _changeSource) : _addToShelf,
                child: Text(_onShelf ? (_local ? '已在书架' : '更换书源') : '加入书架'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(key: const Key('detail_read'), onPressed: () => _read(), child: const Text('阅读'))),
          ]),
        ),
      ),
    );
  }
}
