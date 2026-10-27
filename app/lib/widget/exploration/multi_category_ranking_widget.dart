// widget/exploration/multi_category_ranking_widget.dart — 多分类排行榜 (`MultiCategoryRankingWidget`): tabs over the configured
// `categories` (at least two: 「多分类排行榜至少选择2个分类」), each a ranking of `countPerCategory` books.
import 'package:flutter/material.dart';

import '../../models/book.dart';
import 'exploration_component.dart';

class MultiCategoryRankingWidget extends StatefulWidget {
  final ComponentConfig config;
  const MultiCategoryRankingWidget({super.key, required this.config});

  @override
  State<MultiCategoryRankingWidget> createState() => _MultiCategoryRankingWidgetState();
}

class _MultiCategoryRankingWidgetState extends State<MultiCategoryRankingWidget> {
  int _tab = 0;
  final Map<int, Future<List<Book>>> _futures = {};

  Future<List<Book>> _load(int i) => _futures.putIfAbsent(
      i, () => loadComponentBooks(widget.config, url: widget.config.categories[i]['exploreUrl'], count: widget.config.countPerCategory));

  @override
  Widget build(BuildContext context) {
    final cats = widget.config.categories;
    if (cats.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('多分类排行榜需要选择多个分类'));
    final i = _tab.clamp(0, cats.length - 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.config.title.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(widget.config.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (var k = 0; k < cats.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              child: ChoiceChip(label: Text(cats[k]['title']!), selected: k == i, onSelected: (_) => setState(() => _tab = k)),
            ),
        ]),
      ),
      ComponentSection(
        key: ValueKey(i),
        title: '',
        future: _load(i),
        builder: (c, books) => Column(children: [for (var r = 0; r < books.length; r++) RankRow(book: books[r], rank: r + 1)]),
      ),
    ]);
  }
}
