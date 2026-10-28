// widget/bookfx/book_painter.dart — "模拟翻书" (original `_BookPageState` in book.dart with `BookPainter` / `PrecomputedClipPath` of
// widget/bookfx): the page corner follows the finger. Drawn with widgets so the pages stay live: the page underneath, the front page
// clipped to the part still lying flat, the back of the paper (the front page mirrored across the fold e-h, washed out towards the
// paper colour), and the shadows along the fold on the page below and inside the fold on the back.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model/paper_point.dart';

class BookCurl extends StatelessWidget {
  final Widget front;
  final Widget under;

  /// The touch point (a) and the lifted corner (f) in local coordinates.
  final Offset touch;
  final Offset corner;
  final Color paperColor;

  const BookCurl({super.key, required this.front, required this.under, required this.touch, required this.corner, this.paperColor = const Color(0xFFF2EEE4)});

  /// The back of the paper: the page mirrored and blended towards white (55 % of the colour + 80/255, like the classic algorithm).
  static const ColorFilter backFilter = ColorFilter.matrix(<double>[
    0.55, 0, 0, 0, 80, //
    0, 0.55, 0, 0, 80, //
    0, 0, 0.55, 0, 80, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      if ((touch - corner).distance < 1 || size.isEmpty) return front;
      final p = PaperPoint(touch, corner, size);
      return Stack(fit: StackFit.expand, children: [
        under,
        ClipPath(clipper: _PathClip(p.frontPath()), child: front),
        ClipPath(
          clipper: _PathClip(p.backPath()),
          child: Transform(
            transform: Matrix4.fromList(p.foldMatrix()),
            child: ColorFiltered(colorFilter: backFilter, child: front),
          ),
        ),
        IgnorePointer(child: CustomPaint(painter: BookShadowPainter(p), size: size)),
      ]);
    });
  }
}

class _PathClip extends CustomClipper<Path> {
  final Path path;
  _PathClip(this.path);

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClip old) => true;
}

/// The fold shadows: on the page below next to the fold (width = a-f distance / 4) and on the back of the paper at the crease.
class BookShadowPainter extends CustomPainter {
  final PaperPoint p;
  BookShadowPainter(this.p);

  static Offset _normalTowards(Offset l1, Offset l2, Offset target) {
    final dx = l2.dx - l1.dx, dy = l2.dy - l1.dy;
    var n = Offset(-dy, dx);
    final len = n.distance;
    if (len == 0) return Offset.zero;
    n = n / len;
    final side = (target - l1).dx * n.dx + (target - l1).dy * n.dy;
    return side < 0 ? -n : n;
  }

  void _strip(Canvas canvas, Path clip, Offset l1, Offset l2, Offset towards, double width, List<Color> colors) {
    final n = _normalTowards(l1, l2, towards);
    if (n == Offset.zero || width <= 0) return;
    final mid = Offset((l1.dx + l2.dx) / 2, (l1.dy + l2.dy) / 2);
    final paint = Paint()..shader = ui.Gradient.linear(mid, mid + n * width, colors);
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawRect(Offset.zero & p.size, paint);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final reach = p.reach;
    // on the page below, from the fold line c-j away from the corner
    _strip(canvas, p.underPath(), p.c, p.j, Offset(p.c.dx - 1, (p.c.dy + p.j.dy) / 2), math.min(reach / 4, 60),
        const [Color(0x55000000), Color(0x00000000)]);
    // on the back of the paper, darker at the crease d-i, fading towards the touch point
    _strip(canvas, p.backPath(), p.d, p.i, p.a, math.min(reach / 3, 80), const [Color(0x33000000), Color(0x00000000)]);
  }

  @override
  bool shouldRepaint(BookShadowPainter old) => old.p.a != p.a || old.p.f != p.f;
}
