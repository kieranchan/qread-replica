// pages/book/book_edit_page.dart — 编辑书籍信息 (`BookEditPage`, `_BookEditPageState extends BasePage`).
//
// Fields: cover (tap → 「请选择图片获取方式」: 书源搜索 / 上传图片 / 输入链接 (「输入图片链接」)), name, author, intro, group. 「书源搜索」
// (「搜索封面」) searches the book name in the enabled sources and offers the other covers found (「正在搜索...」, 「搜索进度: n/m」,
// 「未找到其他封面」, 「搜索封面失败: 」). Saving writes through the shelf (`setBasic` 0x100652c, group, author).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/bookself.dart';
import '../../models/book.dart';
import '../../read/api/read_file_store.dart';
import '../../read/api/read_storage_root.dart';
import '../../util/toast.dart';
import '../../widget/book/book_file_picker.dart';
import '../../widget/book_page.dart';
import '../../widget/image/cached_cover_image.dart';
import '../search/book_search_service.dart';

class BookEditPage extends StatefulWidget {
  final Book book;
  const BookEditPage({super.key, required this.book});

  @override
  State<BookEditPage> createState() => _BookEditPageState();
}

class _BookEditPageState extends BookApiPage<BookEditPage> {
  late final _name = TextEditingController(text: widget.book.name);
  late final _author = TextEditingController(text: widget.book.author);
  late final _intro = TextEditingController(text: widget.book.intro);
  late String _cover = widget.book.coverUrl;
  late String _group = widget.book.bookgroup;

  @override
  void dispose() {
    _name.dispose();
    _author.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final way = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('请选择图片获取方式'), children: [
        SimpleDialogOption(onPressed: () => Navigator.of(c).pop(0), child: const Text('书源搜索')),
        SimpleDialogOption(onPressed: () => Navigator.of(c).pop(1), child: const Text('上传图片')),
        SimpleDialogOption(onPressed: () => Navigator.of(c).pop(2), child: const Text('输入链接')),
      ]),
    );
    switch (way) {
      case 0:
        await _searchCover();
      case 1:
        final f = await BookFilePicker.instance.pickImage();
        if (f == null) return;
        final dir = ReadStorageRoot.ensureSub(ReadStorageRoot.covers);
        final dest = File('${dir.path}/${ReadFileStore.md5Hex(widget.book.bookUrl)}${p.extension(f.path)}');
        await f.copy(dest.path);
        update(() => _cover = '${ReadStorageRoot.covers}/${p.basename(dest.path)}');
      case 2:
        final url = await input('输入图片链接', initial: _cover.startsWith('http') ? _cover : '');
        if (url != null && url.trim().isNotEmpty) update(() => _cover = url.trim());
    }
  }

  Future<void> _searchCover() async {
    final covers = <String>{};
    var done = 0, total = 0;
    late StateSetter refresh;
    var finished = false;
    StreamSubscription<List<Book>>? sub;
    final dialog = showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        refresh = set;
        return AlertDialog(
          title: const Text('搜索封面'),
          content: SizedBox(
            width: 400,
            height: 360,
            child: Column(children: [
              Text(finished ? (covers.isEmpty ? '未找到其他封面' : '搜索进度: $done/$total') : '正在搜索... 搜索进度: $done/$total'),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.count(crossAxisCount: 3, childAspectRatio: 0.72, mainAxisSpacing: 8, crossAxisSpacing: 8, children: [
                  for (final u in covers)
                    InkWell(onTap: () => Navigator.of(c).pop(u), child: CachedCoverImage(url: u, title: widget.book.name)),
                ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('取消'))],
        );
      }),
    );
    try {
      final stream = BookSearchService.instance.search(widget.book.name);
      sub = stream.listen((list) {
        done++;
        for (final b in list) {
          if (b.name == widget.book.name && b.coverUrl.isNotEmpty && b.coverUrl != _cover) covers.add(b.coverUrl);
        }
        try {
          refresh(() {});
        } catch (_) {}
      }, onDone: () {
        finished = true;
        try {
          refresh(() {});
        } catch (_) {}
      }, onError: (Object e) => Toast.show('搜索封面过程发生错误: $e', iserror: true));
    } catch (e) {
      Toast.show('搜索封面失败: $e', iserror: true);
    }
    final chosen = await dialog;
    await sub?.cancel();
    debugPrint('搜索结束：对话框已关闭');
    if (chosen != null) update(() => _cover = chosen);
  }

  Future<void> _save() async {
    final url = widget.book.bookUrl;
    if (BookSelfN.contains(url)) {
      final live = BookSelfN.get(url)!;
      if (_author.text.trim() != live.author) {
        live.author = _author.text.trim();
        await Bookdata.save();
      }
      await BookSelfN.setBasic(url, name: _name.text.trim(), coverUrl: _cover, intro: _intro.text);
      if (_group != live.bookgroup) await BookSelfN.setGroup(url, _group);
      Toast.show('修改成功');
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑书籍信息'),
        centerTitle: true,
        actions: [IconButton(key: const Key('edit_save'), icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: InkWell(
            key: const Key('edit_cover'),
            onTap: _pickCover,
            child: CachedCoverImage(url: _cover, title: _name.text, width: 110, height: 150, borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(key: const Key('edit_name'), controller: _name, decoration: const InputDecoration(labelText: '书名')),
        TextField(key: const Key('edit_author'), controller: _author, decoration: const InputDecoration(labelText: '作者')),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('分组'),
          trailing: Text(_group.isEmpty ? kAllGroup : _group),
          onTap: () async {
            final g = await chooseGroup(current: _group);
            if (g != null) update(() => _group = g);
          },
        ),
        TextField(key: const Key('edit_intro'), controller: _intro, minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: '简介')),
      ]),
    );
  }
}
