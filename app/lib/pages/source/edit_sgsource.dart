// pages/source/edit_sgsource.dart — editor of a 轻悦时光书源 (时光源, `editsgsource`): a source whose engine is an html page (code or
// url) defining the search / explore / detail / toc / content functions, run by the original in its web-view engine
// (util/source/baswebview.dart). Original `_EditSourceState` (build 0x5cc654: `书源编辑`; switches 需要登录 / 启用帮助 / 启用书源 /
// 启用发现 / 定制按钮 / 事件监听; fields 书源名称 / 书源URL(必须为 http 开头的正常网址) / 作者 / 书源分类 / html(html 代码或者网址); default
// html 0x9072b8; menu 0xfc6814 copy `引擎已复制` / paste / help / login / search / cleancaches `是否要清理当前书源所有的cache？`;
// code 0xfc7368 and debug 0xfc742c check `请输入书源URL`).
//
// The source runs in the 时光源 runtime (util/source/): 登录 opens the page's login (sg_login.dart), 搜索 the search page on this
// source, 调试 the debugger, 清除缓存 drops the source's `cache.*` store and its running page.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/sourceapi.dart';
import '../../common/nav.dart';
import '../../data/source.dart';
import '../../models/source.dart';
import '../../util/source/cache.dart';
import '../../util/source/source.dart';
import '../../util/toast.dart';
import 'code.dart';
import 'debug_source.dart';
import 'sg_login.dart';
import 'source_help.dart';

/// 0x9072b8: the html a new 时光源 starts with.
const String defaultSgHtml = '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="UTF-8">\n  <title>默认书源</title>\n</head>\n<body>\n\n</body>\n\n</html>\n      ';

class EditSgSourcePage extends StatefulWidget {
  final Map<String, dynamic>? source;
  const EditSgSourcePage({super.key, this.source});

  @override
  State<EditSgSourcePage> createState() => _EditSourceState();
}

class _EditSourceState extends State<EditSgSourcePage> {
  static const List<(String, String)> _fields = [
    ('书源名称', 'bookSourceName'),
    ('书源URL(必须为 http 开头的正常网址)', 'bookSourceUrl'),
    ('作者', 'author'),
    ('书源分类', 'bookSourceGroup'),
    ('html(html 代码或者网址)', 'html'),
  ];
  static const List<(String, String, bool)> _switches = [
    ('需要登录', 'login', false),
    ('启用帮助', 'help', false),
    ('启用书源', 'enabled', true),
    ('启用发现', 'enabledExplore', true),
    ('定制按钮', 'customButton', false),
    ('事件监听', 'eventListener', false),
  ];

  late Map<String, dynamic> _raw = widget.source == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(jsonEncode(widget.source)) as Map);
  final Map<String, TextEditingController> _c = {};
  final Map<String, bool> _flags = {};
  late String _savedUrl = '${widget.source?['bookSourceUrl'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _fill(_raw);
    if (widget.source == null) _c['html']!.text = defaultSgHtml;
  }

  void _fill(Map<String, dynamic> m) {
    for (final f in _fields) {
      final v = m[f.$2];
      (_c[f.$2] ??= TextEditingController()).text = v == null ? '' : '$v';
    }
    for (final s in _switches) {
      final v = m[s.$2];
      _flags[s.$2] = v == null ? s.$3 : (v == true || '$v' == 'true');
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _json {
    final out = Map<String, dynamic>.from(_raw);
    for (final f in _fields) {
      out[f.$2] = _c[f.$2]!.text;
    }
    for (final s in _switches) {
      out[s.$2] = _flags[s.$2];
    }
    return out;
  }

  Future<void> _save() async {
    final json = _json;
    final url = '${json['bookSourceUrl']}'.trim();
    if (url.isEmpty) {
      Toast.show('请输入书源URL');
      return;
    }
    if ('${json['bookSourceName']}'.trim().isEmpty) {
      Toast.show('书源名称不能为空');
      return;
    }
    try {
      await Sources.update(_savedUrl.isEmpty ? url : _savedUrl, json);
      if (_savedUrl.isNotEmpty) SourceApi.reloadSource(_savedUrl);
      SourceApi.reloadSource(url);
      _savedUrl = url;
      _raw = json;
      Toast.show('保存成功');
    } catch (e) {
      Toast.show('保存失败:$e', iserror: true);
    }
  }

  Future<void> _code() async {
    if (_c['bookSourceUrl']!.text.trim().isEmpty) {
      Toast.show('请输入书源URL');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (c) => CodePage(text: _c['html']!.text, onSave: (t) async => setState(() => _c['html']!.text = t)),
    ));
  }

  Future<void> _onSelected(String v) async {
    switch (v) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_json)));
        Toast.show('引擎已复制');
      case 'paste':
        try {
          final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
          if (t.isEmpty) {
            Toast.show('剪贴板为空!');
            return;
          }
          final d = jsonDecode(t);
          final m = Map<String, dynamic>.from((d is List ? d.first : d) as Map);
          setState(() {
            _raw = m;
            _fill(m);
          });
        } catch (e) {
          Toast.show('粘贴失败:$e!');
        }
      case 'help':
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => const SourceHelpPage()));
      case 'login':
      case 'search':
      case 'debug':
        final raw = _savedUrl.isEmpty ? null : Sourcedata.byUrl(_savedUrl);
        if (raw == null) {
          Toast.show('请先保存书源');
          return;
        }
        if (v == 'login') {
          await showTimeSourceLogin(context, BaseSource.fromJson(raw));
        } else if (v == 'search') {
          await Nav.openSearch(context, sources: [Source.fromJson(raw)]);
        } else {
          await Navigator.of(context).push(MaterialPageRoute(builder: (c) => DebugSourcePage(source: raw)));
        }
      case 'cleancaches':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('操作确认'),
            content: const Text('是否要清理当前书源所有的cache？'),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
            ],
          ),
        );
        if (ok != true) return;
        final url = _savedUrl.isEmpty ? _c['bookSourceUrl']!.text.trim() : _savedUrl;
        await Cache(url).clear();
        SourceApi.reloadSource(url);
        Toast.show('清除成功！');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书源编辑'),
        actions: [
          IconButton(tooltip: '编辑代码', icon: const Icon(Icons.code), onPressed: _code),
          IconButton(key: const Key('sg_save'), tooltip: '保存', icon: const Icon(Icons.save_outlined), onPressed: _save),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onSelected,
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'copy', child: Text('复制引擎')),
              PopupMenuItem(value: 'paste', child: Text('粘贴引擎')),
              PopupMenuItem(value: 'debug', child: Text('调试')),
              PopupMenuItem(value: 'login', child: Text('登录')),
              PopupMenuItem(value: 'search', child: Text('搜索')),
              PopupMenuItem(value: 'cleancaches', child: Text('清除缓存')),
              PopupMenuItem(value: 'help', child: Text('帮助')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final s in _switches)
            SwitchListTile(
              dense: true,
              title: Text(s.$1),
              value: _flags[s.$2] ?? s.$3,
              onChanged: (v) => setState(() => _flags[s.$2] = v),
            ),
          for (final f in _fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                key: Key('sg_${f.$2}'),
                controller: _c[f.$2],
                minLines: f.$2 == 'html' ? 6 : 1,
                maxLines: f.$2 == 'html' ? 16 : 3,
                style: f.$2 == 'html' ? const TextStyle(fontFamily: 'monospace', fontSize: 13) : null,
                decoration: InputDecoration(labelText: f.$1, border: const OutlineInputBorder()),
              ),
            ),
        ]),
      ),
    );
  }
}
