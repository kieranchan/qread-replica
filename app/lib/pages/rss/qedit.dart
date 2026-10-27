// pages/rss/qedit.dart — editor of an RSS source stored on the bound 轻阅读 backend (后端订阅编辑, `rssqedit`). Original
// `_EditRssSourcePageState` of this file: same fields as bedit.dart, loaded with `/getRssSources` (0x10c7fb0, `获取订阅源出错:`) and
// saved with `/editRssSources` (0xfaa854).
import 'package:flutter/material.dart';

import '../../qread/api/rssapi.dart';
import '../../qread/qread.dart';
import '../../qread/rssdata.dart';
import 'bedit.dart';

class EditQRssSourcePage extends StatefulWidget {
  final String url;
  const EditQRssSourcePage({super.key, this.url = ''});

  @override
  State<EditQRssSourcePage> createState() => _EditRssSourcePageState();
}

class _EditRssSourcePageState extends State<EditQRssSourcePage> {
  Map<String, dynamic>? _json;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.url.isEmpty) {
      _json = <String, dynamic>{};
    } else {
      RssApi.sourceJson(widget.url).then((j) {
        if (mounted) setState(() => _json = j);
      }, onError: (Object e) {
        if (mounted) setState(() => _error = '获取订阅源出错:$e');
      });
    }
  }

  Future<void> _save(String oldUrl, Map<String, dynamic> json) async {
    if (!Qread.requireEdit()) throw const QreadException('无权限');
    await RssApi.save(oldUrl, json);
    await QRssSources.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final j = _json;
    if (j != null) return EditBRssSourcePage(source: j.isEmpty ? null : j, onSave: _save);
    return Scaffold(
      appBar: AppBar(title: const Text('编辑订阅源')),
      body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)),
    );
  }
}
