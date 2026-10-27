// widget/exploration/horizontal_scroll_widget.dart — 左右滑动 (`HorizontalScrollWidget`): one horizontally scrolling row of
// covers (`itemWidth`, `gap`).
import 'package:flutter/material.dart';

import '../../models/book.dart';
import 'exploration_component.dart';

class HorizontalScrollWidget extends StatefulWidget {
  final ComponentConfig config;
  const HorizontalScrollWidget({super.key, required this.config});

  @override
  State<HorizontalScrollWidget> createState() => _HorizontalScrollWidgetState();
}

class _HorizontalScrollWidgetState extends State<HorizontalScrollWidget> {
  late final Future<List<Book>> _f = loadComponentBooks(widget.config, count: widget.config.count > 0 ? widget.config.count : 10);

  @override
  Widget build(BuildContext context) {
    final w = widget.config.itemWidth;
    return ComponentSection(
      title: widget.config.title,
      future: _f,
      builder: (c, books) => SizedBox(
        height: w * 4 / 3 + 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: books.length,
          separatorBuilder: (c, i) => SizedBox(width: widget.config.gap),
          itemBuilder: (c, i) => CoverCell(book: books[i], width: w),
        ),
      ),
    );
  }
}
