// pages/tts/code.dart — code editor of an engine definition (`CodePage`, 24 functions; the original hosts the Monaco editor in a web
// view: `编辑器尚未加载完成`, `已复制` / `已粘贴` / `已剪切`, `保存成功` / `保存失败：`). The replica uses a monospace text field with the
// same actions; 保存 pops the text (validated as JSON when [json] is set).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../util/toast.dart';

class CodePage extends StatefulWidget {
  final String code;
  final String title;
  final bool json;
  const CodePage({super.key, required this.code, this.title = '编辑代码', this.json = true});

  @override
  State<CodePage> createState() => _CodePageState();
}

class _CodePageState extends State<CodePage> {
  late final TextEditingController _c = TextEditingController(text: widget.code);

  void _save() {
    if (widget.json) {
      try {
        jsonDecode(_c.text);
      } catch (e) {
        Toast.show('保存失败：$e', iserror: true);
        return;
      }
    }
    Toast.show('保存成功');
    Navigator.of(context).pop(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        IconButton(
          tooltip: '复制',
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _c.text));
            Toast.show('已复制');
          },
        ),
        IconButton(
          tooltip: '粘贴',
          icon: const Icon(Icons.content_paste),
          onPressed: () async {
            final d = await Clipboard.getData(Clipboard.kTextPlain);
            if ((d?.text ?? '').isEmpty) return Toast.show('剪贴板为空', iserror: true);
            _c.text = d!.text!;
            Toast.show('已粘贴');
          },
        ),
        IconButton(key: const Key('code_save'), tooltip: '保存', icon: const Icon(Icons.save_outlined), onPressed: _save),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _c,
          expands: true,
          maxLines: null,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
    );
  }
}
