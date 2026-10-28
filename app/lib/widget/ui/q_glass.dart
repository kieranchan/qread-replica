// widget/ui/q_glass.dart — `QGlassContainer`, the glass surface of the original (bars, menus, cards; ~50 callers) drawn at the
// 沉浸光感 level (`ImmersiveLight.level`, prefs `immersiveLight2223`). Build 0x7246fc:
//   * level 0 (弱) or a container with glass off: a plain Container — light: white, dark: #1E1E1E at 95 % — with a 0.5 px border;
//   * level 1 (均衡): the same container behind a 3×3 BackdropFilter blur (`_kBlur3x3`), clipped to the radius, in a RepaintBoundary;
//   * level 2 (强): a `LiquidGlassLens` (liquid_glass_easy) with the container's radius, transparent tint, light refraction.
// The widget listens to the level, so changing the setting restyles every surface at once.
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../common/immersive_light.dart';

class QGlassContainer extends StatelessWidget {
  final Widget? child;
  final double borderRadius;

  /// Fill colour of the plain / blurred surface (null = the theme's default glass colour).
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;

  /// False draws the plain surface whatever the level (the original's flag at field 0x1f).
  final bool glass;

  /// Overrides the global level (the original's optional `level` field).
  final int? level;

  const QGlassContainer({
    super.key,
    this.child,
    this.borderRadius = 16,
    this.color,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.constraints,
    this.glass = true,
    this.level,
  });

  static final ImageFilter _kBlur3x3 = ImageFilter.blur(sigmaX: 3, sigmaY: 3);

  static Color defaultColor(BuildContext context, {double alpha = 1}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return (dark ? const Color(0xF21E1E1E) : Colors.white).withValues(alpha: alpha * (dark ? 0.95 : 1));
  }

  Widget _plain(BuildContext context, {double alpha = 1}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      width: width,
      height: height,
      constraints: constraints,
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? defaultColor(context, alpha: alpha),
        borderRadius: radius,
        border: Border.all(color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.1), width: 0.5),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ImmersiveLight.level,
      builder: (context, global, _) {
        final lv = level ?? global;
        if (lv == ImmersiveLight.off || !glass) return _plain(context);
        final radius = BorderRadius.circular(borderRadius);
        if (lv == ImmersiveLight.balanced) {
          final inner = Container(
            width: width,
            height: height,
            constraints: constraints,
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? defaultColor(context, alpha: 0.72),
              borderRadius: radius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.5),
            ),
            child: child,
          );
          return Padding(
            padding: margin ?? EdgeInsets.zero,
            child: RepaintBoundary(child: ClipRRect(borderRadius: radius, child: BackdropFilter(filter: _kBlur3x3, child: inner))),
          );
        }
        return Padding(
          key: const Key('q_glass_lens'),
          padding: margin ?? EdgeInsets.zero,
          child: LiquidGlassLens(
            style: LiquidGlassStyle(
              shape: LiquidGlassShape(cornerRadius: borderRadius),
              blur: 3,
              color: color?.withValues(alpha: 0.12) ?? Colors.transparent,
            ),
            child: Container(width: width, height: height, constraints: constraints, padding: padding, child: child),
          ),
        );
      },
    );
  }
}
