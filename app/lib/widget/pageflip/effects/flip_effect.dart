// widget/pageflip/effects/flip_effect.dart — `PageFlipEffect` (class 4394, a CustomPainter with the amount, the page picture and the
// paper colour): the "仿真翻页" curl of the original (`_FlipPageState`, filp.dart). Paint routine 0x4e51fc, constants read there:
// movX = (1 - amount) * 0.85; radius 0.18, scaled by movX * 5 while movX < 0.2; the page casts a black54 outer blur of
// sigma(8 + 32 * (1 - shadowXf)); each pixel column x of the picture is drawn 1 px wide at (xf * (1 - r) - movX) * w and stretched
// vertically by r * sin(2π * (xf - (1 - amount))) + r * 1.1 — a cylinder rolling from the right edge to the left.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class PageFlipEffect extends CustomPainter {
  /// 1 = the page lies flat, 0 = it is turned away.
  final double amount;
  final ui.Image image;
  final Color? backgroundColor;
  final double radius;

  const PageFlipEffect({required this.amount, required this.image, this.backgroundColor, this.radius = 0.18});

  /// Horizontal offset of the rolled page (fraction of the width).
  static double movX(double amount) => (1.0 - amount) * 0.85;

  /// Radius of the roll for [amount] (0x4e5260: scaled down near the start).
  static double rollRadius(double amount, [double radius = 0.18]) {
    final m = movX(amount);
    return m < 0.20 ? radius * m * 5 : radius;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pos = amount.clamp(0.0, 1.0);
    final mx = movX(pos);
    final calcR = rollRadius(pos, radius);
    final wHRatio = 1 - calcR;
    final hWRatio = image.height / image.width;
    final hWCorrection = (hWRatio - 1.0) / 2.0;
    final w = size.width;
    final h = size.height;
    final shadowXf = wHRatio - mx;
    final shadowSigma = Shadow.convertRadiusToSigma(8.0 + 32.0 * (1.0 - shadowXf));
    final pageRect = Rect.fromLTRB(0.0, 0.0, w * shadowXf, h);
    final bg = backgroundColor;
    if (bg != null) canvas.drawRect(pageRect, Paint()..color = bg);
    if (pos != 0) {
      canvas.drawRect(
        pageRect,
        Paint()
          ..color = Colors.black54
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, shadowSigma),
      );
    }
    final ip = Paint()..filterQuality = FilterQuality.low;
    for (double x = 0; x < w; x++) {
      final xf = x / w;
      final v = calcR * math.sin(math.pi / 0.5 * (xf - (1.0 - pos))) + calcR * 1.1;
      final xv = xf * wHRatio - mx;
      final sx = xf * image.width;
      final sr = Rect.fromLTRB(sx, 0.0, sx + 1.0, image.height.toDouble());
      final yv = (h * calcR * mx) * hWRatio - hWCorrection;
      final ds = yv * v;
      final dr = Rect.fromLTRB(xv * w, 0.0 - ds, xv * w + 1.0, h + ds);
      canvas.drawImageRect(image, sr, dr, ip);
    }
  }

  @override
  bool shouldRepaint(PageFlipEffect old) => old.image != image || old.amount != amount || old.backgroundColor != backgroundColor;
}
