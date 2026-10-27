// pages/rss/bedit.dart — editor of an RSS source run by the replica's engine (订阅编辑, `rssbedit`). Original `_EditRssSourcePageState`
// (page 0x58660c `编辑订阅源` with the tabs 基本 / 启动 / 列表 / WEB_VIEW; switches 0x58832c 启用 / 单URL / CookieJar / 预加载 and 0x586f58
// 启用 JavaScript / 加载 BaseUrl / 输出 WEBLOG / 优先加载缓存; field rows `{label, code}` 0x58724c with `编辑代码`; JSON build 0x588d98;
// menu 0xfaab74 help (Legado rss tutorial) / login (`请先保存订阅源`) / copy `订阅源已复制` / setVariable / clearcookie / cleancaches /
// paste; save `源URL不能为空`, `确定要保存订阅源吗？`, `保存成功`). Backend RSS sources use the same page (qedit.dart).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/rss.dart';
import '../../util/legado/cookie_jar.dart';
import '../../util/toast.dart';
import '../../util/webbook/model/rss_source.dart';
import '../source/edit_bqsource.dart' show RuleField, SourceForm, ruleFieldRow;
import '../source/login_dialog.dart';
import '../web/webview.dart';
import 'debug.dart';

const List<(String, List<RuleField>)> rssSourceTabs = [
  ('基本', [
    RuleField('源名称', 'sourceName'),
    RuleField('源URL', 'sourceUrl'),
    RuleField('图标', 'sourceIcon'),
    RuleField('分组', 'sourceGroup'),
    RuleField('注释', 'sourceComment'),
    RuleField('分类URL', 'sortUrl'),
    RuleField('搜索URL', 'searchUrl'),
    RuleField('登录URL', 'loginUrl'),
    RuleField('登录UI', 'loginUi'),
    RuleField('登录检查JS', 'loginCheckJs'),
    RuleField('封面解密', 'coverDecodeJs'),
    RuleField('请求头', 'header'),
    RuleField('变量说明', 'variableComment'),
    RuleField('并发率', 'concurrentRate'),
    RuleField('jsLib', 'jsLib'),
  ]),
  ('启动', [
    RuleField('启动页HTML', 'startHtml'),
    RuleField('启动页JS', 'startJs'),
    RuleField('启动页样式', 'startStyle'),
    RuleField('预加载JS', 'preloadJs'),
  ]),
  ('列表', [
    RuleField('列表规则', 'ruleArticles'),
    RuleField('列表下一页规则', 'ruleNextArticles'),
    RuleField('下一页规则', 'ruleNextPage'),
    RuleField('标题规则', 'ruleTitle'),
    RuleField('时间规则', 'rulePubDate'),
    RuleField('描述规则', 'ruleDescription'),
    RuleField('图片规则', 'ruleImage'),
    RuleField('链接规则', 'ruleLink'),
  ]),
  ('WEB_VIEW', [
    RuleField('内容规则', 'ruleContent'),
    RuleField('样式', 'style'),
    RuleField('注入JS', 'injectJs'),
    RuleField('内容白名单', 'contentWhitelist'),
    RuleField('内容黑名单', 'contentBlacklist'),
    RuleField('网址拦截JS', 'urlBlockJs'),
    RuleField('跳转处理(shouldOverrideUrlLoading)', 'shouldOverrideUrlLoading'),
  ]),
];

const List<(String, String, bool)> rssSourceSwitches = [
  ('启用', 'enabled', true),
  ('单URL', 'singleUrl', false),
  ('CookieJar', 'enabledCookieJar', true),
  ('预加载', 'preload', false),
  ('启用 JavaScript', 'enableJs', true),
  ('加载 BaseUrl', 'loadWithBaseUrl', true),
  ('输出 WEBLOG', 'showWebLog', false),
  ('优先加载缓存', 'cacheFirst', false),
];

/// `articleStyle` choices.
const List<(int, String)> rssArticleStyles = [(0, '列表'), (1, '大图'), (2, '网格')];

class EditBRssSourcePage extends StatefulWidget {
  final Map<String, dynamic>? source;

  /// Saves instead of the local store (backend, qedit.dart).
  final Future<void> Function(String oldUrl, Map<String, dynamic> json)? onSave;
  const EditBRssSourcePage({super.key, this.source, this.onSave});

  @override
  State<EditBRssSourcePage> createState() => _EditRssSourcePageState();
}

class _EditRssSourcePageState extends State<EditBRssSourcePage> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: rssSourceTabs.length, vsync: this);
  late final SourceForm _form = SourceForm(widget.source, tabs: rssSourceTabs, switches: rssSourceSwitches, typeKey: 'articleStyle');
  late String _savedUrl = '${widget.source?['sourceUrl'] ?? ''}';

  @override
  void dispose() {
    _tab.dispose();
    _form.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _json => _form.build();
  RssSource get _engine => RssSource.fromJson(_json);

  Future<void> _save() async {
    final json = _json;
    final url = '${json['sourceUrl'] ?? ''}'.trim();
    if (url.isEmpty) {
      Toast.show('源URL不能为空');
      return;
    }
    if ('${json['sourceName'] ?? ''}'.trim().isEmpty) {
      Toast.show('源名称不能为空');
      return;
    }
    try {
      if (widget.onSave != null) {
        await widget.onSave!(_savedUrl.isEmpty ? url : _savedUrl, json);
      } else {
        await RssSources.update(_savedUrl.isEmpty ? url : _savedUrl, json);
      }
      _savedUrl = url;
      Toast.show('保存成功');
    } catch (e) {
      Toast.show('保存失败:$e', iserror: true);
    }
  }

  Future<void> _onSelected(String v) async {
    switch (v) {
      case 'help':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (c) => const WebviewPage(url: 'https://mgz0227.github.io/The-tutorial-of-Legado/Rule/rss.html', title: '订阅源规则帮助')));
      case 'login':
        if (_savedUrl.isEmpty) {
          Toast.show('请先保存订阅源');
          return;
        }
        await showSourceLogin(context, _engine);
      case 'debug':
        await Navigator.of(context).push(MaterialPageRoute(builder: (c) => DebugRssPage(source: _json)));
      case 'copy':
        await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_json)));
        Toast.show('订阅源已复制');
      case 'paste':
        try {
          final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
          if (t.isEmpty) {
            Toast.show('剪贴板为空!');
            return;
          }
          final d = jsonDecode(t);
          setState(() => _form.load(Map<String, dynamic>.from((d is List ? d.first : d) as Map)));
        } catch (e) {
          Toast.show('粘贴失败:$e!');
        }
      case 'setVariable':
        await showSourceVariableDialog(context, _engine);
      case 'clearcookie':
        CookieStore.removeCookie('${_json['sourceUrl'] ?? ''}');
        Toast.show('清除成功！');
      case 'cleancaches':
        Toast.show('清除成功！');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑订阅源'),
        actions: [
          IconButton(key: const Key('rss_save'), tooltip: '保存', icon: const Icon(Icons.save_outlined), onPressed: _save),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onSelected,
            itemBuilder: (c) => const [
              PopupMenuItem(value: 'debug', child: Text('调试')),
              PopupMenuItem(value: 'login', child: Text('登录')),
              PopupMenuItem(value: 'copy', child: Text('复制订阅源')),
              PopupMenuItem(value: 'paste', child: Text('粘贴订阅源')),
              PopupMenuItem(value: 'setVariable', child: Text('设置源变量')),
              PopupMenuItem(value: 'clearcookie', child: Text('清除Cookie')),
              PopupMenuItem(value: 'cleancaches', child: Text('清除缓存')),
              PopupMenuItem(value: 'help', child: Text('帮助')),
            ],
          ),
        ],
        bottom: TabBar(controller: _tab, tabs: [for (final t in rssSourceTabs) Tab(text: t.$1)]),
      ),
      body: SafeArea(
        child: Column(children: [
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                const Text('样式：'),
                DropdownButton<int>(
                  value: rssArticleStyles.any((t) => t.$1 == (_form.type ?? 0)) ? (_form.type ?? 0) : 0,
                  underline: const SizedBox(),
                  items: [for (final t in rssArticleStyles) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
                  onChanged: (v) => setState(() => _form.type = v),
                ),
                for (final s in rssSourceSwitches.take(4))
                  Row(children: [
                    Checkbox(value: _form.flags[s.$2] ?? s.$3, onChanged: (v) => setState(() => _form.flags[s.$2] = v ?? false)),
                    Text(s.$1),
                  ]),
              ]),
            ),
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              for (final t in rssSourceTabs)
                ListView(children: [
                  if (t.$1 == 'WEB_VIEW')
                    for (final s in rssSourceSwitches.skip(4))
                      CheckboxListTile(dense: true, title: Text(s.$1), value: _form.flags[s.$2] ?? s.$3, onChanged: (v) => setState(() => _form.flags[s.$2] = v ?? false)),
                  for (final f in t.$2) ruleFieldRow(context, f.label, _form.controllers[SourceForm.id(f)]!, key: Key('rss_field_${f.key}')),
                  const SizedBox(height: 24),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
