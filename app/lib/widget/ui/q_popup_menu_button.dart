// widget/ui/q_popup_menu_button.dart — `QPopupMenuButton` / `QPopupMenuItem`: the app's popup menus. The original draws a glass
// menu (`_GlassMenu`) on iOS with SF Symbol names (`sfSymbol`, e.g. `checkmark` / `circle` for the checked state); the replica
// uses a Material [PopupMenuButton] with the Material icon of each item.
import 'package:flutter/material.dart';

class QPopupMenuItem<T> {
  final T value;
  final String title;
  final IconData? icon;

  /// SF Symbol name of the original (kept for reference; unused on Material).
  final String? sfSymbol;
  final bool destructive;
  final bool enabled;

  const QPopupMenuItem({required this.value, required this.title, this.icon, this.sfSymbol, this.destructive = false, this.enabled = true});

  /// The original's check-list item: `checkmark` when selected, `circle` otherwise.
  factory QPopupMenuItem.check({required T value, required String title, required bool checked}) => QPopupMenuItem<T>(
        value: value,
        title: title,
        icon: checked ? Icons.check : Icons.circle_outlined,
        sfSymbol: checked ? 'checkmark' : 'circle',
      );
}

class QPopupMenuButton<T> extends StatelessWidget {
  final List<QPopupMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final Widget? child;
  final String? tooltip;

  const QPopupMenuButton({super.key, required this.items, required this.onSelected, this.icon = Icons.more_vert, this.child, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: child == null ? Icon(icon) : null,
      onSelected: onSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (context) => [
        for (final it in items)
          PopupMenuItem<T>(
            value: it.value,
            enabled: it.enabled,
            child: Row(children: [
              if (it.icon != null) ...[
                Icon(it.icon, size: 20, color: it.destructive ? scheme.error : null),
                const SizedBox(width: 12),
              ],
              Flexible(child: Text(it.title, style: it.destructive ? TextStyle(color: scheme.error) : null)),
            ]),
          ),
      ],
      child: child,
    );
  }
}
