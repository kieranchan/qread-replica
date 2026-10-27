// widget/circular_icon_button.dart — round icon buttons of the app bars (`CircularIconButton`, `CircularLoadingButton`).
import 'package:flutter/material.dart';

class CircularIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final Color? backgroundColor;

  const CircularIconButton({super.key, required this.icon, this.onPressed, this.tooltip, this.size = 36, this.color, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final btn = Material(
      color: backgroundColor ?? scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.55, color: color ?? scheme.onSurface)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: tooltip == null ? btn : Tooltip(message: tooltip!, child: btn),
    );
  }
}

/// A [CircularIconButton] that shows a spinner while [loading].
class CircularLoadingButton extends StatelessWidget {
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  const CircularLoadingButton({super.key, required this.icon, required this.loading, this.onPressed, this.tooltip, this.size = 36});

  @override
  Widget build(BuildContext context) {
    if (!loading) return CircularIconButton(icon: icon, onPressed: onPressed, tooltip: tooltip, size: size);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: size,
        height: size,
        child: Padding(padding: EdgeInsets.all(size * 0.25), child: const CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
