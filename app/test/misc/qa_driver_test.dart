// QaDriver: off without its flag file (or with a short token); texts, taps, typing, submit and back on a small app.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/app_dirs.dart';
import 'package:newread/dev/qa_driver.dart';

void main() {
  test('stays off without the flag file or with a short token', () async {
    final dir = Directory.systemTemp.createTempSync('qa_driver');
    addTearDown(() => dir.deleteSync(recursive: true));
    AppDirs.root = dir;
    await QaDriver.start();
    expect(QaDriver.running, isFalse);
    File('${dir.path}/.qa_driver').writeAsStringSync('short\n');
    await QaDriver.start();
    expect(QaDriver.running, isFalse);
  });

  testWidgets('texts, tap, type, submit, back', (tester) async {
    var taps = 0;
    String? submitted;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(
        body: Column(children: [
          TextButton(onPressed: () => taps++, child: const Text('按钮')),
          TextField(autofocus: true, textInputAction: TextInputAction.search, onSubmitted: (s) => submitted = s),
        ]),
      ),
    ));
    await tester.pump();

    final texts = (await QaDriver.run('/texts', const {}))! as List;
    final button = texts.cast<Map<String, Object?>>().firstWhere((t) => t['t'] == '按钮');
    expect(button['hit'], isTrue);
    final r = (button['r']! as List).cast<int>();

    final tap = QaDriver.run('/tap', {'x': '${(r[0] + r[2]) / 2}', 'y': '${(r[1] + r[3]) / 2}'});
    await tester.pump(const Duration(milliseconds: 100));
    expect(await tap, 'ok');
    await tester.pump();
    expect(taps, 1);

    expect(await QaDriver.run('/type', {'s': '斩神'}), 'ok');
    await tester.pump();
    expect(find.text('斩神'), findsOneWidget);
    expect(await QaDriver.run('/submit', const {}), 'ok');
    expect(submitted, '斩神');

    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('第二页'))));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);
    final back = QaDriver.run('/back', const {});
    await tester.pumpAndSettle();
    expect(await back, 'popped');
    expect(find.text('第二页'), findsNothing);
    expect(await QaDriver.run('/nope', const {}), 'unknown /nope');
  });
}
