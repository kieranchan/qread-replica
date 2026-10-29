// 模拟翻书 starts every turn from pictures taken while the pager was idle (the current page and the previous one, rendered under it),
// so the first frame of a turn neither rebuilds the page nor photographs it — the "refresh" the owner saw at every turn start.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/page.dart';
import 'package:newread/read/setting/read_setting.dart';

void main() {
  testWidgets('idle pictures are ready after the page settles; forward and backward turns use them from the first frame', (tester) async {
    tester.view.physicalSize = const Size(440 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    NovelPager.verbose = false;
    final ctl = NovelPagerController();
    var page = 2;
    final turned = <int>[];

    Future<void> realPumps(int n, [bool Function()? until]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 8));
        if (until != null && until()) return;
      }
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 440,
          height: 800,
          child: StatefulBuilder(
            builder: (context, set) => NovelPager(
              mode: TurnMode.book,
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
      ));
      expect(ctl.idlePicturesReady, isFalse);
      await realPumps(60, () => ctl.idlePicturesReady);
      expect(ctl.idlePicturesReady, isTrue, reason: 'current and previous page photographed while idle');

      // forward: the first frame of the turn already draws from the picture
      final f = ctl.turn(1);
      await tester.pump();
      expect(ctl.turnUsesPicture, isTrue);
      await realPumps(40, () => turned.isNotEmpty);
      expect(await f, isTrue);
      expect(turned, [1]);
      expect(find.text('P3'), findsWidgets);

      // the pictures are retaken for the new position, and a backward turn starts from the previous page's picture
      await realPumps(60, () => ctl.idlePicturesReady);
      expect(ctl.idlePicturesReady, isTrue);
      final b = ctl.turn(-1);
      await tester.pump();
      expect(ctl.turnUsesPicture, isTrue);
      await realPumps(40, () => turned.length == 2);
      expect(await b, isTrue);
      expect(turned, [1, -1]);
      await tester.pump();
      expect(find.text('P2'), findsWidgets);
    });
  });

  testWidgets('without idle pictures (first page, no previous) a backward turn is simply blocked and forward still works', (tester) async {
    tester.view.physicalSize = const Size(440 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final ctl = NovelPagerController();
    var page = 0;
    final blocked = <int>[];
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 440,
          height: 800,
          child: StatefulBuilder(
            builder: (context, set) => NovelPager(
              mode: TurnMode.book,
              controller: ctl,
              pageBuilder: (d) => ColoredBox(color: Colors.white, child: Center(child: Text('P${page + d}'))),
              canTurn: (d) => page + d >= 0 && page + d <= 5,
              onTurned: (d) => set(() => page += d),
              onBlocked: blocked.add,
            ),
          ),
        ),
      ));
      for (var i = 0; i < 60 && !ctl.idlePicturesReady; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      expect(ctl.idlePicturesReady, isTrue, reason: 'only the current page is needed on the first page');
      expect(await ctl.turn(-1), isFalse);
      expect(blocked, [-1]);
      final f = ctl.turn(1);
      await tester.pump();
      expect(ctl.turnUsesPicture, isTrue);
      for (var i = 0; i < 40 && page == 0; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      expect(await f, isTrue);
      expect(page, 1);
    });
  });
}
