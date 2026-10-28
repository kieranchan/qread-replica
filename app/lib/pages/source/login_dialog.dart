// pages/source/login_dialog.dart — not a file of the original: the original repeats these dialogs in each page that offers them
// (rss_page.dart `_showLogin` 0x8ed61c + dialog 0x1ba788, rss_articles.dart 0x59cf04, bedit.dart 0x58cbf4, the variable dialogs
// 0x52c704 / 0x59c508 / 0x58ab0c). The replica keeps one copy here.
//
//   * login UI (Legado `loginUi`): JSON list of rows `{name, type: text|password|button|toggle|select, action, chars, default,
//     style{layout_flexBasisPercent…}}`; text rows prefill from the saved login info, buttons run their `action` (an url opens
//     the browser, anything else is JavaScript appended to the login script, `执行动作: `), ✓ saves the info (`Input values: `)
//     and runs `login()`; the key icon shows the saved `loginHeader`.
//   * no login UI: `loginUrl` is opened in the web page (`没有获取到登陆地址!`, `当前登录地址不正确!`).
//   * variables (`变量说明`): the source variable text with the source's `variableComment` as help.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../qread/qread_jobs.dart';
import '../../util/toast.dart';
import '../../util/webbook/model/base_source.dart';
import '../web/webview.dart';

/// Legado `getLoginJs()`: the JavaScript part of `loginUrl`.
String? loginJsOf(BaseSource source) {
  final u = source.loginUrl?.trim();
  if (u == null || u.isEmpty) return null;
  if (u.startsWith('@js:')) return u.substring(4);
  if (u.startsWith('<js>')) {
    final end = u.lastIndexOf('<');
    return u.substring(4, end > 4 ? end : u.length);
  }
  return u;
}

/// The rows of a `loginUi` text (invalid JSON gives no rows).
List<Map<String, dynamic>> loginUiRows(String? loginUi) {
  if (loginUi == null || loginUi.trim().isEmpty) return const [];
  try {
    final v = jsonDecode(loginUi);
    if (v is List) return [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];
  } catch (_) {}
  return const [];
}

/// Opens the login of [source] (dialog or web page).
Future<void> showSourceLogin(BuildContext context, BaseSource source) async {
  final rows = loginUiRows(source.loginUi);
  if (rows.isEmpty) {
    final url = source.loginUrl?.trim() ?? '';
    if (url.isEmpty) {
      Toast.show('没有获取到登陆地址!');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      Toast.show('当前登录地址不正确!');
      return;
    }
    Map<String, String>? header;
    try {
      header = await source.getHeaderMap(true);
    } catch (_) {}
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (c) => WebviewPage(url: url, title: '登录', header: header)));
    return;
  }
  await showDialog<void>(context: context, builder: (c) => SourceLoginDialog(source: source, rows: rows));
}

class SourceLoginDialog extends StatefulWidget {
  final BaseSource source;
  final List<Map<String, dynamic>> rows;
  const SourceLoginDialog({super.key, required this.source, required this.rows});

  @override
  State<SourceLoginDialog> createState() => _SourceLoginDialogState();
}

class _SourceLoginDialogState extends State<SourceLoginDialog> {
  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _choice = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fill(widget.source.getLoginInfoMap().map);
    // the 轻阅读 backend's device jobs (0x1e90 / 0x1e94): reLoginView reloads the saved values, upLoginData fills in a JSON object
    QreadHooks.reLoginView = _reload;
    QreadHooks.upLoginData = _upLoginData;
  }

  void _reload() {
    if (mounted) setState(() => _fill(widget.source.getLoginInfoMap().map));
  }

  void _upLoginData(String data) {
    try {
      final m = jsonDecode(data);
      if (m is Map && mounted) setState(() => _fill(m));
    } catch (_) {}
  }

  void _fill(Map<dynamic, dynamic> saved) {
    for (final r in widget.rows) {
      final name = '${r['name'] ?? ''}';
      final type = '${r['type'] ?? 'text'}';
      if (type == 'text' || type == 'password') {
        final text = '${saved[name] ?? r['default'] ?? ''}';
        final c = _fields[name];
        if (c == null) {
          _fields[name] = TextEditingController(text: text);
        } else {
          c.text = text;
        }
      } else if (type == 'toggle' || type == 'select') {
        final chars = r['chars'] is List ? (r['chars'] as List).map((e) => '$e').toList() : <String>[];
        _choice[name] = '${saved[name] ?? r['default'] ?? (chars.isEmpty ? '' : chars.first)}';
      }
    }
  }

  @override
  void dispose() {
    if (QreadHooks.reLoginView == _reload) QreadHooks.reLoginView = null;
    if (QreadHooks.upLoginData == _upLoginData) QreadHooks.upLoginData = null;
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _values => {for (final e in _fields.entries) e.key: e.value.text, ..._choice};

  Future<void> _runAction(String action) async {
    debugPrint('执行动作: $action');
    if (action.startsWith('http://') || action.startsWith('https://')) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (c) => WebviewPage(url: action, title: '登录')));
      return;
    }
    setState(() => _busy = true);
    try {
      widget.source.putLoginInfo(jsonEncode(_values));
      final r = await widget.source.evalJS('${loginJsOf(widget.source) ?? ''}\n$action', values: {'result': _values});
      if (r != null && '$r'.isNotEmpty) Toast.show('$r');
    } catch (e) {
      Toast.show('$e', iserror: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ✓: save the values and run `login()` (Legado SourceLoginDialog).
  Future<void> _save() async {
    debugPrint('Input values: $_values');
    widget.source.putLoginInfo(jsonEncode(_values));
    final js = loginJsOf(widget.source);
    if (js != null && !js.startsWith('http')) {
      setState(() => _busy = true);
      try {
        await widget.source.evalJS("$js\nif(typeof login=='function'){login.apply(this);}else{throw('Function login not implements!!!')}");
        Toast.show('登录成功');
      } catch (e) {
        Toast.show('$e', iserror: true);
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showHeader() => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('登录头'),
          content: SelectableText(widget.source.getLoginHeader() ?? ''),
          actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('确定'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('登录', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(tooltip: '登录头', icon: const Icon(Icons.vpn_key_outlined), onPressed: _showHeader),
              IconButton(key: const Key('login_save'), tooltip: '确定', icon: const Icon(Icons.check), onPressed: _busy ? null : _save),
            ]),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final r in widget.rows) _row(r),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final name = '${r['name'] ?? ''}';
    final type = '${r['type'] ?? 'text'}';
    if (type == 'text' || type == 'password') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          key: Key('login_$name'),
          controller: _fields[name],
          obscureText: type == 'password',
          decoration: InputDecoration(labelText: name, border: const OutlineInputBorder(), isDense: true),
        ),
      );
    }
    if (type == 'toggle' || type == 'select') {
      final chars = r['chars'] is List ? (r['chars'] as List).map((e) => '$e').toList() : <String>[];
      return IntrinsicWidth(
        child: OutlinedButton(
          onPressed: chars.isEmpty
              ? null
              : () => setState(() {
                    final i = chars.indexOf(_choice[name] ?? '');
                    _choice[name] = chars[(i + 1) % chars.length];
                  }),
          child: Text('$name ${_choice[name] ?? ''}'),
        ),
      );
    }
    // button
    return IntrinsicWidth(
      child: ElevatedButton(
        key: Key('login_btn_$name'),
        onPressed: _busy ? null : () => _runAction('${r['action'] ?? ''}'),
        child: Text(name),
      ),
    );
  }
}

/// The variable dialog (`变量说明`): edits `source.getVariable()`; [onSave] replaces the local store (backend sources).
Future<void> showSourceVariableDialog(BuildContext context, BaseSource source, {String? current, Future<void> Function(String v)? onSave}) async {
  final c = TextEditingController(text: current ?? source.getVariable() ?? '');
  final comment = source.variableComment ?? '';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('设置源变量'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(key: const Key('variable_input'), controller: c, maxLines: 6, minLines: 3, decoration: const InputDecoration(hintText: '请输入内容...', border: OutlineInputBorder())),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('变量说明', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(comment, style: const TextStyle(height: 1.5)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
        ElevatedButton(key: const Key('variable_ok'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
      ],
    ),
  );
  if (ok != true) return;
  if (onSave != null) {
    await onSave(c.text);
  } else {
    source.setVariable(c.text);
  }
}
