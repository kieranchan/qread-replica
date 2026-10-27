// widget/exploration/grid_widget.dart — 宫格 (`GridWidget`): covers in rows of three (count, default 6).
import 'package:flutter/material.dart';

import '../../models/book.dart';
import 'exploration_component.dart';

class GridWidget extends StatefulWidget {
  final ComponentConfig config;
  const GridWidget({super.key, required this.config});

  @override
  State<GridWidget> createState() => _GridWidgetState();
}

class _GridWidgetState extends State<GridWidget> {
  late final Future<List<Book>> _f =
      loadComponentBooks(widget.config, count: widget.config.count > 0 ? widget.config.count : ComponentType.grid.defaultCount);

  @override
  Widget build(BuildContext context) {
    return ComponentSection(
      title: widget.config.title,
      future: _f,
      builder: (c, books) => LayoutBuilder(builder: (c, box) {
        const cols = 3;
        final gap = widget.config.gap;
        final w = (box.maxWidth - 32 - gap * (cols - 1)) / cols;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: gap, runSpacing: gap, children: [for (final b in books) CoverCell(book: b, width: w)]),
        );
      }),
    );
  }
}
