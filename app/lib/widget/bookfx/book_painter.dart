// widget/bookfx/book_painter.dart — "模拟翻书" (original `_BookPageState` in book.dart with `BookPainter` / `PrecomputedClipPath` of
// widget/bookfx): the page corner follows the finger. The classic corner-curl look (the Android original's picture): the page
// underneath, the front page clipped to the part still lying flat, the back of the paper (the front page mirrored across the fold
// e-h, washed out towards white), the shadow the lifted paper casts on the page below, the crease shadow on the back and the
// shadow on the front page where it bends up.
//
// Two ways to draw it: from a picture of the front page ([BookCurl.frontImage], one `drawImageRect` per region — what the pager
// uses once it has taken the picture, so a frame of the curl costs almost nothing), or from the live widgets (clip / transform /
// colour-filter the page widget itself) for the first frames before the picture exists.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model/paper_point.dart';

class BookCurl extends StatelessWidget {
  final Widget front;
  final Widget under;

  /// A picture of [front] (device pixels); when given, [front] is not built and the curl is painted from the picture.
  final ui.Image? frontImage;

  /// The touch point (a) and the lifted corner (f) in local coordinates.
  final Offset touch;
  final Offset corner;
  final Color paperColor;

  const BookCurl({
    super.key,
    required this.front,
    required this.under,
    required this.touch,
    required this.corner,
    this.frontImage,
    this.paperColor = const Color(0xFFF2EEE4),
  });

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
      final img = frontImage;
      if ((touch - corner).distance < 1 || size.isEmpty) return img == null ? front : _flat(img, size);
      final p = PaperPoint(touch, corner, size);
      if (img != null) {
        return Stack(fit: StackFit.expand, children: [
          under,
          IgnorePointer(child: CustomPaint(painter: BookCurlPainter(p, img, paperColor), size: size)),
        ]);
      }
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

  Widget _flat(ui.Image img, Size size) => CustomPaint(painter: _FlatPainter(img), size: size);
}

class _PathClip extends CustomClipper<Path> {
  final Path path;
  _PathClip(this.path);

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PathClip old) => true;
}

/// The front page lying flat (no curl yet), from its picture.
class _FlatPainter extends CustomPainter {
  final ui.Image image;
  _FlatPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) => BookCurlPainter.drawPage(canvas, image, size, null);

  @override
  bool shouldRepaint(_FlatPainter old) => old.image != image;
}

/// The whole curl from a picture of the front page.
class BookCurlPainter extends CustomPainter {
  final PaperPoint p;
  final ui.Image image;
  final Color paperColor;
  BookCurlPainter(this.p, this.image, this.paperColor);

  /// Draws [image] over [size] (the picture is the page at the device pixel ratio).
  static void drawPage(Canvas canvas, ui.Image image, Size size, Paint? paint) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      paint ?? (Paint()..filterQuality = FilterQuality.low),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // the part of the front page still lying flat
    canvas.save();
    canvas.clipPath(p.frontPath());
    drawPage(canvas, image, size, null);
    canvas.restore();
    // the back of the lifted paper: the front mirrored across the fold, washed out
    canvas.save();
    canvas.clipPath(p.backPath());
    canvas.transform(Float64List.fromList(p.foldMatrix()));
    canvas.drawRect(Offset.zero & size, Paint()..color = paperColor);
    drawPage(canvas, image, size, Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = BookCurl.backFilter);
    canvas.restore();
    BookShadows.paint(canvas, p);
  }

  @override
  bool shouldRepaint(BookCurlPainter old) => old.p.a != p.a || old.p.f != p.f || old.image != image || old.paperColor != paperColor;
}

/// The shadows of the curl, shared by both ways of drawing it.
abstract class BookShadows {
  static Offset _normalTowards(Offset l1, Offset l2, Offset target) {
    final dx = l2.dx - l1.dx, dy = l2.dy - l1.dy;
    var n = Offset(-dy, dx);
    final len = n.distance;
    if (len == 0) return Offset.zero;
    n = n / len;
    final side = (target - l1).dx * n.dx + (target - l1).dy * n.dy;
    return side < 0 ? -n : n;
  }

  /// A gradient of [colors] starting on the line l1-l2 and running [width] towards the side of [towards], inside [clip].
  static void strip(Canvas canvas, Size size, Path clip, Offset l1, Offset l2, Offset towards, double width, List<Color> colors) {
    final n = _normalTowards(l1, l2, towards);
    if (n == Offset.zero || width <= 0) return;
    final mid = Offset((l1.dx + l2.dx) / 2, (l1.dy + l2.dy) / 2);
    final paint = Paint()..shader = ui.Gradient.linear(mid, mid + n * width, colors);
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawRect(Offset.zero & size, paint);
    canvas.restore();
  }

  static void paint(Canvas canvas, PaperPoint p) {
    final reach = p.reach;
    final size = p.size;
    final front = p.frontPath();
    // the far corner of the page is always on the flat side
    final flat = Offset(0, p.fromBottom ? 0 : size.height);
    // on the page below, from the fold line c-j away from the corner
    strip(canvas, size, p.underPath(), p.c, p.j, Offset(p.c.dx - 1, (p.c.dy + p.j.dy) / 2), math.min(reach / 4, 60),
        const [Color(0x55000000), Color(0x00000000)]);
    // on the back of the paper, darker at the crease d-i, fading towards the touch point
    strip(canvas, size, p.backPath(), p.d, p.i, p.a, math.min(reach / 3, 80), const [Color(0x33000000), Color(0x00000000)]);
    // on the front page where it bends up: along the two folds c-b and k-j, darker at the fold
    final w = math.min(reach / 6, 40.0);
    strip(canvas, size, front, p.c, p.b, flat, w, const [Color(0x40000000), Color(0x00000000)]);
    strip(canvas, size, front, p.k, p.j, flat, w, const [Color(0x40000000), Color(0x00000000)]);
  }
}

/// The shadows alone (the live-widget way of drawing the curl paints the pages itself).
class BookShadowPainter extends CustomPainter {
  final PaperPoint p;
  BookShadowPainter(this.p);

  @override
  void paint(Canvas canvas, Size size) => BookShadows.paint(canvas, p);

  @override
  bool shouldRepaint(BookShadowPainter old) => old.p.a != p.a || old.p.f != p.f;
}
