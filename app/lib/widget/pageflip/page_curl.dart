// widget/pageflip/page_curl.dart — the "仿真翻页" effect: the page's right edge folds over towards the left, showing the back of the
// paper and a shadow on the page below.
//
// Original: `widget/pageflip/effects/*` (a shader-free curl with a `PrecomputedClipPath`) and `widget/bookfx/*` (`BookPainter` for
// "模拟翻书"). This port models the fold as a vertical line: with turn amount `a` (0 = flat, 1 = gone) the page edge sits at
// `W - 2Wa`, the fold line at `W(1 - a)`; the front is visible left of the edge, the paper back between edge and fold line, the next
// page right of the fold line. TODO(asm widget/pageflip/effects): the original's diagonal corner curl and lighting.
import 'dart:math' as math;

import 'package:flutter/material.dart';

class PageCurl extends StatelessWidget {
  /// The page being turned.
  final Widget front;

  /// The page that is revealed.
  final Widget under;

  /// 0..1.
  final double amount;

  /// Colour of the paper back.
  final Color paperColor;

  const PageCurl({super.key, required this.front, required this.under, required this.amount, this.paperColor = const Color(0xFFF2EEE4)});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final a = amount.clamp(0.0, 1.0);
      final fold = w * (1 - a);
      final edge = math.max(0.0, w - 2 * w * a);
      return Stack(
        fit: StackFit.expand,
        children: [
          under,
          ClipRect(clipper: _LeftClip(edge), child: front),
          if (fold > edge)
            Positioned(
              left: edge,
              top: 0,
              bottom: 0,
              width: fold - edge,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(paperColor, Colors.black, 0.18)!,
                        paperColor,
                        Color.lerp(paperColor, Colors.white, 0.25)!,
                      ],
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                ),
              ),
            ),
          if (a > 0 && a < 1)
            Positioned(
              left: fold,
              top: 0,
              bottom: 0,
              width: math.min(24, w - fold),
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x55000000), Color(0x00000000)])),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _LeftClip extends CustomClipper<Rect> {
  final double right;
  const _LeftClip(this.right);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, right, size.height);

  @override
  bool shouldReclip(_LeftClip old) => old.right != right;
}
