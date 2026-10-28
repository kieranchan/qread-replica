// pages/source/debug_source.dart — `DebugSourcePage`: runs a source step by step and streams the log (调试书源, `debugsource`).
//
// Original `_DebugSourcePageState` (app bar 0x5c70cc: input `输入书名或者发现URL` -> `_handleSearch` 0x5cc56c, menu 0xfc60b4 with
// search / book / toc / content source views (`搜索源码`…, dialog 0x5cc0f8 复制 / 关闭), cleancaches, log, edit -> CodePage,
// explore `是否要重新获取发现？`, refresh `是否要重载书源webview？`; help 0x5c7d20 with the check keywords 我的 / 系统 and the
// `调试发现 >>` / `调试详情页 >>` / `调试目录页 >> ++` / `调试正文页 >> --` examples; run 0xfc1a88 `⇒开始搜索关键字:` …; HTTP section
// 0x5c9394 `在线调试 HTTP（固定端口 5858）`, address pick 0xfc5e4c (192.168. / 10. / 172.16-31), `已复制服务地址`, `接口说明已复制`;
// PUT /source validation 0xfc49b0).
//
// The replica runs `SourceApi.debug` (the engine's debugger, Legado log markers) and streams its lines; the response body of every
// step is kept from the run itself (0xfc20b0), so the source views show exactly what the rules saw (POST requests included). Only
// a step the run did not reach falls back to fetching its url again.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/sourceapi.dart';
import '../../data/source.dart';
import '../../util/http.dart';
import '../../util/toast.dart';
import '../../util/webbook/model/book_source.dart';
import 'code.dart';
import 'debug_http_server.dart';

/// The steps whose page sources can be shown, with the menu labels.
const List<(String, String)> debugSourceSteps = [('search', '搜索源码'), ('explore', '发现源码'), ('book', '书籍源码'), ('toc', '目录源码'), ('content', '正文源码')];

/// Collects the log of one run and the request url of each step.
class DebugRun {
  final List<String> lines = [];
  final Map<String, String> urls = {};

  /// Response bodies of the steps, from the run itself.
  final Map<String, String> bodies = {};
  String _stage = '';

  static const Map<String, String> _markers = {
    '︾开始解析搜索页': 'search',
    '︾开始解析发现页': 'explore',
    '︾开始解析详情页': 'book',
    '︾开始解析目录页': 'toc',
    '︾开始解析正文页': 'content',
  };

  bool _detailNext = false;

  void add(String line) {
    lines.add(line);
    // the detail page is not logged with its url: take the first `详情页链接` of the list, or the url a detail run starts with
    final start = line.indexOf('⇒开始访问详情页:');
    if (start >= 0) urls['book'] = line.substring(start + 9).trim();
    if (_detailNext && line.contains('└')) {
      final u = line.substring(line.indexOf('└') + 1).trim();
      if (u.startsWith('http')) urls.putIfAbsent('book', () => u);
      _detailNext = false;
    }
    if (line.contains('┌获取详情页链接')) _detailNext = true;
    for (final e in _markers.entries) {
      if (line.contains(e.key)) _stage = e.value;
    }
    for (final p in const ['≡请求:', '≡获取成功:']) {
      final i = line.indexOf(p);
      if (i >= 0 && _stage.isNotEmpty) {
        final u = line.substring(i + p.length).trim();
        if (u.startsWith('http') && (p == '≡请求:' || !urls.containsKey(_stage))) urls[_stage] = u;
      }
    }
  }

  @override
  String toString() => lines.join('\n');
}

/// The start line of a run (0xfc1a88).
String debugStartLine(String key) {
  if (key.startsWith('++')) return '⇒开始访问目录页:${key.substring(2)}';
  if (key.startsWith('--')) return '⇒开始访问正文页:${key.substring(2)}';
  if (key.startsWith('http://') || key.startsWith('https://')) return '⇒开始访问详情页:$key';
  if (key.contains('::')) return '⇒开始访问发现页:${key.substring(key.indexOf('::') + 2)}';
  return '⇒开始搜索关键字:$key';
}

class DebugSourcePage extends StatefulWidget {
  /// Raw JSON of the source (as edited; not necessarily saved).
  final Map<String, dynamic> source;

  /// Starts a run at once with this key.
  final String? autoKey;
  const DebugSourcePage({super.key, required this.source, this.autoKey});

  @override
  State<DebugSourcePage> createState() => _DebugSourcePageState();
}

class _DebugSourcePageState extends State<DebugSourcePage> {
  late Map<String, dynamic> source = Map<String, dynamic>.from(widget.source);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  DebugRun _run = DebugRun();
  bool _running = false;
  List<ExploreKind> _kinds = [];
  late final DebugHttpServer _httpServer = DebugHttpServer(
    runDebug: _httpRunDebug,
    partialLogs: () => _run.toString(),
    getSource: _httpGetSource,
    saveSource: _httpSaveSource,
    currentKeyword: () => _checkKeyWord,
  );
  List<String> _addresses = [];

  BookSource get _engine => BookSource.fromJson(source);

  String get _checkKeyWord {
    final r = source['ruleSearch'];
    final k = r is Map ? '${r['checkKeyWord'] ?? ''}'.trim() : '';
    return k.isEmpty ? '我的' : k;
  }

  @override
  void initState() {
    super.initState();
    _loadKinds();
    final k = widget.autoKey;
    if (k != null && k.isNotEmpty) {
      _input.text = k;
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleSearch(k));
    }
  }

  Future<void> _loadKinds({bool refresh = false}) async {
    try {
      final k = await SourceApi.exploreKinds(_engine, refresh: refresh);
      if (mounted) setState(() => _kinds = k.where((e) => (e.url ?? '').isNotEmpty).toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    _httpServer.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _addlog(String line) {
    if (!mounted) return;
    setState(() => _run.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// 0xfc1a88: one run of the debugger.
  Future<DebugRun> _start(String key) async {
    final run = DebugRun();
    setState(() {
      _run = run;
      _running = true;
    });
    _addlog(debugStartLine(key));
    try {
      await SourceApi.debug(_engine, key, onLine: _addlog, onBody: (step, body) => run.bodies[step] = body);
    } catch (e) {
      _addlog('error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
    return run;
  }

  Future<void> _handleSearch(String key) async {
    final k = key.trim();
    if (k.isEmpty) return;
    if (_running) {
      Toast.show('书源未就绪，请稍候再试');
      return;
    }
    FocusScope.of(context).unfocus();
    await _start(k);
  }

  /// The page source of one step: the body the run received, else fetched again with the source's headers.
  Future<String> _rawOf(DebugRun run, String step) async {
    final kept = run.bodies[step];
    if (kept != null) return kept;
    final url = run.urls[step];
    if (url == null) return '';
    try {
      final headers = await _engine.getHeaderMap(true);
      final res = await AppHttp.send(HttpRequest(url: url, headers: headers, useCookieJar: _engine.enabledCookieJar));
      return AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType);
    } catch (e) {
      return '$e';
    }
  }

  Future<void> _showText(String title, String text) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Row(children: [
            Expanded(child: Text(title)),
            IconButton(
              tooltip: '复制',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                Toast.show('已复制到剪贴板');
              },
            ),
          ]),
          content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(text.isEmpty ? '空' : text, style: const TextStyle(height: 1.5)))),
          actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('关闭'))],
        ),
      );

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('操作确认'),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
          ],
        ),
      ) ==
      true;

  /// 0xfc60b4.
  Future<void> _onMenu(String v) async {
    for (final s in debugSourceSteps) {
      if (s.$1 == v) {
        await _showText(s.$2, await _rawOf(_run, v));
        return;
      }
    }
    switch (v) {
      case 'log':
        await _showText('日志', _run.toString());
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (c) => CodePage(
            text: const JsonEncoder.withIndent('  ').convert(source),
            onSave: (t) async => _store(Map<String, dynamic>.from(jsonDecode(t) as Map)),
          ),
        ));
      case 'explore':
        if (await _confirm('是否要重新获取发现？')) {
          _engine.clearExploreKindsCache();
          await _loadKinds(refresh: true);
        }
      case 'cleancaches':
        _engine.clearExploreKindsCache();
        SourceApi.cache.clear();
        Toast.show('清除成功！');
    }
  }

  /// Stores an edited source (local store; the page then debugs the new JSON).
  Future<void> _store(Map<String, dynamic> json) async {
    await Sources.update('${source['bookSourceUrl']}', json);
    if (mounted) setState(() => source = json);
    await _loadKinds(refresh: true);
  }

  // ------------------------------------------------------------------------------------------------------------ HTTP service

  Future<DebugRunResult> _httpRunDebug(String key) async {
    final run = await _start(key);
    final raw = <String, String>{};
    for (final s in const ['search', 'book', 'toc', 'content']) {
      raw[s] = await _rawOf(run, s);
    }
    if ((raw['search'] ?? '').isEmpty) raw['search'] = await _rawOf(run, 'explore');
    return DebugRunResult(key, run.toString(), raw);
  }

  Map<String, dynamic> _httpGetSource() => source;

  /// 0xfc49b0: PUT /source validation.
  Future<Map<String, dynamic>> _httpSaveSource(Object? body) async {
    if (body == null) throw const DebugHttpException('请求体为空：请提交【单个】书源 JSON 对象，禁止传数组。');
    if (body is! Map) throw const DebugHttpException('请求体必须是单个书源 JSON 对象 {…}，禁止传数组 [ … ]。');
    final m = Map<String, dynamic>.from(body);
    if (m['isqread'] == true || '${m['isqread']}' == 'true') throw const DebugHttpException('只允许保存/导入 isqread 为 false 或空（不传）的书源，isqread=true 已拒绝。');
    final url = '${m['bookSourceUrl'] ?? ''}'.trim();
    if (url.isEmpty) throw const DebugHttpException('bookSourceUrl 不能为空。');
    if ('${m['bookSourceName'] ?? ''}'.trim().isEmpty) throw const DebugHttpException('bookSourceName 不能为空。');
    final cur = '${source['bookSourceUrl']}';
    if ('${source['html'] ?? ''}'.trim().isNotEmpty && !'${source['html']}'.startsWith('@yuedu') && '${m['html'] ?? ''}'.trim().isEmpty) {
      throw const DebugHttpException('该书源是自定义代码源，PUT 必须包含完整 html 字段（先 GET /source 取完整 JSON 再修改提交），本次已拒绝。');
    }
    if (url != cur) throw DebugHttpException('bookSourceUrl 必须与当前调试书源一致（当前：$cur，提交：$url），不允许导入新书源或修改地址。');
    await _store(m);
    return {'action': 'edited', 'bookSourceUrl': url, 'bookSourceName': m['bookSourceName']};
  }

  /// 0xfc5e4c: LAN addresses, private ranges first.
  Future<List<String>> _lanAddresses() async {
    final out = <String>[];
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in i.addresses) {
          out.add(a.address);
        }
      }
    } catch (_) {}
    int rank(String a) {
      if (a.startsWith('192.168.')) return 0;
      if (a.startsWith('10.')) return 1;
      final m = RegExp(r'^172\.(\d+)\.').firstMatch(a);
      if (m != null && (int.tryParse(m.group(1)!) ?? 0) >= 16 && (int.tryParse(m.group(1)!) ?? 0) <= 31) return 2;
      return 3;
    }

    out.sort((a, b) => rank(a).compareTo(rank(b)));
    return out.isEmpty ? ['127.0.0.1'] : out;
  }

  String get _httpBaseUrl => 'http://${_addresses.isEmpty ? '127.0.0.1' : _addresses.first}:${_httpServer.boundPort}';

  Future<void> _toggleHttp(bool on) async {
    if (on) {
      try {
        await _httpServer.start();
        _addresses = await _lanAddresses();
      } catch (e) {
        Toast.show('在线调试启动失败（端口 ${DebugHttpServer.defaultPort} 可能被占用）：$e', iserror: true);
      }
    } else {
      await _httpServer.stop();
    }
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------------------------------------------------- UI

  Widget _hint(String title, String example, String key) => ListTile(
        dense: true,
        title: Text(title),
        subtitle: Text(example, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        onTap: () {
          _input.text = key;
          if (!key.endsWith('xxx')) _handleSearch(key);
        },
      );

  Widget _help() {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Wrap(spacing: 8, children: [
          for (final k in {_checkKeyWord, '我的', '系统'}) ActionChip(label: Text(k), onPressed: () => _handleSearch(_input.text = k)),
        ]),
      ),
      if (_kinds.isNotEmpty) ...[
        const ListTile(dense: true, title: Text('调试发现 >> 输入发现URL，如：')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in _kinds) ActionChip(label: Text(k.title), onPressed: () => _handleSearch(_input.text = '${k.title}::${k.url}')),
          ]),
        ),
      ],
      _hint('调试详情页 >> 输入详情页URL，如：', 'http://xxx.com/book/xxx', 'http://xxx.com/book/xxx'),
      _hint('调试目录页 >> 输入目录页URL，如：', '++http://xxx.com/xxx/xxx', '++http://xxx.com/xxx/xxx'),
      _hint('调试正文页 >> 输入正文页URL，如：', '--http://xxx.com/xxx/xxx', '--http://xxx.com/xxx/xxx'),
      const Divider(),
      SwitchListTile(
        key: const Key('debug_http_switch'),
        title: const Text('在线调试 HTTP（固定端口 5858）'),
        subtitle: const Text('开启后，同一局域网（同一 Wi-Fi）下的电脑可用浏览器 / curl / AI 调用接口：运行调试、读取与保存书源。离开本页面服务自动关闭。'),
        value: _httpServer.running,
        onChanged: _toggleHttp,
      ),
      if (_httpServer.running)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('服务运行中', style: TextStyle(color: cs.primary)),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _httpBaseUrl));
                Toast.show('已复制服务地址');
              },
              child: SelectableText(_httpBaseUrl),
            ),
            Text('当前调试书源：${source['bookSourceName'] ?? ''}'),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_httpServer.docs(_httpBaseUrl))));
                Toast.show('接口说明已复制');
              },
              child: const Text('复制接口说明'),
            ),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('debug_input'),
          controller: _input,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '输入书名或者发现URL',
            isDense: true,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            suffixIcon: IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => _handleSearch(_input.text)),
          ),
          onSubmitted: _handleSearch,
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onMenu,
            itemBuilder: (c) => [
              for (final s in debugSourceSteps) PopupMenuItem(value: s.$1, child: Text(s.$2)),
              const PopupMenuItem(value: 'log', child: Text('日志')),
              const PopupMenuItem(value: 'edit', child: Text('编辑书源')),
              const PopupMenuItem(value: 'explore', child: Text('刷新发现')),
              const PopupMenuItem(value: 'cleancaches', child: Text('清除缓存')),
            ],
          ),
        ],
        bottom: _running ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: SafeArea(
        child: _run.lines.isEmpty
            ? SingleChildScrollView(child: _help())
            : SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                child: SelectableText(key: const Key('debug_log'), _run.toString(), style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
      ),
    );
  }
}
