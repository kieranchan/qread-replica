// The footer battery must be right from its very first frame: the curl rebuilds the page and photographs that frame, so an icon that
// waited for the plugin showed an empty battery on the back of the paper (owner, 2026-10-30). The last good reading is used at once.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/views/battery_painter.dart';

void main() {
  BatteryPainter painterOf(WidgetTester tester) => tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter! as BatteryPainter;

  Widget icon() => const Directionality(textDirection: TextDirection.ltr, child: BatteryIcon(color: Colors.black, height: 11, width: 22));

  testWidgets('first frame uses the last good reading; bad readings are ignored; new readings update it', (tester) async {
    ReaderBattery.last = (level: 80, charging: true);
    ReaderBattery.read = () => Completer<({int level, bool charging})?>().future; // the plugin has not answered yet
    await tester.pumpWidget(icon());
    expect(painterOf(tester).level, 80, reason: 'drawn before the plugin answers');
    expect(painterOf(tester).charging, isTrue);
    expect(find.text(' 充电中'), findsOneWidget);

    // iOS can answer -1 first: not a level
    ReaderBattery.read = () async => (level: -1, charging: false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(icon());
    await tester.pump();
    expect(painterOf(tester).level, 80);
    expect(ReaderBattery.last?.level, 80);

    // a real new reading replaces it and becomes the next first frame
    ReaderBattery.read = () async => (level: 55, charging: false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(icon());
    await tester.pump();
    expect(painterOf(tester).level, 55);
    expect(painterOf(tester).charging, isFalse);
    expect(ReaderBattery.last, (level: 55, charging: false));
    await tester.pumpWidget(const SizedBox());
    ReaderBattery.read = () => Completer<({int level, bool charging})?>().future;
    await tester.pumpWidget(icon());
    expect(painterOf(tester).level, 55, reason: 'the next page starts from the new reading');
  });

  test('the glyph size follows the original footer', () {
    expect(BatteryPainter.sizeFor(12), const Size(22, 11));
    expect(BatteryPainter.sizeFor(25), const Size(35, 24));
  });
}
