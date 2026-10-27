// pages/discovery_page.dart — 发现, classic two-pane layout (`DiscoveryPage`, used when `discoveryStyle` != 0, main_page 0x50d560):
// DiscoveryLeftPage (source column with the group filter) and DiscoveryRightPage (explore tags + books of the chosen source).
// App bar: 「发现」, 「搜索」, 「编辑书源」 of the selected source.
import 'package:flutter/material.dart';

import '../common/nav.dart';
import '../data/source.dart';
import '../models/source.dart';
import '../widget/base_page.dart';
import '../widget/discovery/discovery_left.dart';
import '../widget/discovery/discovery_right.dart';
import 'discovery_page_new.dart';
import 'search/search_book_page.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends BasePage<DiscoveryPage> with AutomaticKeepAliveClientMixin {
  List<Source>? _sources;
  Source? _source;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Sourcedata.load();
    final list = exploreSources();
    final url = DiscoveryPrefs.selectedUrl;
    update(() {
      _sources = list;
      _source = list.where((s) => s.bookSourceUrl == (_source?.bookSourceUrl ?? url)).firstOrNull ?? list.firstOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _sources;
    final s = _source;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchBookPage())),
          ),
          if (s != null) IconButton(tooltip: '编辑书源', icon: const Icon(Icons.edit_note), onPressed: () => Nav.openSourceEdit(context, s)),
        ],
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('请先前往书源管理中添加书源并启用发现'))
              : Row(children: [
                  SizedBox(
                    width: 112,
                    child: DiscoveryLeftPage(
                      sources: list,
                      selected: s,
                      onSelect: (x) async {
                        await DiscoveryPrefs.setSelected(x);
                        update(() => _source = x);
                      },
                      onChanged: _load,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: s == null ? const Center(child: Text('未选择书源')) : DiscoveryRightPage(source: s)),
                ]),
    );
  }
}
