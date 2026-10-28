// Download progress: the helper keeps the tasks and forwards them to the system notification sink.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/read/util/down_notification.dart';

class _Sink implements DownSink {
  final List<String> log = [];
  @override
  Future<void> show(DownTask t) async => log.add(t.text);
  @override
  Future<void> remove(String bookUrl) async => log.add('remove $bookUrl');
}

void main() {
  test('progress goes to the sink, one id per book', () async {
    final h = DownNotificationHelper.instance;
    final old = h.sink;
    final sink = _Sink();
    h.sink = sink;
    addTearDown(() => h.sink = old);
    h.update(const DownTask('u1', '书一', 3, 10));
    h.update(const DownTask('u1', '书一', 10, 10, finished: true));
    h.remove('u1');
    await pumpEventQueue();
    expect(sink.log, ['书一 缓存中 3/10', '缓存加载完成', 'remove u1']);
    expect(h.tasks.value, isEmpty);
    expect(LocalNotificationSink.idOf('u1'), LocalNotificationSink.idOf('u1'));
    expect(LocalNotificationSink.idOf('u1'), isNonNegative);
  });
}
