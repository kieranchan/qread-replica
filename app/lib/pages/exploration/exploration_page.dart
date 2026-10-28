// pages/exploration/exploration_page.dart — 探索 tab (`ExplorationPage`): the active exploration template (data/exploration.dart)
// rendered component by component (sorted by `order`), a search bar 「搜索书本或者作者」 (SearchBookPage), 「模版列表」 to switch the
// active template and the editor button. Without templates: 「发现更多精彩」 / 「打造属于你的个性化探索页面」 / 「开始创建」.
import 'package:flutter/material.dart';

import '../../data/exploration.dart';
import '../../models/exploration_template.dart';
import '../../widget/base_page.dart';
import '../../widget/exploration/exploration_component.dart';
import '../../widget/exploration/grid_widget.dart';
import '../../widget/exploration/horizontal_scroll_widget.dart';
import '../../widget/exploration/multi_category_ranking_widget.dart';
import '../../widget/exploration/network_ranking_widget.dart';
import '../../widget/exploration/ranking_widget.dart';
import '../../widget/exploration/recommend_card_widget.dart';
import '../../widget/exploration/staggered_waterfall_widget.dart';
import '../search/search_book_page.dart';
import 'edit/exploration_edit_page.dart';

/// The components of a template in display order.
List<ExplorationComponent> componentsOf(ExplorationTemplate t) {
  final list = [for (final c in t.components) if (c is Map) ExplorationComponent.fromJson(Map<String, dynamic>.from(c)) else if (c is ExplorationComponent) c];
  list.sort((a, b) => a.order.compareTo(b.order));
  return list;
}

/// The widget of one component, inside a `NotificationListener<ScrollNotification>` that stops the component's own scrolling
/// from reaching the page (0x7b3450: `onNotification` is the always-true closure).
Widget componentWidget(ExplorationComponent c) {
  final cfg = ComponentConfig(c.config);
  final key = ValueKey('comp_${c.id}');
  return NotificationListener<ScrollNotification>(onNotification: (_) => true, child: _componentBody(c, cfg, key));
}

Widget _componentBody(ExplorationComponent c, ComponentConfig cfg, Key key) {
  return switch (typeOf(c)) {
    ComponentType.recommendCard => RecommendCardWidget(key: key, config: cfg),
    ComponentType.grid => GridWidget(key: key, config: cfg),
    ComponentType.horizontalScroll => HorizontalScrollWidget(key: key, config: cfg),
    ComponentType.ranking => RankingWidget(key: key, config: cfg),
    ComponentType.networkRanking => NetworkRankingWidget(key: key, config: cfg),
    ComponentType.multiCategoryRanking => MultiCategoryRankingWidget(key: key, config: cfg),
    ComponentType.staggeredWaterfall => StaggeredWaterfallWidget(key: key, config: cfg),
  };
}

class ExplorationPage extends StatefulWidget {
  const ExplorationPage({super.key});

  @override
  State<ExplorationPage> createState() => _ExplorationPageState();
}

class _ExplorationPageState extends BasePage<ExplorationPage> with AutomaticKeepAliveClientMixin {
  bool _loaded = false;
  int _gen = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ExplorationData.load();
    update(() {
      _loaded = true;
      _gen++;
    });
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExplorationEditPage()));
    await _load();
  }

  Future<void> _chooseTemplate() async {
    final list = ExplorationData.templates;
    final cur = ExplorationData.active?.id ?? '';
    final id = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('模版列表'), children: [
        for (final t in list) ChoiceOption<String>(value: t.id, current: cur, title: t.name),
      ]),
    );
    if (id == null) return;
    await Exploration.setActive(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = ExplorationData.active ?? (ExplorationData.templates.isEmpty ? null : ExplorationData.templates.first);
    return Scaffold(
      appBar: AppBar(
        title: const Text('探索'),
        actions: [
          if (ExplorationData.templates.length > 1) IconButton(tooltip: '模版列表', icon: const Icon(Icons.view_list_outlined), onPressed: _chooseTemplate),
          IconButton(key: const Key('explore_edit'), tooltip: '探索编辑', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: InkWell(
                  key: const Key('explore_search'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchBookPage())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
                    child: const Row(children: [Icon(Icons.search, size: 20, color: Colors.grey), SizedBox(width: 8), Text('搜索书本或者作者', style: TextStyle(color: Colors.grey))]),
                  ),
                ),
              ),
              Expanded(
                child: t == null || t.components.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.auto_awesome_outlined, size: 56, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('发现更多精彩', key: Key('explore_empty'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text('打造属于你的个性化探索页面', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _edit, child: const Text('开始创建')),
                        ]),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(key: ValueKey('explore_$_gen'), children: [for (final c in componentsOf(t)) componentWidget(c)]),
                      ),
              ),
            ]),
    );
  }
}
