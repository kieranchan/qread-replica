// 模拟翻书: the page number printed on the back of the lifted page (owner, 2026-11-03: "页数的翻页时的背面显示"). The footer band
// of the page is painted over in paper colour on the back and carries "n/N" at the right margin, mirrored with the page, so it sits
// on the curled corner as soon as it lifts. Checked on pixels, from live widgets and from a picture of the page.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/widget/bookfx/book_painter.dart';
import 'package:newread/widget/bookfx/model/paper_point.dart';

const _paper = Color(0xFFF2EEE4);
const _w = 400.0, _h = 800.0;
const _corner = Offset(_w, _h);
const _touch = Offset(120, 740);

/// A blank page whose footer band (26 px above a 20 px inset) is dark except for its right margin, where the page number goes:
/// the back must hide the band under the label and print the number over paper.
Widget _page() => Container(
      color: _paper,
      child: const Align(alignment: Alignment.bottomLeft, child: Padding(padding: EdgeInsets.only(bottom: 20), child: SizedBox(width: _w - 60, height: 26, child: ColoredBox(color: Color(0xFF444444))))),
    );

const _label = BackLabel(text: '7/12', style: TextStyle(fontSize: 12, color: Color(0xFF222222), height: 1.2), bottomInset: 20, height: 26);

Offset _mirrored(Offset page) => MatrixUtils.transformPoint(Matrix4.fromList(PaperPoint(_touch, _corner, const Size(_w, _h)).foldMatrix()), page);

void main() {
  Future<ui.Image> shoot(WidgetTester tester, GlobalKey key) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
  }

  /// Luminance of the pixel at [p] (whole logical pixels, pixel ratio 1).
  Future<int> lum(ui.Image img, Offset p) async {
    final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (p.dy.round() * img.width + p.dx.round()) * 4;
    return (bd.getUint8(i) + bd.getUint8(i + 1) + bd.getUint8(i + 2)) ~/ 3;
  }

  /// Dark pixels in a window around [c].
  Future<int> ink(ui.Image img, Offset c, {double r = 14}) async {
    var n = 0;
    for (var y = c.dy - r; y <= c.dy + r; y += 2) {
      for (var x = c.dx - r; x <= c.dx + r; x += 2) {
        if (await lum(img, Offset(x, y)) < 120) n++;
      }
    }
    return n;
  }

  for (final fromPicture in [false, true]) {
    testWidgets('the back carries the page number over a paper-coloured footer band (${fromPicture ? 'picture' : 'live'})', (tester) async {
      tester.view.physicalSize = const Size(_w, _h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        ui.Image? pic;
        if (fromPicture) {
          final pageKey = GlobalKey();
          await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: pageKey, child: _page())));
          pic = await shoot(tester, pageKey);
        }
        Future<ui.Image> render(BackLabel? label) async {
          final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            home: RepaintBoundary(
              key: key,
              child: BookCurl(front: _page(), under: const ColoredBox(color: Colors.white), frontImage: pic, touch: _touch, corner: _corner, paperColor: _paper, backLabel: label),
            ),
          ));
          return shoot(tester, key);
        }

        // where the text and a text-free part of the band land on the back
        final text = _mirrored(const Offset(_w - 16 - 12, _h - 20 - 13));
        final band = _mirrored(const Offset(_w - 90, _h - 20 - 13));

        final without = await render(null);
        expect(await ink(without, text), 0, reason: 'nothing but the mirrored page');
        final bandWithout = await lum(without, band);
        expect(bandWithout, lessThan(120), reason: 'the dark footer band mirrors as is');

        final with_ = await render(_label);
        expect(await ink(with_, text), greaterThan(8), reason: 'the page number is printed on the back');
        // paper under the crease shadow is still far brighter than the band was
        expect(await lum(with_, band), greaterThan(bandWithout + 50), reason: 'the band under it is paper');
        without.dispose();
        with_.dispose();
        pic?.dispose();
      });
    });
  }

  test('BackLabel equality drives repaints', () {
    expect(_label, const BackLabel(text: '7/12', style: TextStyle(fontSize: 12, color: Color(0xFF222222), height: 1.2), bottomInset: 20, height: 26));
    expect(_label, isNot(const BackLabel(text: '8/12', style: TextStyle(fontSize: 12, color: Color(0xFF222222), height: 1.2), bottomInset: 20, height: 26)));
    expect(_label.band(const Size(_w, _h)), const Rect.fromLTWH(0, _h - 46, _w, 26));
  });
}
