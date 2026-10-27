// pages/book/book_notes_page.dart — notes and highlights of one book: `BookNoteCard` (chapter, quoted text, note, time,
// `_TypePill` 「笔记」 / 「高亮」, `_ActionButton`s 「编辑」 / 「删除」), used by the catalog's 笔记 tab and as a page of its own.
// Data: `NoteDataN` (bookmarks — ids `bm_…` — are listed by the catalog's 书签 tab instead).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../common/nav.dart';
import '../../data/note_data_n.dart';
import '../../models/book.dart';
import '../../models/note.dart';
import '../../widget/base_page.dart';

/// `MM-dd HH:mm` this year, `yyyy-MM-dd HH:mm` otherwise (catalog formatter).
String noteTime(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateFormat(d.year == DateTime.now().year ? 'MM-dd HH:mm' : 'yyyy-MM-dd HH:mm').format(d);
}

Color noteColor(String c, Color fallback) {
  var s = c.replaceFirst('#', '').replaceFirst('0x', '').replaceFirst('0xff', '');
  if (s.length == 6) s = 'ff$s';
  final v = int.tryParse(s, radix: 16);
  return v == null ? fallback : Color(v);
}

class _TypePill extends StatelessWidget {
  final bool isNote;
  const _TypePill(this.isNote);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: isNote ? scheme.primaryContainer : scheme.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
      child: Text(isNote ? '笔记' : '高亮', style: const TextStyle(fontSize: 11)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionButton(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) =>
      TextButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label), style: TextButton.styleFrom(visualDensity: VisualDensity.compact));
}

class BookNoteCard extends StatelessWidget {
  final BookNote note;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const BookNoteCard({super.key, required this.note, this.onTap, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNote = note.noteContent.trim().isNotEmpty;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _TypePill(isNote),
              const SizedBox(width: 8),
              Expanded(child: Text(note.chapterName.isEmpty ? '未知章节' : note.chapterName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey))),
              Text(noteTime(note.updateTime), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: noteColor(note.color, scheme.primary), width: 3))),
              child: Text(note.selectedText, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
            ),
            if (isNote) Padding(padding: const EdgeInsets.only(top: 6), child: Text(note.noteContent, style: TextStyle(color: scheme.onSurfaceVariant))),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (onEdit != null) _ActionButton('编辑', Icons.edit_outlined, onEdit!),
              if (onDelete != null) _ActionButton('删除', Icons.delete_outline, onDelete!),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Notes list of a book; also embedded by the catalog page.
class BookNotesView extends StatefulWidget {
  final Book book;
  final String filter;

  const BookNotesView({super.key, required this.book, this.filter = ''});

  @override
  State<BookNotesView> createState() => _BookNotesViewState();
}

class _BookNotesViewState extends BasePage<BookNotesView> {
  List<BookNote>? _notes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = await NoteDataN.notesOfBook(widget.book.bookUrl);
    update(() => _notes = n);
  }

  Future<void> _delete(BookNote n) async {
    if (!await confirm('删除笔记', '确定删除这条高亮/笔记吗？')) return;
    await NoteDataN.delete(n.id);
    await _load();
  }

  Future<void> _edit(BookNote n) async {
    final text = await input('编辑', initial: n.noteContent, maxLines: 5);
    if (text == null) return;
    await NoteDataN.update(BookNote.fromJson(n.toJson())..noteContent = text);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _notes;
    if (all == null) return const Center(child: CircularProgressIndicator());
    final f = widget.filter.trim();
    final list = f.isEmpty ? all : all.where((n) => n.selectedText.contains(f) || n.noteContent.contains(f) || n.chapterName.contains(f)).toList();
    if (list.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('还没有笔记'),
          SizedBox(height: 6),
          Text('阅读时长按选中文字即可添加高亮或笔记', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (c, i) => BookNoteCard(
        note: list[i],
        onTap: () => Nav.openReader(context, widget.book, chapterIndex: list[i].chapterIndex),
        onEdit: () => _edit(list[i]),
        onDelete: () => _delete(list[i]),
      ),
    );
  }
}

class BookNotesPage extends StatelessWidget {
  final Book book;
  const BookNotesPage({super.key, required this.book});

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('笔记'), centerTitle: true), body: BookNotesView(book: book));
}
