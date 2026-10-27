// widget/exploration/network_ranking_widget.dart — 网络排行榜 (`NetworkRankingWidget`): a ranking taken from the source's explore
// page, two columns on wide screens. TODO(asm 0x7b3450): the original may page (`page`, `hot`); one page is shown here.
import 'package:flutter/material.dart';

import '../../models/book.dart';
import 'exploration_component.dart';

class NetworkRankingWidget extends StatefulWidget {
  final ComponentConfig config;
  const NetworkRankingWidget({super.key, required this.config});

  @override
  State<NetworkRankingWidget> createState() => _NetworkRankingWidgetState();
}

class _NetworkRankingWidgetState extends State<NetworkRankingWidget> {
  late final Future<List<Book>> _f = loadComponentBooks(widget.config, count: widget.config.count > 0 ? widget.config.count : 10);

  @override
  Widget build(BuildContext context) => ComponentSection(
        title: widget.config.title,
        future: _f,
        builder: (c, books) => LayoutBuilder(builder: (c, box) {
          final cols = box.maxWidth > 700 ? 2 : 1;
          final per = (books.length / cols).ceil();
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var col = 0; col < cols; col++)
              Expanded(
                child: Column(children: [
                  for (var i = col * per; i < books.length && i < (col + 1) * per; i++) RankRow(book: books[i], rank: i + 1),
                ]),
              ),
          ]);
        }),
      );
}
