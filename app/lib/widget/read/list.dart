// widget/read/list.dart — `ReadListPage`: the scrolling list of page bodies used by the scroll-mode reader.
// Original: `ReadListPage` / `_ReadListPageState` (with AutomaticKeepAliveClientMixin), `InfiniteScrollController` and
// `_InfiniteScrollPosition` ("不能jump", "奇怪了没移动对next"). Items have a fixed extent (one page body), so prepending keeps the position
// (see `ReadListController.prepend`).
import 'package:flutter/material.dart';

import '../../read/util/list_content.dart';
import '../../read/util/listcontroller.dart';

class ReadListPage extends StatefulWidget {
  final ReadListController controller;
  final Widget Function(ListContent item) itemBuilder;
  final void Function(ListContent top)? onTopChanged;

  /// Called when the list nears its end (1) or its start (-1).
  final void Function(int direction)? onEdge;

  const ReadListPage({super.key, required this.controller, required this.itemBuilder, this.onTopChanged, this.onEdge});

  @override
  State<ReadListPage> createState() => _ReadListPageState();
}

class _ReadListPageState extends State<ReadListPage> with AutomaticKeepAliveClientMixin {
  int _lastTop = -1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.scroll.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(ReadListPage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      old.controller.scroll.removeListener(_scrolled);
      widget.controller.addListener(_changed);
      widget.controller.scroll.addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.scroll.removeListener(_scrolled);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _scrolled() {
    final c = widget.controller;
    if (c.items.isEmpty) return;
    final i = c.topIndex;
    if (i != _lastTop) {
      _lastTop = i;
      widget.onTopChanged?.call(c.items[i]);
    }
    if (i >= c.items.length - 2) widget.onEdge?.call(1);
    if (i <= 1) widget.onEdge?.call(-1);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(builder: (context, box) {
      final c = widget.controller;
      c.itemExtent = box.maxHeight <= 0 ? 1 : box.maxHeight;
      return ListView.builder(
        controller: c.scroll,
        itemExtent: c.itemExtent,
        itemCount: c.items.length,
        padding: EdgeInsets.zero,
        itemBuilder: (context, i) => ClipRect(
          child: Align(alignment: Alignment.topLeft, child: widget.itemBuilder(c.items[i])),
        ),
      );
    });
  }
}
