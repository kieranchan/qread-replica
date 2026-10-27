// pages/web/bookmark_manager_page.dart — the browser's bookmark list (收藏夹, data/chromemark.dart): search, edit, delete; tapping
// a bookmark returns its url to the browser. Original `_BookmarkManagerPageState` (strings 搜索书签... / 暂无书签 / 没有找到匹配的书签 /
// 编辑书签 / 名称 / 书签已更新 / 确认删除 / 确定要删除"…"吗？ / 已删除书签).
import 'package:flutter/material.dart';

import '../../data/chromemark.dart';
import '../../models/chromemark.dart';
import '../../util/toast.dart';

class BookmarkManagerPage extends StatefulWidget {
  const BookmarkManagerPage({super.key});

  @override
  State<BookmarkManagerPage> createState() => _BookmarkManagerPageState();
}

class _BookmarkManagerPageState extends State<BookmarkManagerPage> {
  final _search = TextEditingController();
  List<Chromemark> _all = [];

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    Chromemarks.load().then((v) {
      if (mounted) setState(() => _all = v);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Chromemark> get _shown {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((b) => b.title.toLowerCase().contains(q) || b.url.toLowerCase().contains(q)).toList();
  }

  Future<void> _edit(Chromemark b) async {
    final name = TextEditingController(text: b.title);
    final url = TextEditingController(text: b.url);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('编辑书签'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('bm_name'), controller: name, decoration: const InputDecoration(labelText: '名称')),
          TextField(key: const Key('bm_url'), controller: url, decoration: const InputDecoration(labelText: '网址')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          TextButton(key: const Key('bm_save'), onPressed: () => Navigator.of(c).pop(true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    await Chromemarks.store.run((list) {
      for (final e in list) {
        if (e.id == b.id) {
          e.title = name.text.trim();
          e.url = url.text.trim();
        }
      }
    });
    setState(() => _all = Chromemarks.bookmarks);
    Toast.show('书签已更新');
  }

  Future<void> _delete(Chromemark b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除"${b.title}"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await Chromemarks.delete(b.id);
    setState(() => _all = Chromemarks.bookmarks);
    Toast.show('已删除书签');
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('书签')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '搜索书签...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text(_all.isEmpty ? '暂无书签' : '没有找到匹配的书签', style: TextStyle(color: cs.outline)))
                : ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final b = shown[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text(b.title.isEmpty ? '?' : b.title.characters.first)),
                        title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(b.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(context).pop(b.url),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) => v == 'edit' ? _edit(b) : _delete(b),
                          itemBuilder: (c) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
