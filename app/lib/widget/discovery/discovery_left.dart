// widget/discovery/discovery_left.dart — `DiscoveryLeftPage`: the source column of the classic discovery layout. A group filter
// (「全部分组」, the source groups, 「时光源」 = own-format sources (`isqread`), 「阅读源」 = Legado sources, 「未分组」; prefs
// `discoverySelectedGroup`, filter 0x7af6fc) and the sources with explore rules; long press: 「编辑书源」 / 「不是发现」 (switches the
// source's `enabledExplore` off).
import 'package:flutter/material.dart';

import '../../common/nav.dart';
import '../../data/source.dart';
import '../../models/source.dart';
import '../../storage/storage.dart';
import '../ui/q_popup_menu_button.dart';

const String kAllSourceGroups = '全部分组';

/// 0x7af6fc: does [s] belong to the discovery group [g].
bool inDiscoveryGroup(Source s, String g) {
  switch (g) {
    case '':
    case kAllSourceGroups:
      return true;
    case '时光源':
      return s.isqread;
    case '阅读源':
      return !s.isqread;
    case '未分组':
      return s.bookSourceGroup.trim().isEmpty;
    default:
      return s.bookSourceGroup.split(',').map((e) => e.trim()).contains(g);
  }
}

class DiscoveryLeftPage extends StatefulWidget {
  final List<Source> sources;
  final Source? selected;
  final ValueChanged<Source> onSelect;
  final VoidCallback? onChanged;

  const DiscoveryLeftPage({super.key, required this.sources, required this.selected, required this.onSelect, this.onChanged});

  @override
  State<DiscoveryLeftPage> createState() => _DiscoveryLeftPageState();
}

class _DiscoveryLeftPageState extends State<DiscoveryLeftPage> {
  static const String groupKey = 'discoverySelectedGroup';
  late String _group = Storage.getString(groupKey).isEmpty ? kAllSourceGroups : Storage.getString(groupKey);

  List<String> get _groups {
    final set = <String>{};
    for (final s in widget.sources) {
      for (final g in s.bookSourceGroup.split(',')) {
        if (g.trim().isNotEmpty) set.add(g.trim());
      }
    }
    return [kAllSourceGroups, ...set.toList()..sort(), '时光源', '阅读源', '未分组'];
  }

  Future<void> _longPress(Source s) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('编辑书源'), onTap: () => Navigator.of(c).pop('edit')),
          ListTile(leading: const Icon(Icons.visibility_off_outlined), title: const Text('不是发现'), onTap: () => Navigator.of(c).pop('off')),
        ]),
      ),
    );
    if (!mounted) return;
    if (v == 'edit') await Nav.openSourceEdit(context, s);
    if (v == 'off') await Sources.setEnabledExplore([s.bookSourceUrl], false);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.sources.where((s) => inDiscoveryGroup(s, _group)).toList();
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      QPopupMenuButton<String>(
        tooltip: '分组列表',
        items: [for (final g in _groups) QPopupMenuItem.check(value: g, title: g, checked: g == _group)],
        onSelected: (g) async {
          setState(() => _group = g);
          await Storage.setString(groupKey, g);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(_group, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            const Icon(Icons.arrow_drop_down, size: 18),
          ]),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: shown.length,
          itemBuilder: (c, i) {
            final s = shown[i];
            final on = s.bookSourceUrl == widget.selected?.bookSourceUrl;
            return InkWell(
              key: Key('left_${s.bookSourceUrl}'),
              onTap: () => widget.onSelect(s),
              onLongPress: () => _longPress(s),
              child: Container(
                color: on ? scheme.primaryContainer : null,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Text(s.bookSourceName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.bold : FontWeight.normal)),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
