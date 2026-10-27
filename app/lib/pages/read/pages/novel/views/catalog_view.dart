// pages/read/pages/novel/views/catalog_view.dart — the reader's drawer: 目录 (chapters, current one marked, read ones dimmed, reverse
// order "目录倒序"), 书签 and 笔记 of the book. Original: the catalog part of `_NovelViewState` (0x572220 "目录" / "目录加载出错：" / "换源" /
// "返回") and the bookmark list that listens to `BookMark.bookmarkVersion`; notes jump with "笔记跳转" (0x899378), "笔记章节不存在".
import 'package:flutter/material.dart';

import '../../../../../data/note_data_n.dart';
import '../../../../../models/note.dart';
import '../../../../../read/api/readapi.dart';
import '../../../../../util/toast.dart';
import '../../../../../widget/note_sheet.dart';
import 'reader_host.dart';

class CatalogView extends StatefulWidget {
  final ReaderHost host;
  const CatalogView({super.key, required this.host});

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  /// "目录倒序" of the drawer (display only; `Book.reverseCatalog` reverses the source's list when it is loaded).
  bool _reverse = false;
  List<BookNote> _marks = [];
  List<BookNote> _notes = [];
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = widget.host.book.bookUrl;
    final marks = await NoteDataN.bookmarksOfBook(url);
    final notes = await NoteDataN.notesOfBook(url);
    if (!mounted) return;
    setState(() {
      _marks = marks;
      _notes = notes;
    });
  }

  void _scrollToCurrent() {
    if (!_scroll.hasClients) return;
    final n = widget.host.chapters.length;
    final i = _reverse ? n - 1 - widget.host.chapterIndex : widget.host.chapterIndex;
    final target = (i * 48.0 - 200).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(target);
  }

  Future<void> _go(int chapter, {int? offset}) async {
    if (chapter < 0 || chapter >= widget.host.chapters.length) {
      Toast.show('笔记章节不存在');
      return;
    }
    Navigator.of(context).pop();
    await widget.host.jumpToChapter(chapter, offset: offset);
  }

  Widget _chapters() {
    final host = widget.host;
    final list = host.chapters;
    final reads = ReadApi.parseRead(host.book.readchapter).toSet();
    final primary = Theme.of(context).colorScheme.primary;
    return ListView.builder(
      controller: _scroll,
      itemExtent: 48,
      itemCount: list.length,
      itemBuilder: (context, k) {
        final i = _reverse ? list.length - 1 - k : k;
        final c = list[i];
        final cur = i == host.chapterIndex;
        return ListTile(
          dense: true,
          title: Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cur ? primary : (reads.contains(i) ? Theme.of(context).disabledColor : null),
              fontWeight: c.isVolume ? FontWeight.bold : null,
            ),
          ),
          trailing: c.isPay || c.isVip ? const Icon(Icons.lock_outline, size: 16) : null,
          onTap: () => _go(i),
        );
      },
    );
  }

  Widget _noteList(List<BookNote> list, {required bool bookmarks}) {
    if (list.isEmpty) return Center(child: Text(bookmarks ? '暂无书签' : '暂无笔记'));
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = list[i];
        return ListTile(
          title: Text(n.chapterName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            bookmarks || n.noteContent.isEmpty ? n.selectedText : '${n.selectedText}\n${n.noteContent}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _go(n.chapterIndex, offset: n.startStableId),
          onLongPress: () async {
            if (bookmarks) {
              await NoteDataN.delete(n.id);
              Toast.show('删除成功');
            } else {
              final r = await showNoteEditSheet(context, n);
              if (r == null) return;
              if (r.delete) {
                await NoteDataN.delete(n.id);
              } else {
                n
                  ..color = r.color
                  ..noteContent = r.content;
                await NoteDataN.update(n);
              }
            }
            await _load();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            title: Text(widget.host.book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('共${widget.host.chapters.length}章'),
            trailing: IconButton(
              tooltip: '目录倒序',
              icon: const Icon(Icons.swap_vert),
              onPressed: () => setState(() => _reverse = !_reverse),
            ),
          ),
          TabBar(controller: _tabs, tabs: const [Tab(text: '目录'), Tab(text: '书签'), Tab(text: '笔记')]),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_chapters(), _noteList(_marks, bookmarks: true), _noteList(_notes, bookmarks: false)],
            ),
          ),
        ],
      ),
    );
  }
}
