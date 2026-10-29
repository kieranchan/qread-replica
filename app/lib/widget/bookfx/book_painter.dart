// widget/bookfx/book_painter.dart — "模拟翻书" (original `_BookPageState` in book.dart with `BookPainter` / `PrecomputedClipPath` of
// widget/bookfx): the page corner follows the finger. The classic corner-curl look (the Android original's picture): the page
// underneath, the front page clipped to the part still lying flat, the back of the paper (the front page mirrored across the fold
// e-h, washed out towards white), the shadow the lifted paper casts on the page below, the crease shadow on the back and the
// shadow on the front page where it bends up.
//
// Two ways to draw it: from a picture of the front page ([BookCurl.frontImage], one `drawImageRect` per region — what the pager
// uses once it has taken the picture, so a frame of the curl costs almost nothing), or from the live widgets (clip / transform /
// colour-filter the page widget itself) for the first frames before the picture exists.
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

  /// The back of the paper is the page mirrored in its own colours (the paper stays the paper, as in the Android original — not the
  /// classic algorithm's blend towards white), with this much of the paper colour laid over it so that the mirrored text shows a
  /// little lighter than on the front.
  static const double backPaperBlend = 0.25;

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
          child: Stack(fit: StackFit.expand, children: [
            Transform(transform: Matrix4.fromList(p.foldMatrix()), child: front),
            ColoredBox(color: paperColor.withValues(alpha: backPaperBlend)),
          ]),
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

  /// Draws [image] over [size] (the picture is the page at the device pixel ratio, so unmirrored it lands pixel for pixel on the
  /// screen: nearest sampling keeps it identical to the live page — bilinear made the text go a touch soft the moment the picture
  /// replaced the live widgets, a flicker at the start and the end of every turn).
  static void drawPage(Canvas canvas, ui.Image image, Size size, Paint? paint) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      paint ?? (Paint()..filterQuality = FilterQuality.none),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // the part of the front page still lying flat
    canvas.save();
    canvas.clipPath(p.frontPath());
    drawPage(canvas, image, size, null);
    canvas.restore();
    // the back of the lifted paper: the front mirrored across the fold in its own colours, a little paper colour over it
    canvas.save();
    canvas.clipPath(p.backPath());
    canvas.drawRect(Offset.zero & size, Paint()..color = paperColor);
    canvas.save();
    canvas.transform(Float64List.fromList(p.foldMatrix()));
    drawPage(canvas, image, size, Paint()..filterQuality = FilterQuality.low);
    canvas.restore();
    canvas.drawRect(Offset.zero & size, Paint()..color = paperColor.withValues(alpha: BookCurl.backPaperBlend));
    canvas.restore();
    BookShadows.paint(canvas, p);
  }

  @override
  bool shouldRepaint(BookCurlPainter old) => old.p.a != p.a || old.p.f != p.f || old.image != image || old.paperColor != paperColor;
}

/// The shadows of the curl, shared by both ways of drawing it.
///
/// 2026-10-30 (owner: the black shadows were unbearable, and turning back flashed): the old strips were linear gradients painted over
/// the whole clip region — a clamped gradient keeps its first colour on the far side of its start line, so the "shadow on the page
/// below" laid a flat 33% black over the entire next page until the turn ended (the dark look, and the sudden darkening at the start
/// of a backward turn / brightening at the end of a forward one). Now: the lifted paper casts a soft blurred shadow on the page
/// below, hugging its edge; the crease and the bend are narrow warm bands that end where they should.
abstract class BookShadows {
  /// Shadow ink: a warm dark, never pure black.
  static const Color ink = Color(0xFF2E2620);

  /// Strength of the paper's shadow on the page below (alpha 0..1) and of the crease / bend bands.
  static double underAlpha = 0.26;
  static double creaseAlpha = 0.16;
  static double bendAlpha = 0.12;

  static Offset _normalTowards(Offset l1, Offset l2, Offset target) {
    final dx = l2.dx - l1.dx, dy = l2.dy - l1.dy;
    var n = Offset(-dy, dx);
    final len = n.distance;
    if (len == 0) return Offset.zero;
    n = n / len;
    final side = (target - l1).dx * n.dx + (target - l1).dy * n.dy;
    return side < 0 ? -n : n;
  }

  /// The band of [width] along the line l1-l2 (extended far past both ends) on the side of [n].
  static Path _band(Offset l1, Offset l2, Offset n, double width, double extent) {
    final d = l2 - l1;
    final len = d.distance;
    if (len == 0) return Path();
    final u = d / len;
    final p1 = l1 - u * extent, p2 = l2 + u * extent;
    return Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p2.dx + n.dx * width, p2.dy + n.dy * width)
      ..lineTo(p1.dx + n.dx * width, p1.dy + n.dy * width)
      ..close();
  }

  /// A gradient of [colors] starting on the line l1-l2 and running [width] towards the side of [towards], inside [clip] — and only
  /// inside its own band, nothing beyond it.
  static void strip(Canvas canvas, Size size, Path clip, Offset l1, Offset l2, Offset towards, double width, List<Color> colors) {
    final n = _normalTowards(l1, l2, towards);
    if (n == Offset.zero || width <= 0) return;
    final mid = Offset((l1.dx + l2.dx) / 2, (l1.dy + l2.dy) / 2);
    final paint = Paint()..shader = ui.Gradient.linear(mid, mid + n * width, colors);
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawPath(_band(l1, l2, n, width, size.longestSide * 2), paint);
    canvas.restore();
  }

  /// Blur radius of the paper's shadow on the page below for a curl of [reach].
  static double shadowSigma(double reach) => (reach / 12).clamp(2.0, 10.0);

  static void paint(Canvas canvas, PaperPoint p) {
    final reach = p.reach;
    if (reach < 1) return;
    final size = p.size;
    final front = p.frontPath();
    final back = p.backPath();
    final under = p.underPath();
    // 1. the lifted paper's shadow on the page below: the silhouette of everything that is not the page below (the flat page and
    //    the back of the paper), blurred and nudged a little towards the corner, drawn only where the page below shows — a soft
    //    contact shadow along the whole paper edge, the curved folds and the lifted tip alike
    final sigma = shadowSigma(reach);
    // only the part inside the page: the geometry's polygons run far outside it, and a blurred shape beyond the top or left edge
    // would bleed a shadow in along that edge (the whole first frame of a backward turn was tinted that way)
    final lifted = Path.combine(PathOperation.intersect, Path.combine(PathOperation.union, front, back), Path()..addRect(Offset.zero & size));
    final dir = p.f - p.a;
    final u = dir / dir.distance;
    canvas.save();
    canvas.clipPath(under);
    canvas.translate(u.dx * sigma * 0.5, u.dy * sigma * 0.5);
    canvas.drawPath(
      lifted,
      Paint()
        ..color = ink.withValues(alpha: underAlpha)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma),
    );
    canvas.restore();
    // 2. on the back of the paper: darker at the crease d-i, fading towards the touch point
    strip(canvas, size, back, p.d, p.i, p.a, (reach / 4).clamp(6.0, 48.0), [ink.withValues(alpha: creaseAlpha), ink.withValues(alpha: 0)]);
    // 3. on the front page where it bends up: along the two folds c-b and k-j, on the flat side (the far corner is always there)
    final flat = Offset(0, p.fromBottom ? 0 : size.height);
    final w = (reach / 8).clamp(4.0, 24.0);
    strip(canvas, size, front, p.c, p.b, flat, w, [ink.withValues(alpha: bendAlpha), ink.withValues(alpha: 0)]);
    strip(canvas, size, front, p.k, p.j, flat, w, [ink.withValues(alpha: bendAlpha), ink.withValues(alpha: 0)]);
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
