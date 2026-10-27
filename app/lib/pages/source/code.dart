// pages/source/code.dart — `CodePage`: edits the code of a source (the `html` of a 时光源, or the whole JSON when opened from the
// debugger's `edit` item). Original `_CodePageState` (build 0x6a79c4: `编辑书源代码`, Monaco editor in `html` mode, help ->
// SourceHelpPage 0x6ad21c, save 0x1035130 `保存成功` / `保存失败：`, tool bar 0x6a808c). The replica's editor is a TextField
// (txtcode.dart [CodeEditorBody]).
import 'package:flutter/material.dart';

import '../../util/toast.dart';
import 'source_help.dart';
import 'txtcode.dart';

class CodePage extends StatefulWidget {
  final String text;
  final String title;

  /// Stores the edited text; throwing shows `保存失败：…`.
  final Future<void> Function(String text) onSave;
  const CodePage({super.key, required this.text, required this.onSave, this.title = '编辑书源代码'});

  @override
  State<CodePage> createState() => _CodePageState();
}

class _CodePageState extends State<CodePage> {
  late final TextEditingController _c = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.onSave(_c.text);
      Toast.show('保存成功');
    } catch (e) {
      Toast.show('保存失败：$e', iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '书源帮助',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => const SourceHelpPage())),
          ),
          IconButton(key: const Key('code_save'), tooltip: '保存', icon: const Icon(Icons.save_outlined), onPressed: _save),
        ],
      ),
      body: CodeEditorBody(controller: _c),
    );
  }
}
