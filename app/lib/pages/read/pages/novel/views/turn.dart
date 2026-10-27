// pages/read/pages/novel/views/turn.dart — tap zones of the novel reader ("点击区域设置").
//
// Original: class 1537 `ClickAreaSetting` (9 slots topLeft..bottomRight of `ClickAreaType`, JSON `toJson` 0x10171ac, `fromJson` 0x8f7698
// with the values `previousPage` / `nextPage` / `menu` / `none`), stored as JSON text under the prefs key `turntype` (read 0x10c4548,
// write 0x1017130). The default (0x10c4548) is: left column and top-centre = previous page, middle-centre = menu, the rest = next page.
// `CustomClickAreaSetting` is the editor page (strings 点击区域设置 / 保存设置 / 必须至少有一个区域设置为菜单 / 上一页 / 下一页 / 菜单 / 无操作),
// `CustomClickAreaOverlay` draws the 3x3 grid over the page while editing.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../../storage/storage.dart';
import '../../../../../util/toast.dart';

enum ClickAreaType {
  previousPage,
  nextPage,
  menu,
  none;

  String get label => switch (this) {
        ClickAreaType.previousPage => '上一页',
        ClickAreaType.nextPage => '下一页',
        ClickAreaType.menu => '菜单',
        ClickAreaType.none => '无操作',
      };

  static ClickAreaType parse(Object? v, ClickAreaType def) {
    for (final t in ClickAreaType.values) {
      if (t.name == v) return t;
    }
    return def;
  }
}

class ClickAreaSetting {
  /// Row-major: topLeft, topCenter, topRight, middleLeft, middleCenter, middleRight, bottomLeft, bottomCenter, bottomRight.
  final List<ClickAreaType> areas;

  static const List<String> keys = [
    'topLeft', 'topCenter', 'topRight', 'middleLeft', 'middleCenter', 'middleRight', 'bottomLeft', 'bottomCenter', 'bottomRight',
  ];

  static const String prefsKey = 'turntype';

  ClickAreaSetting(List<ClickAreaType> areas) : areas = List<ClickAreaType>.of(areas) {
    assert(this.areas.length == 9);
  }

  /// 0x10c4548 default.
  factory ClickAreaSetting.defaults() => ClickAreaSetting(const [
        ClickAreaType.previousPage, ClickAreaType.previousPage, ClickAreaType.nextPage,
        ClickAreaType.previousPage, ClickAreaType.menu, ClickAreaType.nextPage,
        ClickAreaType.previousPage, ClickAreaType.nextPage, ClickAreaType.nextPage,
      ]);

  factory ClickAreaSetting.fromJson(Map<String, dynamic> json) {
    final d = ClickAreaSetting.defaults();
    return ClickAreaSetting([for (var i = 0; i < 9; i++) ClickAreaType.parse(json[keys[i]], d.areas[i])]);
  }

  Map<String, dynamic> toJson() => {for (var i = 0; i < 9; i++) keys[i]: areas[i].name};

  ClickAreaSetting copy() => ClickAreaSetting(areas);

  bool get hasMenu => areas.contains(ClickAreaType.menu);

  /// The action for a tap at [pos] on a page of [size].
  ClickAreaType hit(Offset pos, Size size) {
    final col = (pos.dx / size.width * 3).floor().clamp(0, 2);
    final row = (pos.dy / size.height * 3).floor().clamp(0, 2);
    return areas[row * 3 + col];
  }

  static ClickAreaSetting load() {
    final text = Storage.getString(prefsKey);
    if (text.isEmpty) return ClickAreaSetting.defaults();
    try {
      final v = jsonDecode(text);
      if (v is Map) return ClickAreaSetting.fromJson(Map<String, dynamic>.from(v));
    } catch (_) {}
    return ClickAreaSetting.defaults();
  }

  Future<void> save() => Storage.setString(prefsKey, jsonEncode(toJson()));
}

/// The 3x3 grid with the action of every cell, drawn over the page.
class CustomClickAreaOverlay extends StatelessWidget {
  final ClickAreaSetting setting;
  final void Function(int index)? onTapArea;

  const CustomClickAreaOverlay({super.key, required this.setting, this.onTapArea});

  static Color colorOf(ClickAreaType t) => switch (t) {
        ClickAreaType.previousPage => Colors.blue.withValues(alpha: 0.25),
        ClickAreaType.nextPage => Colors.green.withValues(alpha: 0.25),
        ClickAreaType.menu => Colors.orange.withValues(alpha: 0.3),
        ClickAreaType.none => Colors.grey.withValues(alpha: 0.15),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var r = 0; r < 3; r++)
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < 3; c++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTapArea == null ? null : () => onTapArea!(r * 3 + c),
                      child: Container(
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: colorOf(setting.areas[r * 3 + c]),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          setting.areas[r * 3 + c].label,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The editor page: tap a cell to choose its action, then 保存设置.
class CustomClickAreaSetting extends StatefulWidget {
  final ClickAreaSetting? initial;
  final ValueChanged<ClickAreaSetting>? onSaved;

  const CustomClickAreaSetting({super.key, this.initial, this.onSaved});

  @override
  State<CustomClickAreaSetting> createState() => _CustomClickAreaSettingState();
}

class _CustomClickAreaSettingState extends State<CustomClickAreaSetting> {
  late ClickAreaSetting _setting;

  @override
  void initState() {
    super.initState();
    _setting = (widget.initial ?? ClickAreaSetting.load()).copy();
  }

  Future<void> _choose(int index) async {
    final t = await showModalBottomSheet<ClickAreaType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in ClickAreaType.values)
              ListTile(
                title: Text(t.label),
                trailing: _setting.areas[index] == t ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (t == null || !mounted) return;
    setState(() => _setting.areas[index] = t);
  }

  Future<void> _save() async {
    if (!_setting.hasMenu) {
      Toast.show('必须至少有一个区域设置为菜单');
      return;
    }
    await _setting.save();
    widget.onSaved?.call(_setting.copy());
    if (mounted) Navigator.pop(context, _setting.copy());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('点击区域设置'),
        actions: [TextButton(onPressed: _save, child: const Text('保存设置'))],
      ),
      body: CustomClickAreaOverlay(setting: _setting, onTapArea: _choose),
    );
  }
}
