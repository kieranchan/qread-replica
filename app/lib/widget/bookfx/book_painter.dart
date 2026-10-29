// widget/bookfx/book_painter.dart — "模拟翻书" (original `_BookPageState` in book.dart with `BookPainter` / `PrecomputedClipPath` of
// widget/bookfx): the page corner follows the finger.
//
// Drawing follows Legado's `SimulationPageDelegate` step for step (the owner's reference for this effect is the Android original;
// decompiled from legado 3.26.08011308, class `nn.i`): 1. the current page outside path A (the curled region); 2. the next page inside
// A and the polygon start1-vertex1-vertex2-start2-corner, with the "back shadow" gradient 0xFF111111 -> 0x00111111 along the fold,
// touch-to-corner distance / 4 wide; 3. the "front shadow" 0x80111111 -> 0x00111111, 25 px wide, along the lifted paper's two edges;
// 4. the back of the paper (the page mirrored across control1-control2, its own colours: Legado's colour matrix is the identity)
// with the "folder shadow" 0x00333333 -> 0xB0333333 along the crease. Legado's widths are Android pixels; they are scaled by the
// device pixel ratio here so they measure the same on the phone.
//
// Two ways to draw it: from a picture of the front page ([BookCurl.frontImage], what the pager uses — the picture is taken while the
// pager is idle, so a turn costs no rebuild), or from the live widgets (clip / transform the page widget itself) when no picture is
// ready yet.
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

  /// The back of the paper is the page mirrored in its own colours, as in Legado (identity colour matrix) and the Android original's
  /// pictures; nothing is laid over it.
  static const double backPaperBlend = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final img = frontImage;
      if ((touch - corner).distance < 1 || size.isEmpty) return img == null ? front : _flat(img, size);
      final p = PaperPoint(touch, corner, size);
      final scale = 1 / (MediaQuery.maybeDevicePixelRatioOf(context) ?? 3);
      if (img != null) {
        return Stack(fit: StackFit.expand, children: [
          under,
          IgnorePointer(child: CustomPaint(painter: BookCurlPainter(p, img, paperColor, pixelScale: scale), size: size)),
        ]);
      }
      return Stack(fit: StackFit.expand, children: [
        under,
        ClipPath(clipper: _PathClip(p.frontPath()), child: front),
        ClipPath(
          clipper: _PathClip(p.backPath()),
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: paperColor),
            Transform(transform: Matrix4.fromList(p.foldMatrix()), child: front),
          ]),
        ),
        IgnorePointer(child: CustomPaint(painter: BookShadowPainter(p, pixelScale: scale), size: size)),
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

  /// Logical pixels per Android pixel (1 / device pixel ratio) for Legado's pixel constants.
  final double pixelScale;
  BookCurlPainter(this.p, this.image, this.paperColor, {this.pixelScale = 1 / 3});

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
    // 1. the current page outside the curled region
    canvas.save();
    canvas.clipPath(p.frontPath());
    drawPage(canvas, image, size, null);
    canvas.restore();
    // 2. the page below shows through the widget underneath; its shadow along the fold
    BookShadows.nextPageShadow(canvas, p);
    // 3. the lifted paper's edges
    BookShadows.edgeShadows(canvas, p, pixelScale);
    // 4. the back of the paper: the page mirrored across control1-control2 in its own colours, the crease shadow over it
    canvas.save();
    canvas.clipPath(p.backPath());
    canvas.drawRect(Offset.zero & size, Paint()..color = paperColor);
    canvas.save();
    canvas.transform(Float64List.fromList(p.foldMatrix()));
    drawPage(canvas, image, size, Paint()..filterQuality = FilterQuality.low);
    canvas.restore();
    BookShadows.creaseShadow(canvas, p, pixelScale);
    canvas.restore();
  }

  @override
  bool shouldRepaint(BookCurlPainter old) =>
      old.p.a != p.a || old.p.f != p.f || old.image != image || old.paperColor != paperColor || old.pixelScale != pixelScale;
}

enum _Orient { leftRight, rightLeft, topBottom, bottomTop }

/// Legado's three shadow gradients, drawn its way (a rotated `GradientDrawable` inside clip paths), shared by both ways of
/// drawing the curl.
abstract class BookShadows {
  /// On the back of the paper, along the crease (`mFolderShadowColors`).
  static const List<Color> folderShadow = [Color(0x00333333), Color(0xB0333333)];

  /// On the page below, along the fold (`mBackShadowColors`).
  static const List<Color> backShadow = [Color(0xFF111111), Color(0x00111111)];

  /// Along the lifted paper's two edges (`mFrontShadowColors`).
  static const List<Color> frontShadow = [Color(0x80111111), Color(0x00111111)];

  /// Legado's pixel constants (Android px): width of the edge shadows, and how far from the touch their clip triangles start.
  static const double edgeShadowPx = 25;
  static const double edgeOffsetPx = 35.35;

  /// `mIsRtOrLb`: the lifted corner is the right-top or the left-bottom one.
  static bool rtOrLb(PaperPoint p) => (p.f.dx == 0 && p.f.dy == p.size.height) || (p.f.dy == 0 && p.f.dx == p.size.width);

  /// `mDegrees`: the fold's angle, used to rotate the gradients about start1.
  static double degrees(PaperPoint p) => math.atan2(p.e.dx - p.f.dx, p.h.dy - p.f.dy) * 180 / math.pi;

  /// `mMaxLength`.
  static double maxLength(Size s) => math.sqrt(s.width * s.width + s.height * s.height);

  /// Legado's path A: the curled region (start1 -curve- end1, touch, end2 -curve- start2, corner).
  static Path pathA(PaperPoint p) => Path()
    ..moveTo(p.c.dx, p.c.dy)
    ..quadraticBezierTo(p.e.dx, p.e.dy, p.b.dx, p.b.dy)
    ..lineTo(p.a.dx, p.a.dy)
    ..lineTo(p.k.dx, p.k.dy)
    ..quadraticBezierTo(p.h.dx, p.h.dy, p.j.dx, p.j.dy)
    ..lineTo(p.f.dx, p.f.dy)
    ..close();

  /// `clipOutPath`: everything of [size] outside [path].
  static Path outside(Path path, Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addPath(path, Offset.zero);

  static void _rotateAbout(Canvas canvas, double deg, Offset pivot) {
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
  }

  /// A `GradientDrawable` of [colors] with [orient] filling [r] (colors[0] at the edge the orientation starts from).
  static void _gradient(Canvas canvas, Rect r, List<Color> colors, _Orient orient) {
    if (r.isEmpty) return;
    final (Offset from, Offset to) = switch (orient) {
      _Orient.leftRight => (r.centerLeft, r.centerRight),
      _Orient.rightLeft => (r.centerRight, r.centerLeft),
      _Orient.topBottom => (r.topCenter, r.bottomCenter),
      _Orient.bottomTop => (r.bottomCenter, r.topCenter),
    };
    canvas.drawRect(r, Paint()..shader = ui.Gradient.linear(from, to, colors));
  }

  /// Step 2 of `drawNextPageAreaAndShadow`: inside A and start1-vertex1-vertex2-start2-corner, the back shadow from the fold
  /// towards the corner, touch-to-corner distance / 4 wide.
  static void nextPageShadow(Canvas canvas, PaperPoint p) {
    final region = Path()
      ..moveTo(p.c.dx, p.c.dy)
      ..lineTo(p.d.dx, p.d.dy)
      ..lineTo(p.i.dx, p.i.dy)
      ..lineTo(p.j.dx, p.j.dy)
      ..lineTo(p.f.dx, p.f.dy)
      ..close();
    final w = p.reach / 4;
    final ml = maxLength(p.size);
    canvas.save();
    canvas.clipPath(pathA(p));
    canvas.clipPath(region);
    _rotateAbout(canvas, degrees(p), p.c);
    if (rtOrLb(p)) {
      _gradient(canvas, Rect.fromLTRB(p.c.dx, p.c.dy, p.c.dx + w, p.c.dy + ml), backShadow, _Orient.leftRight);
    } else {
      _gradient(canvas, Rect.fromLTRB(p.c.dx - w, p.c.dy, p.c.dx, p.c.dy + ml), backShadow, _Orient.rightLeft);
    }
    canvas.restore();
  }

  /// `drawCurrentPageShadow`: the two edge shadows of the lifted paper, outside A, 25 px wide.
  static void edgeShadows(Canvas canvas, PaperPoint p, double pixelScale) {
    final rt = rtOrLb(p);
    final a = p.a, e = p.e, h = p.h, c = p.c, j = p.j;
    final size = p.size;
    final ml = maxLength(size);
    final w = edgeShadowPx * pixelScale, one = pixelScale;
    final ang = math.pi / 4 - (rt ? math.atan2(e.dy - a.dy, a.dx - e.dx) : math.atan2(a.dy - e.dy, a.dx - e.dx));
    final off = edgeOffsetPx * pixelScale;
    final p1 = Offset(a.dx + math.cos(ang) * off, rt ? a.dy + math.sin(ang) * off : a.dy - math.sin(ang) * off);
    final notA = outside(pathA(p), size);
    // along touch - control1 (the edge that meets the corner's horizontal side)
    var tri = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(e.dx, e.dy)
      ..lineTo(c.dx, c.dy)
      ..close();
    canvas.save();
    canvas.clipPath(notA);
    canvas.clipPath(tri);
    _rotateAbout(canvas, math.atan2(a.dx - e.dx, e.dy - a.dy) * 180 / math.pi, e);
    if (rt) {
      _gradient(canvas, Rect.fromLTRB(e.dx, e.dy - ml, e.dx + w, e.dy), frontShadow, _Orient.leftRight);
    } else {
      _gradient(canvas, Rect.fromLTRB(e.dx - w, e.dy - ml, e.dx + one, e.dy), frontShadow, _Orient.rightLeft);
    }
    canvas.restore();
    // along touch - control2 (the edge that meets the corner's vertical side)
    tri = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(h.dx, h.dy)
      ..lineTo(j.dx, j.dy)
      ..close();
    canvas.save();
    canvas.clipPath(notA);
    canvas.clipPath(tri);
    _rotateAbout(canvas, math.atan2(h.dy - a.dy, h.dx - a.dx) * 180 / math.pi, h);
    final hy = h.dy < 0 ? h.dy - size.height : h.dy;
    final hyp = math.sqrt(h.dx * h.dx + hy * hy);
    final top = rt ? h.dy : h.dy - w, bottom = rt ? h.dy + w : h.dy + one;
    final r = hyp > ml ? Rect.fromLTRB(h.dx - w - hyp, top, h.dx + ml - hyp, bottom) : Rect.fromLTRB(h.dx - ml, top, h.dx, bottom);
    _gradient(canvas, r, frontShadow, rt ? _Orient.topBottom : _Orient.bottomTop);
    canvas.restore();
  }

  /// The gradient of `drawCurrentBackArea`: the folder shadow along the crease, drawn by the caller inside the back area's clip.
  static void creaseShadow(Canvas canvas, PaperPoint p, double pixelScale) {
    final f1 = (((p.c.dx + p.e.dx) / 2).truncateToDouble() - p.e.dx).abs();
    final f2 = (((p.j.dy + p.h.dy) / 2).truncateToDouble() - p.h.dy).abs();
    final f3 = math.min(f1, f2);
    final one = pixelScale;
    final ml = maxLength(p.size);
    canvas.save();
    _rotateAbout(canvas, degrees(p), p.c);
    if (rtOrLb(p)) {
      _gradient(canvas, Rect.fromLTRB(p.c.dx - one, p.c.dy, p.c.dx + f3 + one, p.c.dy + ml), folderShadow, _Orient.leftRight);
    } else {
      _gradient(canvas, Rect.fromLTRB(p.c.dx - f3 - one, p.c.dy, p.c.dx + one, p.c.dy + ml), folderShadow, _Orient.rightLeft);
    }
    canvas.restore();
  }

  /// All shadows for the live-widget way of drawing (the pages themselves are widgets).
  static void paint(Canvas canvas, PaperPoint p, double pixelScale) {
    if (p.reach < 1) return;
    nextPageShadow(canvas, p);
    edgeShadows(canvas, p, pixelScale);
    canvas.save();
    canvas.clipPath(p.backPath());
    creaseShadow(canvas, p, pixelScale);
    canvas.restore();
  }
}

/// The shadows alone (the live-widget way of drawing the curl paints the pages itself).
class BookShadowPainter extends CustomPainter {
  final PaperPoint p;
  final double pixelScale;
  BookShadowPainter(this.p, {this.pixelScale = 1 / 3});

  @override
  void paint(Canvas canvas, Size size) => BookShadows.paint(canvas, p, pixelScale);

  @override
  bool shouldRepaint(BookShadowPainter old) => old.p.a != p.a || old.p.f != p.f || old.pixelScale != pixelScale;
}
