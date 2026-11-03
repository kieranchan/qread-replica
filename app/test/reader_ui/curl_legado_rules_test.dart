// 模拟翻书 turns as Legado's SimulationPageDelegate / HorizontalPageDelegate do them (decompiled nn.i / nn.c, 2026-11-03, owner:
// "你得根据安卓的那个的代码来做设计"): tap-turn start points, the corner by the tap's / finger's y, the touch pinned to the corner's edge
// for a flat flip, the backward touch at the finger's own x on the bottom edge, and a linear animation whose duration is the turn
// speed scaled by the distance left (300 ms per page width).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/page.dart';
import 'package:newread/read/setting/read_setting.dart';

void main() {
  const w = 400.0, h = 800.0;

  Future<NovelPagerController> pump(WidgetTester tester, {int page = 2, List<int>? turned}) async {
    tester.view.physicalSize = const Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ctl = NovelPagerController();
    var cur = page;
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: w,
        height: h,
        child: StatefulBuilder(
          builder: (context, set) => NovelPager(
            mode: TurnMode.book,
            controller: ctl,
            duration: const Duration(milliseconds: 300),
            pageBuilder: (d) => ColoredBox(color: Colors.white, child: Center(child: Text('P${cur + d}'))),
            canTurn: (d) => cur + d >= 0 && cur + d <= 5,
            onTurned: (d) => set(() {
              cur += d;
              turned?.add(d);
            }),
            onTap: (p, s) => ctl.turn(p.dx > s.width / 2 ? 1 : -1),
          ),
        ),
      ),
    ));
    return ctl;
  }

  testWidgets('a tap in the lower half lifts the bottom-right corner from (0.9w, 0.9h); 1.9 page widths take 570 ms, linearly', (tester) async {
    final turned = <int>[];
    final ctl = await pump(tester, turned: turned);
    await tester.tapAt(const Offset(300, 600));
    await tester.pump();
    var (touch, corner, anim) = ctl.debugCurl;
    expect(corner, const Offset(w, h));
    expect(touch, const Offset(w * 0.9, h * 0.9));
    expect(anim.inMilliseconds, 570); // (0.9 w + w) / w * 300
    // linear: halfway through the time the touch is halfway along x
    await tester.pump(const Duration(milliseconds: 285));
    (touch, corner, anim) = ctl.debugCurl;
    expect(touch!.dx, closeTo((w * 0.9 + -w) / 2, 2));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(turned, [1]);
    expect(find.text('P3'), findsOneWidget);
  });

  testWidgets('a tap in the upper half lifts the top-right corner from (0.9w, 1)', (tester) async {
    final ctl = await pump(tester);
    await tester.tapAt(const Offset(300, 100));
    await tester.pump();
    final (touch, corner, anim) = ctl.debugCurl;
    expect(corner, const Offset(w, 0));
    expect(touch, const Offset(w * 0.9, 1));
    expect(anim.inMilliseconds, 570);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('P3'), findsOneWidget);
  });

  testWidgets('a turn without a tap (keys, menus) starts like a lower-half tap; backwards starts at (0, h) and takes one page width', (tester) async {
    final ctl = await pump(tester);
    final f = ctl.turn(1);
    await tester.pump();
    var (touch, corner, anim) = ctl.debugCurl;
    expect(corner, const Offset(w, h));
    expect(touch, const Offset(w * 0.9, h * 0.9));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(await f, isTrue);
    expect(find.text('P3'), findsOneWidget);

    final b = ctl.turn(-1);
    await tester.pump();
    (touch, corner, anim) = ctl.debugCurl;
    expect(corner, const Offset(w, h));
    expect(touch, const Offset(0, h));
    expect(anim.inMilliseconds, 300); // (w - 0) / w * 300
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    expect(await b, isTrue);
    expect(find.text('P2'), findsOneWidget);
  });

  testWidgets('drags: the corner by the start\'s y, a flat flip from the middle third, a diagonal from the outer thirds; backwards the finger\'s own x on the bottom edge', (tester) async {
    final turned = <int>[];
    final ctl = await pump(tester, turned: turned);

    // lower-middle third, forward: bottom-right corner, touch pinned to the bottom edge; moving back puts it back
    var g = await tester.startGesture(const Offset(380, 450));
    await g.moveBy(const Offset(-50, -30));
    await tester.pump();
    var (touch, corner, _) = ctl.debugCurl;
    expect(corner, const Offset(w, h));
    expect(touch, const Offset(330, h));
    await g.moveBy(const Offset(5, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(turned, isEmpty);

    // upper-middle third: the top-right corner, touch on the top edge
    g = await tester.startGesture(const Offset(380, 300));
    await g.moveBy(const Offset(-50, 30));
    await tester.pump();
    (touch, corner, _) = ctl.debugCurl;
    expect(corner, const Offset(w, 0));
    expect(touch, const Offset(330, 1));
    await g.moveBy(const Offset(5, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(turned, isEmpty);

    // bottom third: a diagonal curl that follows the finger
    g = await tester.startGesture(const Offset(380, 700));
    await g.moveBy(const Offset(-50, -30));
    await tester.pump();
    (touch, corner, _) = ctl.debugCurl;
    expect(corner, const Offset(w, h));
    expect(touch!.dy, lessThan(h - 5));
    expect(touch.dx, closeTo(330, 5));
    await g.moveBy(const Offset(5, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(turned, isEmpty);

    // backwards: the previous page's corner is the bottom-right one, the touch is the finger's x on the bottom edge
    g = await tester.startGesture(const Offset(40, 400));
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    (touch, corner, _) = ctl.debugCurl;
    expect(corner, const Offset(w, h));
    expect(touch, const Offset(100, h));
    // the last movement went on to the right: letting go completes the turn, however short the drag
    await g.up();
    await tester.pumpAndSettle();
    expect(turned, [-1]);
    expect(find.text('P1'), findsOneWidget);
  });
}
