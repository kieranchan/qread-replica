// pages/source/edit_bqsource.dart — editor of an 开源阅读 (Legado) book source run by the replica's own engine (兼容层编辑书源,
// `editbqsource`). Original `_EditSourcePageState` (app bar 0x58dd40 `编辑书源`; tab bar 0x59057c with six tabs; header rows
// 0x5911e4 `类型：` 小说/听书/漫画 + 启用 / 发现 / CookieJar and 0x590a2c 事件监听 / 定制按钮; field lists 0x5901bc 基本, 0x58fe58 搜索,
// 0x58fb38 发现, 0x58f7d0 详情, 0x58f45c 目录, 0x58e86c 正文; field row 0x58eb58 with the `编辑代码` button; JSON build 0x591f98;
// menu 0xfacdfc help / login / search / copy (`书源已复制`) / setVariable / clearcookie / cleancaches / paste (`剪贴板为空!`);
// debug 0xfad488). The same page edits backend sources (edit_qsource.dart) with a different save.
//
// Round trip: the page edits a copy of the raw JSON and only writes the fields the user changed, so keys the form does not show
// (and the representation of untouched values) survive unchanged.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/nav.dart';
import '../../data/source.dart';
import '../../models/source.dart';
import '../../util/legado/cookie_jar.dart';
import '../../util/toast.dart';
import '../../util/webbook/model/book_source.dart';
import '../web/webview.dart';
import 'debug_source.dart';
import 'login_dialog.dart';
import 'txtcode.dart';

/// One editable rule: [label] as the original shows it, [key] in the JSON, [group] the rule object (`ruleSearch`, …) or null for a
/// top-level key.
class RuleField {
  final String label;
  final String key;
  final String? group;
  const RuleField(this.label, this.key, [this.group]);
}

const String _search = 'ruleSearch', _explore = 'ruleExplore', _info = 'ruleBookInfo', _toc = 'ruleToc', _content = 'ruleContent';

/// The six tabs and their fields, in the original's order.
const List<(String, List<RuleField>)> bookSourceTabs = [
  ('基本', [
    RuleField('源 URL', 'bookSourceUrl'),
    RuleField('源名称', 'bookSourceName'),
    RuleField('源分组', 'bookSourceGroup'),
    RuleField('源注释', 'bookSourceComment'),
    RuleField('登录 URL', 'loginUrl'),
    RuleField('登录 UI', 'loginUi'),
    RuleField('登录检查 JS', 'loginCheckJs'),
    RuleField('封面解密', 'coverDecodeJs'),
    RuleField('书籍 URL 正则', 'bookUrlPattern'),
    RuleField('请求头', 'header'),
    RuleField('变量说明', 'variableComment'),
    RuleField('并发率', 'concurrentRate'),
    RuleField('jsLib', 'jsLib'),
  ]),
  ('搜索', [
    RuleField('搜索地址', 'searchUrl'),
    RuleField('校验关键字', 'checkKeyWord', _search),
    RuleField('书籍列表规则', 'bookList', _search),
    RuleField('书名规则', 'name', _search),
    RuleField('作者规则', 'author', _search),
    RuleField('分类规则', 'kind', _search),
    RuleField('字数规则', 'wordCount', _search),
    RuleField('最新章节规则', 'lastChapter', _search),
    RuleField('简介规则', 'intro', _search),
    RuleField('封面规则', 'coverUrl', _search),
    RuleField('详情页 URL 规则', 'bookUrl', _search),
  ]),
  ('发现', [
    RuleField('发现地址规则', 'exploreUrl'),
    RuleField('书籍列表规则', 'bookList', _explore),
    RuleField('书名规则', 'name', _explore),
    RuleField('作者规则', 'author', _explore),
    RuleField('分类规则', 'kind', _explore),
    RuleField('字数规则', 'wordCount', _explore),
    RuleField('最新章节规则', 'lastChapter', _explore),
    RuleField('简介规则', 'intro', _explore),
    RuleField('封面规则', 'coverUrl', _explore),
    RuleField('详情页 URL 规则', 'bookUrl', _explore),
  ]),
  ('详情', [
    RuleField('预处理规则', 'init', _info),
    RuleField('书名规则', 'name', _info),
    RuleField('作者规则', 'author', _info),
    RuleField('分类规则', 'kind', _info),
    RuleField('字数规则', 'wordCount', _info),
    RuleField('最新章节规则', 'lastChapter', _info),
    RuleField('简介规则', 'intro', _info),
    RuleField('封面规则', 'coverUrl', _info),
    RuleField('目录 URL 规则', 'tocUrl', _info),
    RuleField('允许修改书名作者', 'canReName', _info),
    RuleField('下载URL规则', 'downloadUrls', _info),
  ]),
  ('目录', [
    RuleField('更新之前 JS', 'preUpdateJs', _toc),
    RuleField('目录列表规则', 'chapterList', _toc),
    RuleField('章节名称规则', 'chapterName', _toc),
    RuleField('章节 URL 规则', 'chapterUrl', _toc),
    RuleField('格式化规则', 'formatJs', _toc),
    RuleField('字数规则', 'wordCount', _toc),
    RuleField('Volume 标识', 'isVolume', _toc),
    RuleField('更新时间', 'updateTime', _toc),
    RuleField('VIP 标识', 'isVip', _toc),
    RuleField('购买标识', 'isPay', _toc),
    RuleField('目录下一页规则', 'nextTocUrl', _toc),
  ]),
  ('正文', [
    RuleField('正文规则', 'content', _content),
    RuleField('正文副本', 'subContent', _content),
    RuleField('正文下一页 URL 规则', 'nextContentUrl', _content),
    RuleField('WebView JS', 'webJs', _content),
    RuleField('资源正则', 'sourceRegex', _content),
    RuleField('替换规则', 'replaceRegex', _content),
    RuleField('图片解密', 'imageDecode', _content),
    RuleField('购买操作', 'payAction', _content),
    RuleField('回调操作', 'callBackJs', _content),
  ]),
];

/// `bookSourceType` choices of the `类型：` menu.
const List<(int, String)> bookSourceTypes = [(0, '小说'), (1, '听书'), (2, '漫画')];

/// Switches of the header rows: (label, key, default).
const List<(String, String, bool)> bookSourceSwitches = [
  ('启用', 'enabled', true),
  ('发现', 'enabledExplore', true),
  ('CookieJar', 'enabledCookieJar', true),
  ('事件监听', 'eventListener', false),
  ('定制按钮', 'customButton', false),
];

bool _on(Object? v, bool def) => v == null ? def : (v is bool ? v : '$v' == 'true' || '$v' == '1');

/// Text of a JSON value in a field (strings as they are, other values as JSON).
String fieldText(Object? v) => v == null ? '' : (v is String ? v : jsonEncode(v));

/// The form state of a source editor: the original JSON and the edited values. Separate from the widget so the round trip can
/// be tested without a UI.
class SourceForm {
  final Map<String, dynamic> original;
  final List<(String, List<RuleField>)> tabs;
  final List<(String, String, bool)> switches;
  final String typeKey;
  final Map<String, TextEditingController> controllers = {};
  final Map<String, bool> flags = {};
  int? type;

  SourceForm(Map<String, dynamic>? source, {this.tabs = bookSourceTabs, this.switches = bookSourceSwitches, this.typeKey = 'bookSourceType'})
      : original = source == null ? <String, dynamic>{} : (jsonDecode(jsonEncode(source)) as Map<String, dynamic>) {
    load(original);
  }

  static String id(RuleField f) => '${f.group ?? ''}.${f.key}';

  Object? _value(Map<String, dynamic> m, RuleField f) {
    if (f.group == null) return m[f.key];
    final g = m[f.group];
    return g is Map ? g[f.key] : null;
  }

  /// Fills the form from [m] (also used by `paste`).
  void load(Map<String, dynamic> m) {
    for (final t in tabs) {
      for (final f in t.$2) {
        final text = fieldText(_value(m, f));
        final c = controllers[id(f)];
        if (c == null) {
          controllers[id(f)] = TextEditingController(text: text);
        } else {
          c.text = text;
        }
      }
    }
    for (final s in switches) {
      flags[s.$2] = _on(m[s.$2], s.$3);
    }
    type = int.tryParse('${m[typeKey] ?? ''}');
  }

  String text(RuleField f) => controllers[id(f)]!.text;

  /// The edited JSON: the original map with only the changed fields written (an emptied field is removed).
  Map<String, dynamic> build() {
    final out = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    for (final t in tabs) {
      for (final f in t.$2) {
        final now = text(f);
        if (now == fieldText(_value(original, f))) continue;
        if (f.group == null) {
          if (now.isEmpty) {
            out.remove(f.key);
          } else {
            out[f.key] = now;
          }
        } else {
          final g = out[f.group] is Map ? Map<String, dynamic>.from(out[f.group] as Map) : <String, dynamic>{};
          if (now.isEmpty) {
            g.remove(f.key);
          } else {
            g[f.key] = now;
          }
          out[f.group!] = g;
        }
      }
    }
    for (final s in switches) {
      if (flags[s.$2] != _on(original[s.$2], s.$3)) out[s.$2] = flags[s.$2];
    }
    if (type != null && '${original[typeKey]}' != '$type') out[typeKey] = type;
    return out;
  }

  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
  }
}

/// Opens a field in the full-screen editor ([Txtcodee]) and writes the result back.
Future<void> editFieldCode(BuildContext context, String label, TextEditingController c) async {
  final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => Txtcodee(text: c.text, title: label)));
  if (r != null) c.text = r;
}

/// One field row (0x58eb58): multi-line text field with the `编辑代码` button.
Widget ruleFieldRow(BuildContext context, String label, TextEditingController c, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: c,
            minLines: 1,
            maxLines: 6,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: InputDecoration(labelText: label, hintText: '请输入', isDense: true, border: const OutlineInputBorder()),
          ),
        ),
        IconButton(tooltip: '编辑代码', icon: const Icon(Icons.code), onPressed: () => editFieldCode(context, label, c)),
      ]),
    );

class EditBqSourcePage extends StatefulWidget {
  /// Raw Legado JSON (null = new source).
  final Map<String, dynamic>? source;

  /// Saves the edited JSON instead of the local store (backend sources, edit_qsource.dart). [oldUrl] is the url the page was
  /// opened with.
  final Future<void> Function(String oldUrl, Map<String, dynamic> json)? onSave;
  final String title;
  const EditBqSourcePage({super.key, this.source, this.onSave, this.title = '编辑书源'});

  @override
  State<EditBqSourcePage> createState() => _EditSourcePageState();
}

class _EditSourcePageState extends State<EditBqSourcePage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: bookSourceTabs.length, vsync: this);
  late final SourceForm _form = SourceForm(widget.source);
  late String _savedUrl = '${widget.source?['bookSourceUrl'] ?? ''}';

  @override
  void dispose() {
    _tabController.dispose();
    _form.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _json => _form.build();

  Future<bool> _save() async {
    final json = _json;
    final url = '${json['bookSourceUrl'] ?? ''}'.trim();
    if (url.isEmpty) {
      Toast.show('源URL不能为空');
      return false;
    }
    if ('${json['bookSourceName'] ?? ''}'.trim().isEmpty) {
      Toast.show('书源名称不能为空');
      return false;
    }
    if (_savedUrl.isNotEmpty && url != _savedUrl) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('保存书源'),
          content: const Text('你已修改源URL会导致已添加书架的书本无法找到书源，确定要继续保存书源吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
          ],
        ),
      );
      if (ok != true) return false;
    }
    try {
      if (widget.onSave != null) {
        await widget.onSave!(_savedUrl.isEmpty ? url : _savedUrl, json);
      } else {
        await Sources.update(_savedUrl.isEmpty ? url : _savedUrl, json);
      }
      _savedUrl = url;
      Toast.show('保存成功');
      return true;
    } catch (e) {
      Toast.show('保存失败:$e', iserror: true);
      return false;
    }
  }

  BookSource get _engineSource => BookSource.fromJson(_json);

  Future<void> _onSelected(String v) async {
    switch (v) {
      case 'help':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (c) => const WebviewPage(url: 'https://mgz0227.github.io/The-tutorial-of-Legado/Rule/source.html', title: '书源规则帮助')));
      case 'login':
        if (_savedUrl.isEmpty) {
          Toast.show('请先保存书源');
          return;
        }
        await showSourceLogin(context, _engineSource);
      case 'search':
        if (_savedUrl.isEmpty) {
          Toast.show('请先保存书源');
          return;
        }
        // 0xfacdfc: SearchBookPage limited to this source
        await Nav.openSearch(context, sources: [Source.fromJson(_json)]);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_json)));
        Toast.show('书源已复制');
      case 'paste':
        try {
          final d = await Clipboard.getData(Clipboard.kTextPlain);
          final t = d?.text?.trim() ?? '';
          if (t.isEmpty) {
            Toast.show('剪贴板为空!');
            return;
          }
          final v = jsonDecode(t);
          final m = v is List ? v.first : v;
          setState(() => _form.load(Map<String, dynamic>.from(m as Map)));
        } catch (e) {
          Toast.show('粘贴失败:$e!');
        }
      case 'setVariable':
        await showSourceVariableDialog(context, _engineSource);
      case 'clearcookie':
        CookieStore.removeCookie('${_json['bookSourceUrl'] ?? ''}');
        Toast.show('清除成功！');
      case 'cleancaches':
        _engineSource.clearExploreKindsCache();
        Toast.show('清除成功！');
    }
  }

  void _debug() {
    final json = _json;
    if ('${json['bookSourceUrl'] ?? ''}'.trim().isEmpty) {
      Toast.show('请输入书源URL');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (c) => DebugSourcePage(source: json)));
  }

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          const Text('类型：'),
          DropdownButton<int>(
            value: bookSourceTypes.any((t) => t.$1 == (_form.type ?? 0)) ? (_form.type ?? 0) : 0,
            underline: const SizedBox(),
            items: [for (final t in bookSourceTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
            onChanged: (v) => setState(() => _form.type = v),
          ),
          for (final s in bookSourceSwitches)
            InkWell(
              key: Key('sw_${s.$2}'),
              onTap: () => setState(() => _form.flags[s.$2] = !(_form.flags[s.$2] ?? s.$3)),
              child: Row(children: [
                Checkbox(value: _form.flags[s.$2] ?? s.$3, onChanged: (v) => setState(() => _form.flags[s.$2] = v ?? false)),
                Text(s.$1),
                const SizedBox(width: 6),
              ]),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(key: const Key('source_debug'), tooltip: '调试', icon: const Icon(Icons.bug_report_outlined), onPressed: _debug),
          IconButton(key: const Key('source_save'), tooltip: '保存', icon: const Icon(Icons.save_outlined), onPressed: _save),
          PopupMenuButton<String>(
            key: const Key('source_more'),
            tooltip: '更多',
            onSelected: _onSelected,
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'search', child: Text('搜索')),
              PopupMenuItem(value: 'login', child: Text('登录')),
              PopupMenuItem(value: 'copy', child: Text('复制书源')),
              PopupMenuItem(value: 'paste', child: Text('粘贴书源')),
              PopupMenuItem(value: 'setVariable', child: Text('设置源变量')),
              PopupMenuItem(value: 'clearcookie', child: Text('清除Cookie')),
              PopupMenuItem(value: 'cleancaches', child: Text('清除缓存')),
              PopupMenuItem(value: 'help', child: Text('帮助')),
            ],
          ),
        ],
        bottom: TabBar(controller: _tabController, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in bookSourceTabs) Tab(text: t.$1)]),
      ),
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(
            child: TabBarView(controller: _tabController, children: [
              for (final t in bookSourceTabs)
                ListView(children: [
                  for (final f in t.$2) ruleFieldRow(context, f.label, _form.controllers[SourceForm.id(f)]!, key: Key('field_${SourceForm.id(f)}')),
                  const SizedBox(height: 24),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
