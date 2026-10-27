// pages/source/edit_qsource.dart — editor of a source stored on the bound 轻阅读 backend (后端编辑书源, `editqsource`). The original
// page (`_EditSourcePageState` of this file, size 0x20 widget `EditQSourcePage`) has the same fields as the Legado editor; it loads
// the source with `/getbookSources` (0x10c1134, `获取书源` / `获取书源出错:`) and saves with `/editbookSources` (0xf96eb4). Opening it
// requires the backend's edit permission (`当前用户无法编辑轻阅读书源…`).
import 'package:flutter/material.dart';

import '../../qread/api/qsourceapi.dart';
import '../../qread/qread.dart';
import 'edit_bqsource.dart';

class EditQSourcePage extends StatefulWidget {
  /// `bookSourceUrl` of the backend source (empty = new source).
  final String url;
  const EditQSourcePage({super.key, this.url = ''});

  @override
  State<EditQSourcePage> createState() => _EditQSourcePageState();
}

class _EditQSourcePageState extends State<EditQSourcePage> {
  Map<String, dynamic>? _json;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.url.isEmpty) {
      setState(() => _json = <String, dynamic>{});
      return;
    }
    try {
      final j = await QSourceApi.sourceJson(widget.url);
      if (mounted) setState(() => _json = j);
    } catch (e) {
      if (mounted) setState(() => _error = '获取书源出错:$e');
    }
  }

  Future<void> _save(String oldUrl, Map<String, dynamic> json) async {
    if (!Qread.requireEdit()) throw const QreadException('无权限');
    await QSourceApi.save(oldUrl, json);
    await QSourceApi.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final j = _json;
    if (j != null) return EditBqSourcePage(source: j.isEmpty ? null : j, onSave: _save, title: '编辑书源');
    return Scaffold(
      appBar: AppBar(title: const Text('编辑书源')),
      body: Center(child: _error == null ? const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('获取书源')]) : Text(_error!)),
    );
  }
}
