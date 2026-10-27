// widget/exploration/staggered_waterfall_widget.dart — 错位瀑布流 (`StaggeredWaterfallWidget`): two columns of covers, the second
// shifted down, alternating heights.
import 'package:flutter/material.dart';

import '../../models/book.dart';
import 'exploration_component.dart';

class StaggeredWaterfallWidget extends StatefulWidget {
  final ComponentConfig config;
  const StaggeredWaterfallWidget({super.key, required this.config});

  @override
  State<StaggeredWaterfallWidget> createState() => _StaggeredWaterfallWidgetState();
}

class _StaggeredWaterfallWidgetState extends State<StaggeredWaterfallWidget> {
  late final Future<List<Book>> _f = loadComponentBooks(widget.config, count: widget.config.count > 0 ? widget.config.count : 10);

  @override
  Widget build(BuildContext context) => ComponentSection(
        title: widget.config.title,
        future: _f,
        builder: (c, books) => LayoutBuilder(builder: (c, box) {
          final gap = widget.config.gap;
          final w = (box.maxWidth - 32 - gap) / 2;
          Widget col(int start) => Column(children: [
                if (start == 1) SizedBox(height: w * 0.35),
                for (var i = start; i < books.length; i += 2)
                  Padding(padding: EdgeInsets.only(bottom: gap), child: CoverCell(book: books[i], width: w, ratio: i % 4 < 2 ? 1.25 : 1.5)),
              ]);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [col(0), SizedBox(width: gap), col(1)]),
          );
        }),
      );
}
