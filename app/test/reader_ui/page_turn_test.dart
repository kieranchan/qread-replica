// Page-turn effects: the PaperPoint geometry of 模拟翻书, the PageFlipEffect roll of 仿真翻页 (constants of 0x4e51fc), and NovelPager in the
// curl modes (drag follows the finger, release completes or puts the page back, taps animate).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/page.dart';
import 'package:newread/read/setting/read_setting.dart';
import 'package:newread/widget/bookfx/book_painter.dart';
import 'package:newread/widget/bookfx/model/paper_point.dart';
import 'package:newread/widget/pageflip/effects/flip_effect.dart';

void main() {
  test('PaperPoint: fold geometry of a corner curl', () {
    const size = Size(400, 800);
    final p = PaperPoint(const Offset(300, 700), const Offset(400, 800), size);
    expect(p.g, const Offset(350, 750));
    // e and h lie on the corner's edges and on the perpendicular bisector of a-f
    expect(p.e.dy, 800);
    expect(p.h.dx, 400);
    expect(p.e.dx, closeTo(300, 1e-9));
    expect(p.h.dy, closeTo(700, 1e-9));
    expect(p.c.dx, closeTo(250, 1e-9));
    expect(p.j.dy, closeTo(650, 1e-9));
    // b on a-e and on c-j
    expect(p.b.dx, closeTo(300, 1e-6)); // a-e is vertical here: b = (300, 750), k = (350, 700)
    expect(p.b.dy, closeTo(750, 1e-6));
    expect(p.k.dx, closeTo(350, 1e-6));
    // reflecting the corner across the fold gives the touch point
    final m = Matrix4.fromList(p.foldMatrix());
    final mapped = MatrixUtils.transformPoint(m, p.f);
    expect(mapped.dx, closeTo(p.a.dx, 1e-6));
    expect(mapped.dy, closeTo(p.a.dy, 1e-6));
    // the three regions cover the page
    expect(p.frontPath().contains(const Offset(10, 10)), isTrue);
    expect(p.underPath().contains(const Offset(395, 795)), isTrue);
    expect(p.backPath().contains(const Offset(316, 716)), isTrue);
    expect(p.frontPath().contains(const Offset(316, 716)), isFalse);
    // dragging far left keeps the fold on the page
    final c = PaperPoint.constrain(const Offset(-300, 500), const Offset(400, 800), size);
    expect(PaperPoint(c, const Offset(400, 800), size).c.dx, greaterThanOrEqualTo(0));
    expect(PaperPoint(const Offset(-300, 500), const Offset(400, 800), size).c.dx, lessThan(0));
  });

  test('PageFlipEffect: roll radius and offset of the original', () {
    expect(PageFlipEffect.movX(1), 0);
    expect(PageFlipEffect.movX(0), 0.85);
    expect(PageFlipEffect.rollRadius(0.9), closeTo(0.18 * 0.085 * 5, 1e-9)); // movX 0.085 < 0.2
    expect(PageFlipEffect.rollRadius(0.5), 0.18);
  });

  testWidgets('PageFlipEffect paints a picture', (tester) async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 40, 80), Paint()..color = Colors.red);
    final img = (await tester.runAsync(() => rec.endRecording().toImage(40, 80)))!;
    await tester.pumpWidget(Center(
      child: SizedBox(width: 40, height: 80, child: CustomPaint(painter: PageFlipEffect(amount: 0.5, image: img, backgroundColor: Colors.white))),
    ));
    expect(tester.takeException(), isNull);
    img.dispose();
  });

  for (final mode in [TurnMode.book, TurnMode.simulation, TurnMode.appleBook]) {
    testWidgets('NovelPager mode $mode: drag back puts the page back, a long drag and a tap turn', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var page = 0;
      final turned = <int>[];
      final ctl = NovelPagerController();
      Widget pager() => MaterialApp(
            home: SizedBox(
              width: 400,
              height: 800,
              child: StatefulBuilder(
                builder: (context, set) => NovelPager(
                  mode: mode,
                  controller: ctl,
                  pageBuilder: (d) => ColoredBox(color: Colors.white, child: Center(child: Text('P${page + d}'))),
                  canTurn: (d) => page + d >= 0 && page + d <= 5,
                  onTurned: (d) => set(() {
                    page += d;
                    turned.add(d);
                  }),
                ),
              ),
            ),
          );
      await tester.pumpWidget(pager());
      expect(find.text('P0'), findsOneWidget);

      // a short drag that comes back: no turn
      final g = await tester.startGesture(const Offset(380, 700));
      await g.moveBy(const Offset(-40, -10));
      await tester.pump();
      if (mode != TurnMode.simulation) expect(find.byType(BookCurl), findsOneWidget);
      await g.moveBy(const Offset(35, 10));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(turned, isEmpty);

      // a long drag to the left turns forward
      await tester.dragFrom(const Offset(380, 700), const Offset(-300, -40));
      await tester.pumpAndSettle();
      expect(turned, [1]);
      expect(find.text('P1'), findsOneWidget);

      // controller turns (tap zones) in both directions
      final t1 = ctl.turn(1);
      await tester.pumpAndSettle();
      expect(await t1, isTrue);
      final t2 = ctl.turn(-1);
      await tester.pumpAndSettle();
      expect(await t2, isTrue);
      expect(turned, [1, 1, -1]);
      expect(find.text('P1'), findsOneWidget);

      // dragging right turns back
      await tester.dragFrom(const Offset(40, 400), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(turned.last, -1);
      expect(find.text('P0'), findsOneWidget);
    });
  }
}
