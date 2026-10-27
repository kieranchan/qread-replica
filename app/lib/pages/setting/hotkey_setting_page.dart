// pages/setting/hotkey_setting_page.dart — 快捷按键 (desktop builds; `HotkeySettingPage`, 31 functions). Seven prefs keys with their
// defaults (accessors 0x9267fc … 0x9269dc): hotkeyNextPage `arrowright`, hotkeyPreviousPage `arrowleft`, hotkeyNormalTitleBar `f12`,
// hotkeyFrameless `f11`, hotkeyShow `f9`, hotkeyMinimize `f10`, hotkeyEscape `escape`. Recording a key: letters, digits, function
// keys and arrows only (`不支持 "x" 键，请使用字母、数字、功能键或方向键`), unique (`"x" 已被其他快捷键占用`), then `快捷键已更新：x`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../storage/storage.dart';
import '../../util/toast.dart';

class HotkeySettingPage extends StatefulWidget {
  const HotkeySettingPage({super.key});

  /// key, label, default.
  static const List<(String, String, String)> items = [
    ('hotkeyNextPage', '下一页', 'arrowright'),
    ('hotkeyPreviousPage', '上一页', 'arrowleft'),
    ('hotkeyNormalTitleBar', '标准标题栏', 'f12'),
    ('hotkeyFrameless', '无边框窗口', 'f11'),
    ('hotkeyShow', '显示窗口', 'f9'),
    ('hotkeyMinimize', '最小化', 'f10'),
    ('hotkeyEscape', '返回', 'escape'),
  ];

  static String get(String key) {
    final d = items.firstWhere((e) => e.$1 == key, orElse: () => (key, key, '')).$3;
    final v = Storage.getString(key);
    return v.isEmpty ? d : v;
  }

  /// The stored name of a key (`a`, `5`, `f9`, `arrowleft`, `escape`), null when the key is not allowed.
  static String? keyName(LogicalKeyboardKey k) {
    final label = k.keyLabel.toLowerCase();
    if (RegExp(r'^[a-z0-9]$').hasMatch(label)) return label;
    if (RegExp(r'^f([1-9]|1[0-2])$').hasMatch(label)) return label;
    if (k == LogicalKeyboardKey.arrowLeft) return 'arrowleft';
    if (k == LogicalKeyboardKey.arrowRight) return 'arrowright';
    if (k == LogicalKeyboardKey.arrowUp) return 'arrowup';
    if (k == LogicalKeyboardKey.arrowDown) return 'arrowdown';
    if (k == LogicalKeyboardKey.escape) return 'escape';
    return null;
  }

  /// Validates and stores; returns the message the page shows.
  static Future<String> assign(String key, String name) async {
    for (final e in items) {
      if (e.$1 != key && get(e.$1) == name) return '"$name" 已被其他快捷键占用';
    }
    await Storage.setString(key, name);
    return '快捷键已更新：$name';
  }

  @override
  State<HotkeySettingPage> createState() => _HotkeySettingPageState();
}

class _HotkeySettingPageState extends State<HotkeySettingPage> {
  String? _recording;
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final key = _recording;
    if (key == null || e is! KeyDownEvent) return KeyEventResult.ignored;
    final name = HotkeySettingPage.keyName(e.logicalKey);
    if (name == null) {
      Toast.show('不支持 "${e.logicalKey.keyLabel}" 键，请使用字母、数字、功能键或方向键', iserror: true);
      return KeyEventResult.handled;
    }
    HotkeySettingPage.assign(key, name).then((msg) {
      Toast.show(msg, iserror: !msg.startsWith('快捷键已更新'));
      if (mounted) setState(() => _recording = null);
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('快捷按键')),
        body: ListView(children: [
          for (final e in HotkeySettingPage.items)
            ListTile(
              title: Text(e.$2),
              trailing: Chip(label: Text(_recording == e.$1 ? '请按键…' : HotkeySettingPage.get(e.$1).toUpperCase())),
              onTap: () {
                setState(() => _recording = e.$1);
                _focus.requestFocus();
              },
            ),
        ]),
      ),
    );
  }
}
