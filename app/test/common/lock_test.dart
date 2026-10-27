import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/lock.dart';

final lock = Lock();

void main() {
  test('calls run one after another, errors stay with their caller', () async {
    final order = <String>[];
    final a = lock.synchronized(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      order.add('a');
    });
    final b = lock.synchronized(() async => throw StateError('b'));
    final c = lock.synchronized(() => order.add('c'));
    await a;
    await expectLater(b, throwsStateError);
    await c;
    expect(order, ['a', 'c']);
  });

  // the static lock is first used inside one widget test's fake-async zone and then again in the next test
  testWidgets('first widget test takes the lock', (tester) async {
    expect(await lock.synchronized(() => 1), 1);
  });

  testWidgets('a later widget test can still take it', (tester) async {
    final r = await tester.runAsync(() => lock.synchronized(() async => 2)).timeout(const Duration(seconds: 5));
    expect(r, 2);
  });
}
