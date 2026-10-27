// widget/note_sheet.dart — the sheets for creating / editing / viewing a note (original 0x24ee58 "📝 添加笔记/高亮", 0x24f91c "✏️ 编辑笔记",
// 0x252524 "笔记详情"; classes NoteCreateResult, NoteEditResult, _ColorPicker, _HighlightedQuote, _QuoteText).
import 'package:flutter/material.dart';

import '../models/note.dart';

class NoteCreateResult {
  final String color;
  final String content;
  const NoteCreateResult(this.color, this.content);
}

class NoteEditResult {
  final String color;
  final String content;
  final bool delete;
  const NoteEditResult(this.color, this.content, {this.delete = false});
}

/// Highlight colours offered by the picker (#rrggbb).
const List<String> noteColors = ['#FFC107', '#FF7043', '#66BB6A', '#42A5F5', '#AB47BC', '#EC407A'];

Color _hex(String s) {
  final v = int.tryParse(s.replaceFirst('#', ''), radix: 16) ?? 0xFFC107;
  return Color(0xFF000000 | v);
}

class _ColorPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ColorPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      children: [
        for (final c in noteColors)
          GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _hex(c),
                shape: BoxShape.circle,
                border: Border.all(color: c == value ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _QuoteText extends StatelessWidget {
  final String text;
  final String color;
  const _QuoteText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: _hex(color), width: 3)),
        color: _hex(color).withValues(alpha: 0.12),
      ),
      child: Text(text, maxLines: 6, overflow: TextOverflow.ellipsis),
    );
  }
}

class _NoteForm extends StatefulWidget {
  final String title;
  final String quote;
  final String color;
  final String content;
  final String contentLabel;
  final String hint;
  final bool canDelete;

  const _NoteForm({
    required this.title,
    required this.quote,
    required this.color,
    required this.content,
    required this.contentLabel,
    required this.hint,
    this.canDelete = false,
  });

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  late String _color = widget.color.isEmpty ? noteColors.first : widget.color;
  late final TextEditingController _text = TextEditingController(text: widget.content);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const Text('引用文本：'),
            const SizedBox(height: 6),
            _QuoteText(text: widget.quote, color: _color),
            const SizedBox(height: 12),
            const Text('高亮颜色：'),
            const SizedBox(height: 6),
            _ColorPicker(value: _color, onChanged: (c) => setState(() => _color = c)),
            const SizedBox(height: 12),
            Text(widget.contentLabel),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('note_content'),
              controller: _text,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(hintText: widget.hint, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.canDelete)
                  TextButton(
                    onPressed: () => Navigator.pop(context, NoteEditResult(_color, _text.text, delete: true)),
                    child: const Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                FilledButton(
                  onPressed: () => Navigator.pop(context, NoteEditResult(_color, _text.text)),
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "📝 添加笔记/高亮".
Future<NoteCreateResult?> showNoteCreateSheet(BuildContext context, {required String quote, String color = ''}) async {
  final r = await showModalBottomSheet<NoteEditResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NoteForm(
      title: '📝 添加笔记/高亮',
      quote: quote,
      color: color,
      content: '',
      contentLabel: '笔记内容（可选）：',
      hint: '可选，不填则仅标记高亮',
    ),
  );
  return r == null ? null : NoteCreateResult(r.color, r.content);
}

/// "✏️ 编辑笔记".
Future<NoteEditResult?> showNoteEditSheet(BuildContext context, BookNote note) => showModalBottomSheet<NoteEditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoteForm(
        title: '✏️ 编辑笔记',
        quote: note.selectedText,
        color: note.color,
        content: note.noteContent,
        contentLabel: '笔记内容：',
        hint: '可选',
        canDelete: true,
      ),
    );

/// "笔记详情".
Future<void> showNoteDetail(BuildContext context, BookNote note) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('笔记详情'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选中内容'),
              const SizedBox(height: 6),
              _QuoteText(text: note.selectedText, color: note.color.isEmpty ? noteColors.first : note.color),
              if (note.noteContent.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('笔记内容'),
                const SizedBox(height: 6),
                Text(note.noteContent),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
