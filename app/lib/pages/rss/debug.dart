// pages/rss/debug.dart — `DebugRssPage` (调试订阅, `rssdebug`): runs an RSS source (first sort, first page, first article) and shows the
// log; the menu shows the list and content page sources (`列表源码` / `正文源码`, dialog 0x5bef0c 复制 / 关闭).
// Original `_DebugRssPageState`: the run happens on the bound backend over the `debug` websocket (0x10ca934 `rssdebug`, sends
// `{url, key}`, messages `msg` / `列表源码Qwq` / `正文源码Qwq`). The replica runs local sources in its own engine (same log markers) and
// keeps the websocket for backend sources.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/rssapi.dart';
import '../../qread/qread.dart';
import '../../util/http.dart';
import '../../util/toast.dart';
import '../../util/webbook/debug.dart';
import '../../util/webbook/model/rss_source.dart';
import '../source/debug_qsource.dart' show QwqLog;

/// One local debug run of an RSS source: log lines and the two page sources. Public for tests.
Future<QwqLog> runRssDebug(RssSource source, {void Function(String line)? onLine}) async {
  final out = QwqLog();
  void add(String s) {
    out.lines.add(s);
    onLine?.call(s);
  }

  final log = DebugLog(onLine: add);
  try {
    final sorts = await RssRunapi.sorts(source);
    log.log('︾开始解析列表页');
    final sort = sorts.first;
    log.log('≡分类:${sort.$1} ${sort.$2}');
    final (list, next) = await RssRunapi.articles(source, sort.$1, sort.$2, debug: log);
    out.sources['列表源码'] = await _fetch(source, sort.$2);
    log.log('︽列表页解析完成 ${list.length}${next == null ? '' : ' 下一页:$next'}');
    if (list.isEmpty) {
      log.log('≡未获取到文章');
      return out;
    }
    final a = list.first;
    log.log('≡标题:${a.title}');
    log.log('≡链接:${a.link}');
    log.log('≡时间:${a.pubDate ?? ''}');
    log.log('≡图片:${a.image ?? ''}');
    if ((source.ruleContent ?? '').trim().isEmpty) {
      log.log('⇒内容规则为空，默认获取整个网页');
      return out;
    }
    log.log('︾开始解析正文页');
    out.sources['正文源码'] = await _fetch(source, a.link);
    final content = await RssRunapi.content(source, a, debug: log);
    log.log('┌获取正文');
    log.log('└$content');
    log.log('︽正文页解析完成');
  } catch (e) {
    log.log('error: $e');
  }
  return out;
}

Future<String> _fetch(RssSource source, String url) async {
  try {
    if (!url.startsWith('http')) return '';
    final res = await AppHttp.send(HttpRequest(url: url, headers: await source.getHeaderMap(true)));
    return AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType);
  } catch (e) {
    return '$e';
  }
}

class DebugRssPage extends StatefulWidget {
  final Map<String, dynamic> source;
  const DebugRssPage({super.key, required this.source});

  @override
  State<DebugRssPage> createState() => _DebugRssPageState();
}

class _DebugRssPageState extends State<DebugRssPage> {
  QwqLog _log = QwqLog();
  WebSocket? _ws;
  bool _running = false;

  bool get _remote => widget.source['isqread'] == true || '${widget.source['isqread']}' == 'true';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _ws?.close();
    super.dispose();
  }

  void _addlog(String s) {
    if (mounted) setState(() => _log.lines.add(s));
  }

  Future<void> _start() async {
    setState(() {
      _log = QwqLog();
      _running = true;
    });
    if (_remote) {
      await _startRemote();
    } else {
      final r = await runRssDebug(RssSource.fromJson(widget.source), onLine: _addlog);
      _log.sources.addAll(r.sources);
    }
    if (mounted) setState(() => _running = false);
  }

  /// 0x10ca934.
  Future<void> _startRemote() async {
    final String url;
    try {
      url = Qread.wsUrl('rssdebug');
    } catch (_) {
      _addlog('获取ws链接失败');
      return;
    }
    try {
      final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 15));
      _ws = ws;
      _addlog('WebSocket连接成功');
      ws.add(jsonEncode({'url': widget.source['sourceUrl'], 'key': 'debug'}));
      ws.listen((m) {
        if (mounted) setState(() => _log.add(m));
      }, onError: (Object e) => _addlog('WebSocket连接错误:$e'));
    } catch (e) {
      _addlog('WebSocket连接失败: $e');
    }
  }

  Future<void> _show(String label, String text) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
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
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.source['sourceName'] ?? '调试订阅'}'),
        actions: [
          IconButton(tooltip: '重新调试', icon: const Icon(Icons.refresh), onPressed: _running ? null : _start),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) => v == 'log' ? _show('日志', _log.lines.join('\n')) : _show(v, _log.sources[v] ?? ''),
            itemBuilder: (c) => const [
              PopupMenuItem(value: '列表源码', child: Text('列表源码')),
              PopupMenuItem(value: '正文源码', child: Text('正文源码')),
              PopupMenuItem(value: 'log', child: Text('日志')),
            ],
          ),
        ],
        bottom: _running ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: SelectableText(key: const Key('rss_debug_log'), _log.lines.join('\n')))),
    );
  }
}
