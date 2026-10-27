// widget/ui/glass_card.dart — `GlassFAB` and a frosted card used by the shelf / discovery sheets ("沉浸光感" glass look of the
// original, reduced to a translucent blurred surface).
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;

  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.borderRadius = const BorderRadius.all(Radius.circular(16)), this.blur = 12});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            borderRadius: borderRadius,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: child,
        ),
      ),
    );
  }
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
      child: GlassCard(
        padding: EdgeInsets.zero,
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        child: InkWell(onTap: onPressed, child: SizedBox(width: 56, height: 56, child: Icon(icon))),
      ),
    );
  }
}
