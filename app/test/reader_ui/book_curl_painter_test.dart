// 模拟翻书 drawn from a picture of the page (widget/bookfx/book_painter.dart): the flat part keeps the page's pixels, the lifted
// corner shows the page underneath, the back of the paper is the mirrored front washed out towards white.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/widget/bookfx/book_painter.dart';
import 'package:newread/widget/bookfx/model/paper_point.dart';

Future<ui.Image> _page(int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF2040C0)); // a blue page
  c.drawRect(Rect.fromLTWH(0, 0, w / 2, h.toDouble()), Paint()..color = const Color(0xFF802020)); // dark red left half
  return rec.endRecording().toImage(w, h);
}

Future<ui.Image> _paint(PaperPoint p, ui.Image page, Size size) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF00FF00)); // "the page underneath" is green
  BookCurlPainter(p, page, const Color(0xFFF2EEE4)).paint(c, size);
  return rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
}

Future<Color> _pixel(ui.Image img, int x, int y) async {
  final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * img.width + x) * 4;
  return Color.fromARGB(bd.getUint8(i + 3), bd.getUint8(i), bd.getUint8(i + 1), bd.getUint8(i + 2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the curl from a picture: flat part, page underneath and the washed-out mirrored back', () async {
    const size = Size(200, 400);
    final page = await _page(200, 400);
    // the bottom-right corner lifted to the middle of the page
    final p = PaperPoint(const Offset(100, 200), const Offset(200, 400), size);
    final out = await _paint(p, page, size);
    expect(out.width, 200);
    int rgb(Color c) => c.toARGB32() & 0xffffff;
    int sum(Color c) => ((c.r + c.g + c.b) * 255).round();
    // top-left: the page still lies flat (dark red)
    expect(rgb(await _pixel(out, 10, 10)), 0x802020);
    // the lifted corner shows the page underneath (green, darkened by the paper's shadow near the fold)
    final under = await _pixel(out, 195, 395);
    expect(under.r, 0);
    expect(under.b, 0);
    expect(under.g, greaterThan(0.5));
    // the back of the paper near the touch point: the front mirrored and washed out (lighter than the blue, not blue, not green)
    final back = await _pixel(out, 120, 215);
    expect(rgb(back), isNot(0x2040c0));
    expect(rgb(back), isNot(0x00ff00));
    expect(sum(back), greaterThan(0x20 + 0x40 + 0xc0));
    page.dispose();
    out.dispose();
  });

  testWidgets('BookCurl with a picture builds the painter, without one the live widgets', (t) async {
    final page = await _page(100, 200);
    Widget curl(ui.Image? img) => MaterialApp(
          home: SizedBox(
            width: 100,
            height: 200,
            child: BookCurl(
              front: const ColoredBox(color: Colors.white, child: Text('front')),
              under: const ColoredBox(color: Colors.black, child: Text('under')),
              frontImage: img,
              touch: const Offset(50, 100),
              corner: const Offset(100, 200),
            ),
          ),
        );
    await t.pumpWidget(curl(page));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('front'), findsNothing);
    expect(find.text('under'), findsOneWidget);
    await t.pumpWidget(curl(null));
    expect(find.text('front'), findsWidgets);
    page.dispose();
  });
}
