// widget/exploration/ranking_widget.dart — 排行榜 (`RankingWidget`): numbered list of the first `count` books.
import 'package:flutter/material.dart';

import '../../models/book.dart';
import 'exploration_component.dart';

class RankingWidget extends StatefulWidget {
  final ComponentConfig config;
  const RankingWidget({super.key, required this.config});

  @override
  State<RankingWidget> createState() => _RankingWidgetState();
}

class _RankingWidgetState extends State<RankingWidget> {
  late final Future<List<Book>> _f = loadComponentBooks(widget.config, count: widget.config.count > 0 ? widget.config.count : 10);

  @override
  Widget build(BuildContext context) => ComponentSection(
        title: widget.config.title,
        future: _f,
        builder: (c, books) => Column(children: [for (var i = 0; i < books.length; i++) RankRow(book: books[i], rank: i + 1)]),
      );
}
