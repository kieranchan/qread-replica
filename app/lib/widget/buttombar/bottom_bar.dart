// widget/buttombar/bottom_bar.dart — `BottomBar` / `BottomBarItem`: the floating tab bar of the main page (non-iOS path; iOS
// uses the native CNTabBar). Rounded bar with 20 px margins (`#141317` in dark mode), the selected item grows with an animated
// pill (AnimationController, 200 ms / 80 ms durations in the original); `hide` slides it out (scrolling hides the bar when
// `bottomBarHideMode` asks for it).
import 'package:flutter/material.dart';

class BottomBarItem {
  final IconData icon;
  final IconData? activeIcon;
  final String title;

  /// SF Symbol names of the original (`book` / `book.fill`, `magnifyingglass.circle`, `safari`, `bookmark`, `person`).
  final String? sfSymbol;

  const BottomBarItem({required this.icon, this.activeIcon, required this.title, this.sfSymbol});
}

class BottomBar extends StatefulWidget {
  final List<BottomBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool hide;

  /// Show titles of unselected items too.
  final bool showUnselectedTitle;

  const BottomBar({super.key, required this.items, required this.currentIndex, required this.onTap, this.hide = false, this.showUnselectedTitle = true});

  @override
  State<BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<BottomBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), value: widget.hide ? 0 : 1);
  late final Animation<double> _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void didUpdateWidget(covariant BottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hide != widget.hide) widget.hide ? _controller.reverse() : _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizeTransition(
      sizeFactor: _animation,
      axisAlignment: -1,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF141317) : scheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            for (var i = 0; i < widget.items.length; i++)
              Expanded(
                child: InkWell(
                  key: Key('tab_${widget.items[i].title}'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => widget.onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: i == widget.currentIndex ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(i == widget.currentIndex ? (widget.items[i].activeIcon ?? widget.items[i].icon) : widget.items[i].icon,
                          color: i == widget.currentIndex ? scheme.primary : scheme.onSurfaceVariant),
                      if (widget.showUnselectedTitle || i == widget.currentIndex) ...[
                        const SizedBox(height: 4),
                        Text(widget.items[i].title,
                            style: TextStyle(fontSize: 11, color: i == widget.currentIndex ? scheme.primary : scheme.onSurfaceVariant)),
                      ],
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
