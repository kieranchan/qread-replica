// 模拟翻书: the page number on the back of the lifted page (owner, 2026-11-03: "页数的翻页时的背面显示", then "翻页时的背面是完整
// 的对称的，页码你需要镜像的放在背面的中间"). The back stays the complete mirror of the page; the number sits in the middle of the
// visible back strip at the footer's height, mirrored, on a small paper halo; the footer's own number is patched out of the mirror
// when it stands alone in the centre slot. Checked on pixels, from live widgets and from a picture of the page.
//
// Why the number needs its own place: with a finger on the screen, Legado's geometry keeps the fold at the bottom edge right of the
// page's centre for a bottom-right lift (e.x ≈ (a.x + f.x) / 2), so a page number in the footer's middle never reaches the back
// while dragging — only in the last frames of the finishing animation, when the touch is already off the screen.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/widget/bookfx/book_painter.dart';
import 'package:newread/widget/bookfx/model/paper_point.dart';

const _paper = Color(0xFFF2EEE4);
const _band = Color(0xFF444444);
const _w = 400.0, _h = 800.0;
const _size = Size(_w, _h);
const _corner = Offset(_w, _h);
const _style = TextStyle(fontSize: 12, color: Color(0xFF222222), height: 1.2);

/// A blank page whose footer band (26 px above a 20 px inset) is dark: the mirror must keep it, the halo must read over it.
Widget _page() => Container(
      color: _paper,
      child: const Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.only(bottom: 20), child: SizedBox(width: _w, height: 26, child: ColoredBox(color: _band)))),
    );

const _label = BackLabel(text: '7/12', style: _style, bottomInset: 20, height: 26);
const _patching = BackLabel(text: '7/12', style: _style, bottomInset: 20, height: 26, coverCentre: true);

/// A finger on the screen near the bottom edge: the fold sits right of the page's centre.
final _onScreen = PaperPoint(const Offset(20, 780), _corner, _size);

Offset _mirrored(PaperPoint p, Offset page) => MatrixUtils.transformPoint(Matrix4.fromList(p.foldMatrix()), page);

int _lum(ByteData bd, int width, Offset p) {
  final i = (p.dy.round() * width + p.dx.round()) * 4;
  return (bd.getUint8(i) + bd.getUint8(i + 1) + bd.getUint8(i + 2)) ~/ 3;
}

/// Dark and bright pixels in a window around [c].
(int, int) _count(ByteData bd, int width, Offset c, {double r = 14}) {
  var dark = 0, bright = 0;
  for (var y = c.dy - r; y <= c.dy + r; y += 2) {
    for (var x = c.dx - r; x <= c.dx + r; x += 2) {
      final l = _lum(bd, width, Offset(x, y));
      if (l < 120) dark++;
      if (l > 200) bright++;
    }
  }
  return (dark, bright);
}

void main() {
  Future<ui.Image> shoot(WidgetTester tester, GlobalKey key) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
  }

  /// Pixels that differ between two renderings outside circles of [r] around [keep].
  int changedOutside(ByteData a, ByteData b, List<Offset> keep, {double r = 30}) {
    var n = 0;
    for (var y = 0; y < _h; y += 2) {
      for (var x = 0; x < _w; x += 2) {
        final p = Offset(x.toDouble(), y.toDouble());
        if (keep.any((k) => (k - p).distance < r)) continue;
        if ((_lum(a, _w.toInt(), p) - _lum(b, _w.toInt(), p)).abs() > 8) n++;
      }
    }
    return n;
  }

  for (final fromPicture in [false, true]) {
    testWidgets('a drag: the number in the middle of the back strip on a paper halo, the rest of the mirror untouched (${fromPicture ? 'picture' : 'live'})', (tester) async {
      tester.view.physicalSize = _size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        ui.Image? pic;
        if (fromPicture) {
          final pageKey = GlobalKey();
          await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: pageKey, child: _page())));
          pic = await shoot(tester, pageKey);
        }
        Future<ByteData> render(BackLabel? label) async {
          final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: BookCurl(front: _page(), under: const ColoredBox(color: Colors.white), frontImage: pic, touch: _onScreen.a, corner: _corner, paperColor: _paper, backLabel: label),
            ),
          ));
          final img = await shoot(tester, key);
          final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          img.dispose();
          return bd;
        }

        final y = _label.footerY(_size);
        expect(BackLabel.foldX(_onScreen, y, _size), greaterThan(_w / 2), reason: 'the footer\'s centre never reaches the back while dragging');
        final atNumber = _mirrored(_onScreen, _label.anchor(_size, _onScreen));

        final without = await render(null);
        final (dark0, bright0) = _count(without, _w.toInt(), atNumber); // the dark band mirrors as is where the number will go
        expect(dark0, greaterThan(100));
        final plain = await render(_label);
        final (dark, bright) = _count(plain, _w.toInt(), atNumber);
        expect(bright, greaterThan(bright0 + 8), reason: 'the paper halo');
        expect(dark, greaterThan(8), reason: 'the number on it');
        expect(dark, lessThan(dark0 - 20), reason: 'the halo took the band\'s place under the number');
        expect(changedOutside(without, plain, [atNumber]), 0, reason: 'everything else on the back is the mirror as before');
        // the footer's centre is not on the back here, so the patch changes nothing
        final patched = await render(_patching);
        expect(changedOutside(plain, patched, const []), 0);
        pic?.dispose();
      });
    });
  }

  test('paint: the footer\'s own number is patched out only when asked; the halo sits at the anchor', () async {
    Future<ByteData> draw(BackLabel label) async {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(Offset.zero & _size, Paint()..color = _paper);
      canvas.drawRect(label.band(_size), Paint()..color = _band);
      label.paint(canvas, _size, _onScreen, _paper); // page coordinates, no mirror
      final img = await rec.endRecording().toImage(_w.toInt(), _h.toInt());
      final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      img.dispose();
      return bd;
    }

    final y = _label.footerY(_size);
    final centre = Offset(_w / 2, y);
    final plain = await draw(_label);
    expect(_count(plain, _w.toInt(), centre, r: 4).$2, 0, reason: 'the band at the centre stays');
    final patched = await draw(_patching);
    expect(_count(patched, _w.toInt(), centre, r: 4).$1, 0, reason: 'patched in paper');
    expect(_count(patched, _w.toInt(), centre, r: 4).$2, greaterThan(10));
    final anchor = _label.anchor(_size, _onScreen);
    final (dark, bright) = _count(patched, _w.toInt(), anchor);
    expect(bright, greaterThan(8), reason: 'the halo');
    expect(dark, greaterThan(8), reason: 'the number');
    expect(_count(patched, _w.toInt(), Offset(anchor.dx - 40, y), r: 4).$1, greaterThan(10), reason: 'the band beside the halo stays');
  });

  test('anchor: midway between the fold and the lifted corner\'s edge at the footer\'s height; band', () {
    final y = _label.footerY(_size);
    expect(y, _h - 20 - 13);
    expect(_label.band(_size), const Rect.fromLTWH(0, _h - 46, _w, 26));
    final fx = BackLabel.foldX(_onScreen, y, _size);
    expect(fx, closeTo(210, 5));
    expect(_label.anchor(_size, _onScreen), Offset((fx + _w) / 2, y));
    // a lift from the bottom-left corner (the previous page coming back): the strip runs from the fold to the left edge
    final left = PaperPoint(const Offset(380, 780), const Offset(0, _h), _size);
    final lx = BackLabel.foldX(left, y, _size);
    expect(lx, closeTo(190, 5));
    expect(_label.anchor(_size, left), Offset(lx / 2, y));
  });

  test('BackLabel equality drives repaints', () {
    expect(_label, const BackLabel(text: '7/12', style: _style, bottomInset: 20, height: 26));
    expect(_label, isNot(const BackLabel(text: '8/12', style: _style, bottomInset: 20, height: 26)));
    expect(_label, isNot(_patching));
  });
}
