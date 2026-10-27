// pages/source/debug_qsource.dart — debugger of a source on the bound 轻阅读 backend (后端调试书源, `debugqsource`). The backend runs the
// source and streams its log over a websocket. Original `_DebugSourcePageState` of this file (run 0xfc0a34: ws url from 0x2acdc8
// with `debug` -> `ws(s)://<host>/api/5/debug?id=<token>&sg=1`, sends `{url, key}`, `WebSocket连接成功` / `WebSocket连接失败: `,
// `获取ws链接失败`; messages carry `msg`; page sources arrive as text starting with `搜索源码Qwq` / `发现源码Qwq` / `书籍源码Qwq` /
// `目录源码Qwq` / `正文源码Qwq`).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../qread/qread.dart';
import '../../util/toast.dart';

/// Prefix of a page-source message -> menu label.
const Map<String, String> qwqPrefixes = {
  '搜索源码Qwq': '搜索源码',
  '发现源码Qwq': '发现源码',
  '书籍源码Qwq': '书籍源码',
  '目录源码Qwq': '目录源码',
  '正文源码Qwq': '正文源码',
  '列表源码Qwq': '列表源码',
};

/// Splits one websocket message into a log line or a page source; shared with the RSS debugger.
class QwqLog {
  final List<String> lines = [];
  final Map<String, String> sources = {};

  void add(Object? message) {
    var text = '$message';
    try {
      final v = jsonDecode(text);
      if (v is Map && v['msg'] != null) text = '${v['msg']}';
    } catch (_) {}
    for (final p in qwqPrefixes.entries) {
      if (text.startsWith(p.key)) {
        sources[p.value] = text.substring(p.key.length);
        return;
      }
    }
    lines.add(text);
  }
}

class DebugQSourcePage extends StatefulWidget {
  final String url;
  final String name;
  const DebugQSourcePage({super.key, required this.url, this.name = ''});

  @override
  State<DebugQSourcePage> createState() => _DebugSourcePageState();
}

class _DebugSourcePageState extends State<DebugQSourcePage> {
  final _input = TextEditingController();
  QwqLog _log = QwqLog();
  WebSocket? _ws;

  @override
  void dispose() {
    _ws?.close();
    _input.dispose();
    super.dispose();
  }

  void _addlog(String s) {
    if (mounted) setState(() => _log.lines.add(s));
  }

  Future<void> _handleSearch(String key) async {
    if (key.trim().isEmpty) return;
    await _ws?.close();
    setState(() => _log = QwqLog());
    final String url;
    try {
      url = Qread.wsUrl('debug');
    } catch (e) {
      _addlog('获取ws链接失败');
      return;
    }
    try {
      final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 15));
      _ws = ws;
      _addlog('WebSocket连接成功');
      ws.add(jsonEncode({'url': widget.url, 'key': key.trim()}));
      ws.listen((m) {
        if (mounted) setState(() => _log.add(m));
      }, onError: (Object e) => _addlog('WebSocket连接错误:$e'), onDone: () => _ws = null);
    } catch (e) {
      _addlog('WebSocket连接失败: $e');
    }
  }

  Future<void> _show(String label) => showDialog<void>(
        context: context,
        builder: (c) {
          final text = _log.sources[label] ?? '';
          return AlertDialog(
            title: Row(children: [
              Expanded(child: Text(label)),
              IconButton(
                tooltip: '复制',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Toast.show('已复制到剪贴板');
                },
              ),
            ]),
            content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(text.isEmpty ? '空' : text))),
            actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('关闭'))],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _input,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '输入书名或者发现URL',
            isDense: true,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          ),
          onSubmitted: _handleSearch,
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _show,
            itemBuilder: (c) => [for (final l in qwqPrefixes.values.take(5)) PopupMenuItem(value: l, child: Text(l))],
          ),
        ],
      ),
      body: SafeArea(
        child: _log.lines.isEmpty
            ? ListView(children: [
                for (final k in const ['我的', '系统'])
                  ListTile(dense: true, title: Text(k), onTap: () => _handleSearch(_input.text = k)),
                const ListTile(dense: true, title: Text('调试详情页 >> 输入详情页URL，如：'), subtitle: Text('http://xxx.com/book/xxx')),
                const ListTile(dense: true, title: Text('调试目录页 >> 输入目录页URL，如：'), subtitle: Text('++http://xxx.com/xxx/xxx')),
                const ListTile(dense: true, title: Text('调试正文页 >> 输入正文页URL，如：'), subtitle: Text('--http://xxx.com/xxx/xxx')),
              ])
            : SingleChildScrollView(padding: const EdgeInsets.all(12), child: SelectableText(_log.lines.join('\n'))),
      ),
    );
  }
}
