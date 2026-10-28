// pages/source/sg_login.dart — login and help of a 时光源 (the `source_login` route, the source manager's 登录 / 帮助, the editor's
// menu). Original login 0xe5b940 (reached from the shelf 0xf736c4, the discovery page 0xfb8b98 / 0x5bca34, the reader, the editor
// 0xfc6814 …): the page's `getloginurl()` (0xe61ae0, errors logged as `书源: …`) answers
//   * an `http(s)` url (or a `data:text/html` page): opened in the source's browser page, whose cookies go to the app's store;
//   * the JSON array of a login form `[{name, type: text|password|select|button, action, chars, default}]` (template pp+0x53130):
//     shown as a dialog; the values are saved as JSON with `cache.set("LoginInfo", …)` (the page reads them with
//     `cache.getLoginInfo()`), then `await login()` runs; buttons run their `action` in the page;
//   * nothing: `未获取到登录参数!`; anything else: `当前登录地址不正确!`.
// Afterwards the search cache of the source is dropped (0x1ba52c). Help (`启用帮助`, 0xf8dae0): `gethelp()` answers an http url
// (browser), plain text or `@html:` html (shown as text here).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../api/sourceapi.dart';
import '../../util/legado/html_formatter.dart';
import '../../util/source/baswebview.dart';
import '../../util/source/cache.dart';
import '../../util/source/run.dart';
import '../../util/source/source.dart';
import '../../util/source/time_source_api.dart';
import '../../util/toast.dart';

/// The rows of a login form text (anything but a JSON array of objects gives none).
List<Map<String, dynamic>> sgLoginRows(String text) {
  try {
    final v = jsonDecode(text);
    if (v is List) return [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];
  } catch (_) {}
  return const [];
}

bool _isPage(String url) {
  final t = url.trim().toLowerCase();
  return t.startsWith('http://') || t.startsWith('https://') || (t.startsWith('data') && t.contains('text/html'));
}

/// Opens the login of the 时光源 [s].
Future<void> showTimeSourceLogin(BuildContext context, BaseSource s) async {
  String url;
  try {
    url = (await TimeSourceApi.loginUrl(s)).trim();
  } catch (e) {
    Toast.show('书源: $e', iserror: true);
    return;
  }
  if (url.isEmpty) {
    Toast.show('未获取到登录参数!');
    return;
  }
  if (_isPage(url)) {
    await SourceUi.openBrowser?.call(SourceBrowserRequest(url: url, title: '登录', source: s));
    SourceApi.cache.removeSource(s.bookSourceUrl);
    return;
  }
  final rows = sgLoginRows(url);
  if (rows.isEmpty) {
    Toast.show('当前登录地址不正确!');
    return;
  }
  final saved = await sgLoginInfo(s);
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (c) => TimeSourceLoginDialog(source: s, rows: rows, saved: saved));
  SourceApi.cache.removeSource(s.bookSourceUrl);
}

/// The saved form values (`LoginInfo` of the source's cache, a JSON object).
Future<Map<String, String>> sgLoginInfo(BaseSource s) async {
  final t = await Cache(s.bookSourceUrl).get('LoginInfo');
  try {
    final v = jsonDecode(t);
    if (v is Map) return {for (final e in v.entries) '${e.key}': '${e.value ?? ''}'};
  } catch (_) {}
  return {};
}

class TimeSourceLoginDialog extends StatefulWidget {
  final BaseSource source;
  final List<Map<String, dynamic>> rows;
  final Map<String, String> saved;
  const TimeSourceLoginDialog({super.key, required this.source, required this.rows, this.saved = const {}});

  @override
  State<TimeSourceLoginDialog> createState() => _TimeSourceLoginDialogState();
}

class _TimeSourceLoginDialogState extends State<TimeSourceLoginDialog> {
  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _choice = {};
  bool _busy = false;

  static String _type(Map<String, dynamic> r) => '${r['type'] ?? 'text'}'.trim().toLowerCase();

  static List<String> _chars(Map<String, dynamic> r) => r['chars'] is List ? (r['chars'] as List).map((e) => '$e').toList() : <String>[];

  @override
  void initState() {
    super.initState();
    for (final r in widget.rows) {
      final name = '${r['name'] ?? ''}';
      final type = _type(r);
      if (type == 'select') {
        final chars = _chars(r);
        _choice[name] = widget.saved[name] ?? '${r['default'] ?? (chars.isEmpty ? '' : chars.first)}';
      } else if (type != 'button') {
        _fields[name] = TextEditingController(text: widget.saved[name] ?? '${r['default'] ?? ''}');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _values => {for (final e in _fields.entries) e.key: e.value.text, ..._choice};

  Future<void> _store() => Cache(widget.source.bookSourceUrl).set('LoginInfo', jsonEncode(_values));

  Future<void> _run(Future<String> Function(SourceRun run) f) async {
    setState(() => _busy = true);
    try {
      await _store();
      final r = await f(await SourceRun.of(widget.source));
      if (r.isNotEmpty) Toast.show(r);
    } catch (e) {
      Toast.show('$e', iserror: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String action) async {
    debugPrint('执行动作: $action');
    if (_isPage(action)) {
      await SourceUi.openBrowser?.call(SourceBrowserRequest(url: action.trim(), title: '登录', source: widget.source));
      return;
    }
    await _run((run) => run.runJs(action));
  }

  Future<void> _login() async {
    await _run((run) => run.login());
    if (mounted) Navigator.of(context).pop();
  }

  Widget _row(Map<String, dynamic> r) {
    final name = '${r['name'] ?? ''}';
    switch (_type(r)) {
      case 'button':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: OutlinedButton(onPressed: _busy ? null : () => _action('${r['action'] ?? ''}'), child: Text(name)),
        );
      case 'select':
        final chars = _chars(r);
        final cur = _choice[name] ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: DropdownButtonFormField<String>(
            initialValue: chars.contains(cur) ? cur : null,
            decoration: InputDecoration(labelText: name, border: const OutlineInputBorder(), isDense: true),
            items: [for (final c in chars) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _choice[name] = v ?? ''),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextField(
            key: Key('sg_login_$name'),
            controller: _fields[name],
            obscureText: _type(r) == 'password',
            decoration: InputDecoration(labelText: name, border: const OutlineInputBorder(), isDense: true),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('登录 ${widget.source.bookSourceName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [for (final r in widget.rows) _row(r)])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        ElevatedButton(key: const Key('sg_login_ok'), onPressed: _busy ? null : _login, child: const Text('登录')),
      ],
    );
  }
}

/// 帮助 of a 时光源 with 启用帮助.
Future<void> showTimeSourceHelp(BuildContext context, BaseSource s) async {
  String v;
  try {
    v = (await TimeSourceApi.help(s)).trim();
  } catch (e) {
    Toast.show('$e', iserror: true);
    return;
  }
  if (v.isEmpty) {
    Toast.show('当前书源没有帮助');
    return;
  }
  if (_isPage(v)) {
    await SourceUi.openBrowser?.call(SourceBrowserRequest(url: v, title: '帮助', source: s));
    return;
  }
  final text = v.startsWith('@html:') ? HtmlFormatter.stripTags(v.substring(6)) : v;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('帮助'),
      content: SingleChildScrollView(child: SelectableText(text)),
      actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('关闭'))],
    ),
  );
}
