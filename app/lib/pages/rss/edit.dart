// pages/rss/edit.dart — `EditRssSourcePage`: picks the RSS editor (`late Widget w`): backend sources (`isqread`) -> qedit.dart,
// everything else -> bedit.dart. Callers check the backend edit permission first (`当前用户无法编辑轻阅读书源…`, rss_page 0xf6975c).
import 'package:flutter/material.dart';

import 'bedit.dart';
import 'qedit.dart';

class EditRssSourcePage extends StatefulWidget {
  final Map<String, dynamic>? source;

  /// New backend source (when [source] is null).
  final bool remote;
  const EditRssSourcePage({super.key, this.source, this.remote = false});

  @override
  State<EditRssSourcePage> createState() => _EditRssSourcePageState();
}

class _EditRssSourcePageState extends State<EditRssSourcePage> {
  late Widget w;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    final remote = s == null ? widget.remote : (s['isqread'] == true || '${s['isqread']}' == 'true');
    w = remote ? EditQRssSourcePage(url: '${s?['sourceUrl'] ?? ''}') : EditBRssSourcePage(source: s);
  }

  @override
  Widget build(BuildContext context) => w;
}
