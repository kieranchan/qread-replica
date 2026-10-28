// widget/ui/glass_card.dart — `GlassFAB` and a frosted card used by the shelf / discovery sheets; both are `QGlassContainer`
// surfaces (q_glass.dart), so they follow the 沉浸光感 level.
import 'package:flutter/material.dart';

import 'q_glass.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.borderRadius = const BorderRadius.all(Radius.circular(16))});

  @override
  Widget build(BuildContext context) => QGlassContainer(padding: padding, borderRadius: borderRadius.topLeft.x, child: child);
}

/// Floating action button on a glass background.
class GlassFAB extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  const GlassFAB({super.key, required this.icon, this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: QGlassContainer(
        borderRadius: 28,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(customBorder: const CircleBorder(), onTap: onPressed, child: SizedBox(width: 56, height: 56, child: Icon(icon))),
        ),
      ),
    );
  }
}
