// pages/web/chrome_inapp.dart — the in-app browser (浏览器): address bar (opens web/search_page.dart, plain words are searched with
// `https://quark.sm.cn/s?q=` as in the original), bookmark star, progress, start page of bookmark tiles, back / forward / home /
// refresh / menu (书签, 阅读模式, UA设置), cookies saved into the engine's CookieStore after every page.
//
// Original `_ChromePageState` (build 0x5d73a8, InAppWebView 0x5d81d4, policy 0xfcdba4, bookmark tiles 0x5d8b38, menu sheet
// 0x5d9cd8, UA dialog 0x5da7d8 / 0xfceb00 `UA设置已应用,重新打开页面后生效`, reading mode 0xfcec20 + hint dialog 0x5e5c30
// `neverShowReadingModeHint`, star 0xfd1494 `已从收藏夹移除` / `已添加到收藏夹`, search 0xfd1934 + history 0xfd1cf8, cookie save
// 0xfce524 `保存cookie成功 `).
import 'package:flutter/material.dart';

import '../../common/nav.dart';
import '../../data/chromemark.dart';
import '../../models/book.dart';
import '../../models/chromemark.dart';
import '../../storage/storage.dart';
import '../../util/legado/cookie_jar.dart';
import '../../util/toast.dart';
import 'bookmark_manager_page.dart';
import 'chrome.dart';
import 'search_page.dart';
import 'web_engine.dart';
import 'webview.dart';

/// Search engine of the address bar (0x5e6938).
const String webSearchUrl = 'https://quark.sm.cn/s?q=';

/// What the address bar does with [text]: an url is loaded, a bare domain gets `https://`, anything else is searched.
String addressToUrl(String text) {
  final t = text.trim();
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  if (!t.contains(' ') && RegExp(r'^[\w-]+(\.[\w-]+)+(:\d+)?(/.*)?$').hasMatch(t)) return 'https://$t';
  return '$webSearchUrl${Uri.encodeQueryComponent(t)}';
}

class ChromeInappPage extends StatefulWidget {
  final String? url;
  const ChromeInappPage({super.key, this.url});

  @override
  State<ChromeInappPage> createState() => _ChromeInappPageState();
}

class _ChromeInappPageState extends State<ChromeInappPage> {
  late final QWebController _c;
  bool _home = true;
  List<Chromemark> _marks = [];

  @override
  void initState() {
    super.initState();
    _c = WebEngine.create();
    _c.onNavigate = (u) => webNavigationPolicy(context, u);
    _c.onPageFinished = _saveCookie;
    final ua = UAType.current.ua;
    if (ua != null) _c.setUserAgent(ua);
    _loadMarks();
    final u = widget.url;
    if (u != null && u.isNotEmpty) _open(u);
  }

  Future<void> _loadMarks() async {
    final m = await Chromemarks.load();
    if (mounted) setState(() => _marks = List.of(m));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    setState(() => _home = false);
    final cookie = CookieStore.getCookie(url);
    if (cookie.isNotEmpty) {
      try {
        await _c.setCookie(url, cookie);
      } catch (_) {}
    }
    await _c.loadUrl(url);
  }

  /// 0xfce524.
  Future<void> _saveCookie(String url) async {
    if (!url.startsWith('http')) return;
    try {
      final c = await _c.pageCookie();
      if (c.isNotEmpty) {
        CookieStore.replaceCookie(url, c);
        debugPrint('保存cookie成功 $url');
      }
    } catch (e) {
      debugPrint('保存Cookie失败:$e');
    }
  }

  /// 0xfd1934: the address bar opens the search page; its answer is loaded or searched.
  Future<void> _search() async {
    final text = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (c) => SearchPage(initial: _home ? '' : _c.url.value)));
    if (text == null || text.trim().isEmpty) return;
    await WebSearchHistory.add(text);
    await _open(addressToUrl(text));
  }

  /// 0xfd1494.
  Future<void> _bookmarkCurrentPage() async {
    if (_home) {
      Toast.show('请先打开一个网站');
      return;
    }
    final url = _c.url.value;
    final i = Chromemarks.bookmarks.indexWhere((b) => b.url == url);
    if (i >= 0) {
      await Chromemarks.delete(Chromemarks.bookmarks[i].id);
      Toast.show('已从收藏夹移除');
    } else {
      await Chromemarks.add(_c.title.value.isEmpty ? url : _c.title.value, url);
      Toast.show('已添加到收藏夹');
    }
    await _loadMarks();
  }

  Future<void> _goBack() async {
    if (_home) return;
    if (await _c.canGoBack()) {
      await _c.goBack();
    } else {
      setState(() => _home = true);
    }
  }

  Future<void> _goForward() async {
    if (_home) {
      if (_c.url.value.isNotEmpty) setState(() => _home = false);
      return;
    }
    if (await _c.canGoForward()) await _c.goForward();
  }

  void _refresh() {
    if (!_home) _c.reload();
  }

  void _showBrowserMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              _menuItem(c, Icons.bookmarks_outlined, '书签', _openBookmarks),
              _menuItem(c, Icons.menu_book_outlined, '阅读模式', _readingMode),
              _menuItem(c, Icons.devices_outlined, 'UA设置', _uaDialog),
            ],
          ),
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
        ]),
      ),
    );
  }

  Widget _menuItem(BuildContext sheet, IconData icon, String label, Future<void> Function() action) => InkWell(
        onTap: () {
          Navigator.of(sheet).pop();
          action();
        },
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon), const SizedBox(height: 6), Text(label)]),
      );

  Future<void> _openBookmarks() async {
    final url = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (c) => const BookmarkManagerPage()));
    await _loadMarks();
    if (url != null && url.isNotEmpty) await _open(url);
  }

  Future<void> _uaDialog() async {
    var sel = UAType.current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('UA设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in UAType.values)
                ListTile(
                  dense: true,
                  leading: Icon(t == sel ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  title: Text(t.label),
                  onTap: () => set(() => sel = t),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await UAType.save(sel);
    await _c.setUserAgent(sel.ua);
    Toast.show('UA设置已应用,重新打开页面后生效');
  }

  /// 0xfcec20: turns the current table-of-contents page into a book (`@chrome` origin) and opens its detail page.
  Future<void> _readingMode() async {
    if (_home || _c.url.value.isEmpty) {
      Toast.show('请先打开一个网站');
      return;
    }
    if (_c.progress.value < 100) Toast.show('建议先等待网站加载完成后再使用阅读模式');
    if ((await Storage.read('neverShowReadingModeHint')) != 'true') {
      var never = false;
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: const Text('进入阅读模式'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('阅读模式可以将目录页转换成书本，请确保在目录页使用阅读模式。', style: TextStyle(height: 1.5)),
              InkWell(
                onTap: () => set(() => never = !never),
                child: Row(children: [Checkbox(value: never, onChanged: (v) => set(() => never = v ?? false)), const Text('不再提示')]),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
              ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('进入阅读模式')),
            ],
          ),
        ),
      );
      if (go != true) return;
      if (never) await Storage.write('neverShowReadingModeHint', 'true');
    }
    try {
      // TODO(asm 0xfcec20): the original parses the page into a book with its `@chrome` rules (`getinfo(` 0xfcf350) before opening
      // the detail page; the replica hands the url to the detail page of the shelf area.
      final book = Book(bookUrl: _c.url.value, tocUrl: _c.url.value, name: _c.title.value, origin: '@chrome');
      if (mounted) await Nav.openBook(context, book);
    } catch (e) {
      Toast.show('进入阅读模式失败:$e');
    }
  }

  Widget _startPage() {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (c, box) {
        final cols = (box.maxWidth / 96).floor().clamp(3, 8);
        return GridView.count(
          crossAxisCount: cols,
          padding: const EdgeInsets.all(16),
          children: [
            for (final b in _marks)
              InkWell(
                key: ValueKey('mark_${b.id}'),
                onTap: () => _open(b.url),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: cs.primaryContainer,
                    child: Text(b.title.isEmpty ? '?' : b.title.characters.first, style: TextStyle(color: cs.onPrimaryContainer)),
                  ),
                  const SizedBox(height: 6),
                  Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ]),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    key: const Key('chrome_address'),
                    onTap: _search,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                      child: ValueListenableBuilder<String>(
                        valueListenable: _c.title,
                        builder: (c, t, _) => Text(
                          _home ? '搜索或输入网址' : (t.isEmpty ? _c.url.value : t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _home ? cs.outline : cs.onSurface),
                        ),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: _c.url,
                  builder: (c, u, _) => IconButton(
                    key: const Key('chrome_star'),
                    icon: Icon(!_home && Chromemarks.contains(u) ? Icons.star : Icons.star_border),
                    onPressed: _bookmarkCurrentPage,
                  ),
                ),
              ]),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _c.progress,
              builder: (c, p, _) => _home || p >= 100 ? const SizedBox(height: 2) : LinearProgressIndicator(value: p / 100, minHeight: 2),
            ),
            Expanded(
              child: IndexedStack(index: _home ? 0 : 1, children: [_startPage(), RepaintBoundary(child: _c.build(context))]),
            ),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            IconButton(tooltip: '后退', icon: const Icon(Icons.arrow_back_ios_new), onPressed: _goBack),
            IconButton(tooltip: '前进', icon: const Icon(Icons.arrow_forward_ios), onPressed: _goForward),
            IconButton(tooltip: '主页', icon: const Icon(Icons.home_outlined), onPressed: () => setState(() => _home = true)),
            IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _refresh),
            IconButton(key: const Key('chrome_menu'), tooltip: '菜单', icon: const Icon(Icons.menu), onPressed: _showBrowserMenu),
          ]),
        ),
      ),
    );
  }
}
