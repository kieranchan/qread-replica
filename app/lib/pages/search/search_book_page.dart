// pages/search/search_book_page.dart — 搜索 (`SearchBookPage`, `_SearchBookPageState extends BasePage`).
//
// Recovered: search field 「搜索书名、作者」, history (file-store key `historysearch`, 「搜索历史」 + 「清除」, 「搜索历史记录读取失败」 /
// 「历史记录保存失败」), progress 「正在搜索中...」 「已搜索 n/m」, result tabs 「包含匹配」 「精确匹配」 「全部结果」 「书架搜索」 (last tab in
// prefs `currentTab`), sort dialog 「排序方式」 (「默认排序」 「字数从大到小」 「字数从小到大」), source choice 「选择书源」 (prefs
// `searchUrls`, JSON list of source urls) or 「搜索分类」 / 「选择搜索分类」 (prefs `searchCategory`, a source group), messages
// 「您当前没有书源，请先添加书源」, 「您当前所有书源都已被禁用请先启用书源」, 「当前未选择任何书源只显示书架搜索结果！」, 「搜索错误: 」.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/bookself.dart';
import '../../data/source.dart';
import '../../models/book.dart';
import '../../models/source.dart';
import '../../storage/storage.dart';
import '../../util/toast.dart';
import '../../widget/base_page.dart';
import '../../widget/book/booklist.dart';
import '../book/book_detail_page.dart';
import 'search.dart';

abstract class SearchPrefs {
  static const String historyKey = 'historysearch';
  static const String tabKey = 'currentTab';
  static const String urlsKey = 'searchUrls';
  static const String categoryKey = 'searchCategory';
  static const int historyMax = 30;

  static Future<List<String>> history() async {
    try {
      return [for (final e in Storage.jsondecode(await Storage.read(historyKey))) '$e'];
    } catch (e) {
      Toast.show('搜索历史记录读取失败', iserror: true);
      return [];
    }
  }

  static Future<void> addHistory(String key) async {
    final list = await history();
    list
      ..remove(key)
      ..insert(0, key);
    if (list.length > historyMax) list.removeRange(historyMax, list.length);
    try {
      await Storage.write(historyKey, jsonEncode(list));
    } catch (e) {
      debugPrint('历史记录保存失败 $e');
    }
  }

  static Future<void> clearHistory() => Storage.write(historyKey, '[]');

  static List<String> get urls {
    final t = Storage.getString(urlsKey);
    if (t.isEmpty) return [];
    try {
      return [for (final e in jsonDecode(t) as List) '$e'];
    } catch (_) {
      return [];
    }
  }

  static Future<void> setUrls(List<String> v) => Storage.setString(urlsKey, v.isEmpty ? '' : jsonEncode(v));
  static String get category => Storage.getString(categoryKey);
  static Future<void> setCategory(String v) => Storage.setString(categoryKey, v);
}

class SearchBookPage extends StatefulWidget {
  /// Pre-filled key; searching starts at once when not empty.
  final String searchKey;

  /// Restrict to these sources (otherwise the saved choice / all enabled sources).
  final List<Source>? sources;

  const SearchBookPage({super.key, this.searchKey = '', this.sources});

  @override
  State<SearchBookPage> createState() => _SearchBookPageState();
}

class _SearchBookPageState extends BasePage<SearchBookPage> with SingleTickerProviderStateMixin {
  static const tabs = ['包含匹配', '精确匹配', '全部结果', '书架搜索'];
  static const sorts = ['默认排序', '字数从大到小', '字数从小到大'];

  late final TextEditingController _ctl = TextEditingController(text: widget.searchKey);
  late final TabController _tab = TabController(length: tabs.length, vsync: this, initialIndex: Storage.getInt(SearchPrefs.tabKey, 0).clamp(0, tabs.length - 1));
  List<String> _history = [];
  Search? _search;
  int _sort = 0;

  @override
  void initState() {
    super.initState();
    _tab.addListener(() {
      if (!_tab.indexIsChanging) Storage.setString(SearchPrefs.tabKey, '${_tab.index}');
      update();
    });
    _init();
  }

  Future<void> _init() async {
    await Sourcedata.load();
    await BookSelfN.load();
    _history = await SearchPrefs.history();
    update();
    if (widget.searchKey.isNotEmpty) await _start(widget.searchKey);
  }

  @override
  void dispose() {
    _search?.cancel();
    _search?.revision.removeListener(update);
    _ctl.dispose();
    _tab.dispose();
    super.dispose();
  }

  /// The sources to search: explicit list > saved url choice > saved category > every enabled source. Null = none usable.
  List<Source>? _sources() {
    if (widget.sources != null) return widget.sources;
    final all = Sourcedata.sources;
    if (all.isEmpty) {
      Toast.show('您当前没有书源，请先添加书源');
      return null;
    }
    final enabled = [for (final m in Sourcedata.enabledRaw) Source.fromJson(m)];
    if (enabled.isEmpty) {
      Toast.show('您当前所有书源都已被禁用请先启用书源');
      return null;
    }
    final urls = SearchPrefs.urls;
    if (urls.isNotEmpty) return enabled.where((s) => urls.contains(s.bookSourceUrl)).toList();
    final cat = SearchPrefs.category;
    if (cat.isNotEmpty) return [for (final m in Sourcedata.ofGroup(cat)) if (Sourcedata.enabledRaw.contains(m)) Source.fromJson(m)];
    return enabled;
  }

  Future<void> _start(String key) async {
    key = key.trim();
    if (key.isEmpty) return;
    FocusScope.of(context).unfocus();
    await _search?.cancel();
    _search?.revision.removeListener(update);
    await SearchPrefs.addHistory(key);
    _history = await SearchPrefs.history();
    final sources = _sources();
    if (sources != null && sources.isEmpty) Toast.show('当前未选择任何书源只显示书架搜索结果！');
    final s = Search(key, sources: sources ?? const []);
    s.revision.addListener(update);
    update(() => _search = s);
    if (sources != null && sources.isNotEmpty) {
      s.start();
    } else {
      _tab.index = 3;
    }
  }

  List<Book> _results() {
    final s = _search;
    if (s == null) return [];
    if (_tab.index == 3) {
      return [for (final b in BookSelfN.books) if (b.name.contains(s.key) || b.author.contains(s.key)) b];
    }
    final hits = switch (_tab.index) { 0 => s.contains, 1 => s.exact, _ => List<SearchHit>.of(s.hits) };
    if (_sort == 1) hits.sort((a, b) => wordCountValue(b.book.wordCount).compareTo(wordCountValue(a.book.wordCount)));
    if (_sort == 2) hits.sort((a, b) => wordCountValue(a.book.wordCount).compareTo(wordCountValue(b.book.wordCount)));
    return [for (final h in hits) h.book];
  }

  Future<void> _chooseSort() async {
    final v = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('排序方式'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < sorts.length; i++)
            ChoiceOption<int>(value: i, current: _sort, title: sorts[i]),
        ]),
      ),
    );
    if (v != null) update(() => _sort = v);
  }

  Future<void> _chooseSources() async {
    await Sourcedata.load();
    final all = Sourcedata.sources;
    final sel = SearchPrefs.urls.toSet();
    if (!mounted) return;
    final r = await showDialog<Set<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('选择书源'),
          content: SizedBox(
            width: 400,
            height: 420,
            child: ListView(children: [
              for (final s in all)
                CheckboxListTile(
                  value: sel.contains(s.bookSourceUrl),
                  title: Text(s.bookSourceName),
                  subtitle: s.bookSourceGroup.isEmpty ? null : Text(s.bookSourceGroup),
                  onChanged: (v) => set(() => v == true ? sel.add(s.bookSourceUrl) : sel.remove(s.bookSourceUrl)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(<String>{}), child: const Text('清除')),
            ElevatedButton(onPressed: () => Navigator.of(c).pop(sel), child: const Text('确定')),
          ],
        ),
      ),
    );
    if (r == null) return;
    await SearchPrefs.setUrls(r.toList());
    if (r.isNotEmpty) await SearchPrefs.setCategory('');
    update();
  }

  Future<void> _chooseCategory() async {
    await Sourcedata.load();
    if (!mounted) return;
    final groups = Sourcedata.groups;
    final cur = SearchPrefs.category;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('选择搜索分类'),
        content: SizedBox(
          width: 360,
          child: ListView(shrinkWrap: true, children: [
            ChoiceOption<String>(value: '', current: cur, title: '全部'),
            for (final g in groups) ChoiceOption<String>(value: g, current: cur, title: g),
          ]),
        ),
      ),
    );
    if (r == null) return;
    await SearchPrefs.setCategory(r);
    if (r.isNotEmpty) await SearchPrefs.setUrls([]);
    update();
  }

  Widget _historyView() {
    if (_history.isEmpty) return const SizedBox.shrink();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Text('搜索历史', style: TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton(
          key: const Key('history_clear'),
          onPressed: () async {
            await SearchPrefs.clearHistory();
            update(() => _history = []);
          },
          child: const Text('清除'),
        ),
      ]),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final h in _history)
          ActionChip(
            key: Key('history_$h'),
            label: Text(h),
            onPressed: () {
              _ctl.text = h;
              _start(h);
            },
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = _search;
    final results = _results();
    final cat = SearchPrefs.category;
    final urls = SearchPrefs.urls;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('search_input'),
          controller: _ctl,
          autofocus: widget.searchKey.isEmpty,
          textInputAction: TextInputAction.search,
          onSubmitted: _start,
          decoration: const InputDecoration(hintText: '搜索书名、作者', border: InputBorder.none),
        ),
        actions: [
          if (s?.running == true)
            IconButton(key: const Key('search_stop'), icon: const Icon(Icons.stop_circle_outlined), onPressed: () => s!.cancel())
          else
            IconButton(key: const Key('search_go'), icon: const Icon(Icons.search), onPressed: () => _start(_ctl.text)),
          IconButton(tooltip: '排序方式', icon: const Icon(Icons.sort), onPressed: _chooseSort),
        ],
        bottom: s == null
            ? null
            : TabBar(controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t)]),
      ),
      body: s == null
          ? _historyView()
          : Column(children: [
              if (s.running || s.total > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(children: [
                    if (s.running) const Text('正在搜索中... '),
                    Text('已搜索 ${s.done}/${s.total}', key: const Key('search_progress')),
                  ]),
                ),
              if (s.running) LinearProgressIndicator(value: s.total == 0 ? null : s.done / s.total, minHeight: 2),
              Expanded(
                child: BookList(
                  key: const Key('search_list'),
                  books: results,
                  islist: true,
                  ishistory: false,
                  onTap: (b) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: b))),
                ),
              ),
            ]),
      bottomNavigationBar: SafeArea(
        child: Row(children: [
          Expanded(
            child: TextButton.icon(
              key: const Key('search_sources'),
              onPressed: _chooseSources,
              icon: const Icon(Icons.library_books_outlined),
              label: Text(urls.isEmpty ? '选择书源' : '选择书源 (${urls.length})'),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              key: const Key('search_category'),
              onPressed: _chooseCategory,
              icon: const Icon(Icons.list),
              label: Text(cat.isEmpty ? '搜索分类' : cat),
            ),
          ),
        ]),
      ),
    );
  }
}
