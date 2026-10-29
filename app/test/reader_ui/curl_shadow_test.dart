// 模拟翻书 shadows and flashes (owner, 2026-10-30): the page below must not be veiled as a whole, the first frame of a backward turn
// must look exactly like the page that is already there, and the picture of the page must match the live widgets closely (the
// pager swaps one for the other after the first frames).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/widget/bookfx/book_painter.dart';
import 'package:newread/widget/bookfx/model/paper_point.dart';

const _paper = Color(0xFFEDE6D6);
const _w = 440.0, _h = 956.0;

Widget _page(String tag) => Container(
      color: _paper,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFF222222), fontSize: 18, height: 1.8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < 10; i++) Text('第$tag页第${i + 1}行，翻页阴影测试文字。'),
        ]),
      ),
    );

Future<ui.Image> _shoot(WidgetTester tester, GlobalKey key) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
}

Future<ByteData> _rgba(ui.Image img) async => (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;

/// Mean absolute difference per channel; with [fromX] (device pixels, [stride] wide) only the part right of that column.
double _meanDiff(ByteData a, ByteData b, {int fromX = 0, int stride = (_w * 2) ~/ 1}) {
  var sum = 0, n = 0;
  for (var i = 0; i < a.lengthInBytes; i += 4) {
    if ((i ~/ 4) % stride < fromX) continue;
    for (var c = 0; c < 4; c++) {
      sum += (a.getUint8(i + c) - b.getUint8(i + c)).abs();
    }
    n += 4;
  }
  return sum / n;
}

/// Mean colour of the device-pixel rectangle [r] of an image [stride] pixels wide.
Color _meanColor(ByteData px, int stride, Rect r) {
  var rr = 0, gg = 0, bb = 0, n = 0;
  for (var y = r.top.toInt(); y < r.bottom; y++) {
    for (var x = r.left.toInt(); x < r.right; x++) {
      final i = (y * stride + x) * 4;
      rr += px.getUint8(i);
      gg += px.getUint8(i + 1);
      bb += px.getUint8(i + 2);
      n++;
    }
  }
  return Color.fromARGB(255, rr ~/ n, gg ~/ n, bb ~/ n);
}

int _dist(Color a, Color b) => ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 ~/ 3;

void main() {
  testWidgets('the page below is only shadowed next to the lifted paper; a backward turn starts invisible; picture = live', (tester) async {
    tester.view.physicalSize = const Size(_w * 2, _h * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    const corner = Offset(_w, _h);

    await tester.runAsync(() async {
      Future<(ui.Image, ui.Image)> frames(Offset touch, ui.Image pic) async {
        final k1 = GlobalKey(), k2 = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          home: RepaintBoundary(key: k1, child: BookCurl(front: _page('A'), under: _page('B'), touch: touch, corner: corner, paperColor: _paper)),
        ));
        final live = await _shoot(tester, k1);
        await tester.pumpWidget(MaterialApp(
          home: RepaintBoundary(key: k2, child: BookCurl(front: _page('A'), under: _page('B'), frontImage: pic, touch: touch, corner: corner, paperColor: _paper)),
        ));
        final picFrame = await _shoot(tester, k2);
        return (live, picFrame);
      }

      final pageKey = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: pageKey, child: _page('A'))));
      final pageA = await _shoot(tester, pageKey);
      final underKey = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: underKey, child: _page('B'))));
      final plainB = await _rgba(await _shoot(tester, underKey));

      // 1. backward turn, first frame: the previous page is still entirely off the left edge -> the current page, apart from the
      //    soft shadow its edge casts just inside the left border (nothing right of ~30 px may change: the old code veiled it all)
      final (live0, pic0) = await frames(const Offset(-_w, _h), pageA);
      final l0 = await _rgba(live0), p0 = await _rgba(pic0);
      if (Platform.environment['CURL_DEBUG'] == '1') {
        final dir = Directory('build/curl_shadow_debug')..createSync(recursive: true);
        File('${dir.path}/live0.png').writeAsBytesSync((await live0.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
        File('${dir.path}/pic0.png').writeAsBytesSync((await pic0.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
        final plainKey = GlobalKey();
        await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: plainKey, child: _page('B'))));
        final plainImg = await _shoot(tester, plainKey);
        File('${dir.path}/plain.png').writeAsBytesSync((await plainImg.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
        plainImg.dispose();
      }
      expect(_meanDiff(l0, plainB, fromX: 40), lessThan(0.05), reason: 'live first frame of a backward turn');
      expect(_meanDiff(p0, plainB, fromX: 40), lessThan(0.05), reason: 'picture first frame of a backward turn');
      expect(_meanDiff(l0, plainB), lessThan(0.3), reason: 'at most a thin band at the edge differs');

      // 2. mid turn along the bottom edge: the page below shows on the right; far from the fold it keeps its own colour
      final mid = const Offset(_w * 0.25, _h);
      final (liveMid, picMid) = await frames(mid, pageA);
      final p = PaperPoint(mid, corner, const Size(_w, _h));
      expect(p.c.dx, greaterThan(0));
      final px = await _rgba(picMid);
      if (Platform.environment['CURL_DEBUG'] == '1') {
        File('build/curl_shadow_debug/picMid.png').writeAsBytesSync((await picMid.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
        File('build/curl_shadow_debug/liveMid.png').writeAsBytesSync((await liveMid.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
      }
      // a patch of the page below, 80 logical px right of the fold line's top end (device pixels, x2)
      final probe = Rect.fromLTWH((p.j.dx.clamp(0, _w) - 10) * 2, 120 * 2, 8 * 2, 8 * 2);
      final paperThere = _meanColor(plainB, (_w * 2).toInt(), probe);
      final seen = _meanColor(px, (_w * 2).toInt(), probe);
      expect(_dist(seen, paperThere), lessThan(6), reason: 'no veil over the page below ($seen vs $paperThere)');
      // but just right of the crease d-i (where the page below starts) the paper casts a shadow
      final fold = Rect.fromLTWH((p.d.dx + 8) * 2, 700 * 2, 8, 8);
      final nearFold = _meanColor(px, (_w * 2).toInt(), fold);
      expect(_dist(nearFold, _meanColor(plainB, (_w * 2).toInt(), fold)), greaterThan(6), reason: 'a shadow next to the fold');
      // 3. the live frame and the picture frame agree closely (the swap between them must not be visible)
      expect(_meanDiff(await _rgba(liveMid), px), lessThan(0.6));

      // 4. a diagonal corner lift: no veil far from the corner either
      final diag = const Offset(_w * 0.3, _h * 0.7);
      final (_, picDiag) = await frames(diag, pageA);
      final pd = await _rgba(picDiag);
      final farPatch = Rect.fromLTWH((_w - 30) * 2, (_h - 30) * 2, 16, 16); // the corner itself, page below
      expect(_dist(_meanColor(pd, (_w * 2).toInt(), farPatch), _meanColor(plainB, (_w * 2).toInt(), farPatch)), lessThan(8));

      for (final i in [pageA, live0, pic0, liveMid, picMid, picDiag]) {
        i.dispose();
      }
    });
  });

  test('the touch is kept a little off the corner edges, scaled with the reach', () {
    const size = Size(_w, _h);
    final flat = PaperPoint(const Offset(-_w, _h), const Offset(_w, _h), size);
    expect((flat.a.dy - _h).abs(), closeTo(2 * _w * 0.01, 0.01));
    expect(flat.h.dy.isFinite, isTrue);
    expect(flat.j.dy.abs(), lessThan(1e5), reason: 'no million-pixel points');
    final near = PaperPoint(const Offset(_w - 5, _h), const Offset(_w, _h), size);
    expect((near.a.dy - _h).abs(), closeTo(0.5, 0.01));
  });
}
