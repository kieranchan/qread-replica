// widget/bookfx/model/paper_point.dart — `PaperPoint` (class 1160): the geometry of the "模拟翻书" corner curl (constructor 0x10630ac,
// "Error initializing PaperPoint: "). a = the touch point, f = the page corner being lifted:
//   g = midpoint(a, f); e / h = where the perpendicular bisector of a-f meets the corner's edges;
//   c / j = e / h moved half their distance from f further out; b = cross(a-e, c-j), k = cross(a-h, c-j);
//   d = (c + 2e + b) / 4 and i = (j + 2h + k) / 4 (the midpoints of the two Bézier folds); e.x / d.x are clamped to >= 0.
// The front page is what lies outside c-b-a-k-j, the back of the paper the polygon d-b-a-k-i, the next page the rest.
import 'dart:math' as math;
import 'dart:ui';

class PaperPoint {
  final Offset a;
  final Offset f;
  final Size size;
  late final Offset g, e, h, c, j, b, k, d, i;

  /// Slope / intercept of the line a-h (the original keeps them for hit tests).
  late final double ahSlope, ahIntercept;

  PaperPoint(Offset touch, this.f, this.size) : a = _safe(touch, f) {
    g = Offset((a.dx + f.dx) / 2, (a.dy + f.dy) / 2);
    var ex = g.dx - (f.dy - g.dy) * (f.dy - g.dy) / (f.dx - g.dx);
    e = Offset(ex, f.dy);
    h = Offset(f.dx, g.dy - (f.dx - g.dx) * (f.dx - g.dx) / (f.dy - g.dy));
    c = Offset(e.dx - (f.dx - e.dx) / 2, f.dy);
    j = Offset(f.dx, h.dy - (f.dy - h.dy) / 2);
    b = cross(a, e, c, j);
    k = cross(a, h, c, j);
    d = Offset((c.dx + 2 * e.dx + b.dx) / 4, (2 * e.dy + c.dy + b.dy) / 4);
    i = Offset((j.dx + 2 * h.dx + k.dx) / 4, (2 * h.dy + j.dy + k.dy) / 4);
    ahSlope = (h.dy - a.dy) / (h.dx - a.dx);
    ahIntercept = a.dy - ahSlope * a.dx;
  }

  /// The touch must not sit on the corner's edges (divisions by zero), and not nearly on them either: a finger dragged straight
  /// along the bottom edge (every 左右 turn) made `h` / `j` / `k` land millions of pixels away and the first frames of a turn painted
  /// garbage (the flash at the start of a backward turn). The fold is kept at least ~1° off the edge, which the eye cannot tell.
  static Offset _safe(Offset a, Offset f) {
    var x = a.dx, y = a.dy;
    final eps = math.max(0.5, (a - f).distance * 0.01);
    if ((f.dx - x).abs() < eps) x = f.dx - eps;
    if ((f.dy - y).abs() < eps) y = f.dy + (f.dy == 0 ? eps : -eps);
    return Offset(x, y);
  }

  /// Intersection of the lines p1-p2 and p3-p4.
  static Offset cross(Offset p1, Offset p2, Offset p3, Offset p4) {
    final den = (p1.dx - p2.dx) * (p3.dy - p4.dy) - (p1.dy - p2.dy) * (p3.dx - p4.dx);
    if (den == 0) return p2;
    final t1 = p1.dx * p2.dy - p1.dy * p2.dx;
    final t2 = p3.dx * p4.dy - p3.dy * p4.dx;
    return Offset((t1 * (p3.dx - p4.dx) - (p1.dx - p2.dx) * t2) / den, (t1 * (p3.dy - p4.dy) - (p1.dy - p2.dy) * t2) / den);
  }

  /// While dragging, the fold must stay on the page: when c leaves the left edge the touch is pulled back along a-f so that c lands
  /// on x = 0 (the classic correction of this algorithm).
  static Offset constrain(Offset touch, Offset f, Size size) {
    final p = PaperPoint(touch, f, size);
    if (p.c.dx >= 0) return p.a;
    final w0 = size.width - p.c.dx;
    final w1 = (f.dx - p.a.dx).abs();
    final w2 = size.width * w1 / w0;
    final x = (f.dx - w2).abs();
    final h1 = (f.dy - p.a.dy).abs();
    final h2 = w2 * h1 / w1;
    final y = (f.dy - h2).abs();
    return Offset(x, y);
  }

  /// Distance from the touch to the corner.
  double get reach => math.sqrt((f.dx - a.dx) * (f.dx - a.dx) + (f.dy - a.dy) * (f.dy - a.dy));

  bool get fromBottom => f.dy > 0;

  // the three regions are asked for several times per frame (pages, shadows): built once per PaperPoint
  late final Path _front = _buildFront();
  late final Path _back = Path.combine(PathOperation.difference, _backPolygon(), frontPath());
  late final Path _under = Path.combine(
      PathOperation.difference, Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), frontPath()), backPath());

  /// The part of the page still lying flat.
  Path frontPath() => _front;

  /// The back of the lifted paper.
  Path backPath() => _back;

  /// The visible part of the page underneath.
  Path underPath() => _under;

  Path _buildFront() {
    final w = size.width, hh = size.height;
    final p = Path();
    if (fromBottom) {
      p.moveTo(0, 0);
      p.lineTo(0, hh);
      p.lineTo(c.dx, c.dy);
      p.quadraticBezierTo(e.dx, e.dy, b.dx, b.dy);
      p.lineTo(a.dx, a.dy);
      p.lineTo(k.dx, k.dy);
      p.quadraticBezierTo(h.dx, h.dy, j.dx, j.dy);
      p.lineTo(w, 0);
    } else {
      p.moveTo(0, 0);
      p.lineTo(c.dx, c.dy);
      p.quadraticBezierTo(e.dx, e.dy, b.dx, b.dy);
      p.lineTo(a.dx, a.dy);
      p.lineTo(k.dx, k.dy);
      p.quadraticBezierTo(h.dx, h.dy, j.dx, j.dy);
      p.lineTo(w, hh);
      p.lineTo(0, hh);
    }
    p.close();
    return p;
  }

  Path _backPolygon() => Path()
    ..moveTo(i.dx, i.dy)
    ..lineTo(d.dx, d.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(a.dx, a.dy)
    ..lineTo(k.dx, k.dy)
    ..close();

  /// Reflection across the fold line e-h: maps the corner f onto the touch a (the back of the paper is the mirrored front).
  List<double> foldMatrix() {
    final dx = h.dx - e.dx, dy = h.dy - e.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final ux = dx / len, uy = dy / len;
    final m00 = 2 * ux * ux - 1, m01 = 2 * ux * uy, m11 = 2 * uy * uy - 1;
    final tx = e.dx - (m00 * e.dx + m01 * e.dy);
    final ty = e.dy - (m01 * e.dx + m11 * e.dy);
    // column-major 4x4
    return [m00, m01, 0, 0, m01, m11, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1];
  }
}
