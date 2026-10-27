// pages/source/txtcode.dart — `Txtcodee`: full-screen editor for one rule / script field (the `编辑代码` button next to every field of
// the source editors). The original hosts a Monaco editor in a web view (`javascript` language, `vs`/`vs-dark`) with a tool bar
// (cursor up/down/left/right, select all, cut, copy, paste, find; 0x6ad964) and returns the text (`获取内容失败：` 0x1035e60).
// The replica uses a monospace TextField with the same tool bar; [CodeEditorBody] is shared with code.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../util/toast.dart';

/// Monospace editor plus the original's tool bar.
class CodeEditorBody extends StatefulWidget {
  final TextEditingController controller;
  const CodeEditorBody({super.key, required this.controller});

  @override
  State<CodeEditorBody> createState() => _CodeEditorBodyState();
}

class _CodeEditorBodyState extends State<CodeEditorBody> {
  final _focus = FocusNode();
  TextEditingController get _c => widget.controller;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _move(String to) {
    try {
      final text = _c.text;
      var o = _c.selection.isValid ? _c.selection.extentOffset : text.length;
      switch (to) {
        case 'left':
          o = (o - 1).clamp(0, text.length);
        case 'right':
          o = (o + 1).clamp(0, text.length);
        case 'up':
        case 'down':
          final lineStart = text.lastIndexOf('\n', o == 0 ? 0 : o - 1) + 1;
          final col = o - lineStart;
          if (to == 'up') {
            if (lineStart == 0) break;
            final prevStart = text.lastIndexOf('\n', lineStart - 2) + 1;
            o = (prevStart + col).clamp(prevStart, lineStart - 1);
          } else {
            final next = text.indexOf('\n', o);
            if (next < 0) break;
            final nextEnd = text.indexOf('\n', next + 1);
            o = (next + 1 + col).clamp(next + 1, nextEnd < 0 ? text.length : nextEnd);
          }
      }
      _c.selection = TextSelection.collapsed(offset: o);
      _focus.requestFocus();
    } catch (e) {
      Toast.show('移动光标失败：$e');
    }
  }

  void _selectAll() {
    try {
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
      _focus.requestFocus();
    } catch (e) {
      Toast.show('全选失败：$e');
    }
  }

  String get _selected => _c.selection.isValid && !_c.selection.isCollapsed ? _c.selection.textInside(_c.text) : _c.text;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _selected));
      Toast.show('已复制');
    } catch (e) {
      Toast.show('复制失败：$e');
    }
  }

  Future<void> _cut() async {
    try {
      final sel = _c.selection;
      await Clipboard.setData(ClipboardData(text: _selected));
      if (sel.isValid && !sel.isCollapsed) {
        _c.value = TextEditingValue(text: sel.textBefore(_c.text) + sel.textAfter(_c.text), selection: TextSelection.collapsed(offset: sel.start));
      } else {
        _c.clear();
      }
      Toast.show('已剪切');
    } catch (e) {
      Toast.show('剪切失败：$e');
    }
  }

  Future<void> _paste() async {
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final t = d?.text ?? '';
      if (t.isEmpty) {
        Toast.show('剪贴板为空');
        return;
      }
      final sel = _c.selection.isValid ? _c.selection : TextSelection.collapsed(offset: _c.text.length);
      _c.value = TextEditingValue(text: sel.textBefore(_c.text) + t + sel.textAfter(_c.text), selection: TextSelection.collapsed(offset: sel.start + t.length));
      Toast.show('已粘贴');
    } catch (e) {
      Toast.show('粘贴失败：$e');
    }
  }

  Future<void> _find() async {
    final q = TextEditingController();
    final s = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('搜索'),
        content: TextField(controller: q, autofocus: true, onSubmitted: (v) => Navigator.of(c).pop(v)),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(q.text), child: const Text('确定'))],
      ),
    );
    if (s == null || s.isEmpty) return;
    try {
      final from = _c.selection.isValid ? _c.selection.end : 0;
      var i = _c.text.indexOf(s, from);
      if (i < 0) i = _c.text.indexOf(s);
      if (i < 0) {
        Toast.show('未找到');
        return;
      }
      _c.selection = TextSelection(baseOffset: i, extentOffset: i + s.length);
      _focus.requestFocus();
    } catch (e) {
      Toast.show('搜索失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Expanded(
        child: TextField(
          key: const Key('code_editor'),
          controller: _c,
          focusNode: _focus,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
          decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(12)),
        ),
      ),
      Material(
        color: cs.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Wrap(alignment: WrapAlignment.center, children: [
            IconButton(tooltip: '上', icon: const Icon(Icons.keyboard_arrow_up), onPressed: () => _move('up')),
            IconButton(tooltip: '下', icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => _move('down')),
            IconButton(tooltip: '左', icon: const Icon(Icons.keyboard_arrow_left), onPressed: () => _move('left')),
            IconButton(tooltip: '右', icon: const Icon(Icons.keyboard_arrow_right), onPressed: () => _move('right')),
            IconButton(tooltip: '全选', icon: const Icon(Icons.select_all), onPressed: _selectAll),
            IconButton(tooltip: '剪切', icon: const Icon(Icons.content_cut), onPressed: _cut),
            IconButton(tooltip: '复制', icon: const Icon(Icons.content_copy), onPressed: _copy),
            IconButton(tooltip: '粘贴', icon: const Icon(Icons.content_paste), onPressed: _paste),
            IconButton(tooltip: '搜索', icon: const Icon(Icons.search), onPressed: _find),
          ]),
        ),
      ),
    ]);
  }
}

class Txtcodee extends StatefulWidget {
  final String text;
  final String title;
  const Txtcodee({super.key, required this.text, this.title = '编辑'});

  @override
  State<Txtcodee> createState() => _TxtcodeeState();
}

class _TxtcodeeState extends State<Txtcodee> {
  late final TextEditingController _c = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [IconButton(key: const Key('txtcode_ok'), tooltip: '确定', icon: const Icon(Icons.check), onPressed: () => Navigator.of(context).pop(_c.text))],
      ),
      body: CodeEditorBody(controller: _c),
    );
  }
}
