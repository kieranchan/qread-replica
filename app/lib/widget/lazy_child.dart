// widget/lazy_child.dart — `LazyChild`: builds an expensive child only after the first frame (tab pages of the IndexedStack,
// exploration components), showing [placeholder] until then.
import 'package:flutter/material.dart';

class LazyChild extends StatefulWidget {
  final WidgetBuilder builder;
  final Widget placeholder;

  /// Build immediately (no deferral), e.g. for the visible tab.
  final bool eager;

  const LazyChild({super.key, required this.builder, this.placeholder = const SizedBox.shrink(), this.eager = false});

  @override
  State<LazyChild> createState() => _LazyChildState();
}

class _LazyChildState extends State<LazyChild> {
  late bool _ready = widget.eager;

  @override
  void initState() {
    super.initState();
    if (!_ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) => _ready ? widget.builder(context) : widget.placeholder;
}
