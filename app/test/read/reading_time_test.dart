// Reading time: counted per session, saved on stop, split over midnight, switched off by 全局统计 / 单本统计, audio / video not counted.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/read/util/reading_time.dart';
import 'package:newread/storage/book_reading_time_storage.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

void main() {
  setUp(() async => newDevice());
  tearDown(() => ReadingTimer.record = BookReadingTimeStorage.addReading);

  test('a session adds its seconds to the book and the day', () async {
    var t = DateTime(2026, 10, 28, 20, 0, 0);
    final book = Book(bookUrl: 'https://x/b1', name: 'b1');
    final timer = ReadingTimer(book, now: () => t)..start();
    t = t.add(const Duration(minutes: 3, seconds: 5));
    await timer.flush();
    t = t.add(const Duration(seconds: 55));
    await timer.stop();
    expect(await BookReadingTimeStorage.bookSeconds('https://x/b1'), 240);
    expect(await BookReadingTimeStorage.daySeconds(DateTime(2026, 10, 28)), 240);
    expect(timer.running, isFalse);
  });

  test('over midnight the time is split between the days', () async {
    final calls = <String>[];
    ReadingTimer.record = (k, s, {DateTime? day}) async => calls.add('$k $s ${day!.day}');
    var t = DateTime(2026, 10, 28, 23, 59, 0);
    final timer = ReadingTimer(Book(bookUrl: 'u', name: 'n'), now: () => t)..start();
    t = DateTime(2026, 10, 29, 0, 2, 0);
    await timer.stop();
    expect(calls, ['u 60 28', 'u 120 29']);
  });

  test('switched off, and audio / video books are not counted', () async {
    expect(ReadingTimer(Book(bookUrl: 'a', type_: 1)).enabled, isFalse);
    expect(ReadingTimer(Book(bookUrl: 'v', type_: 4)).enabled, isFalse);
    expect(ReadingTimer(Book(bookUrl: 'c', type_: 2)).enabled, isTrue);
    await Storage.setBool('globalReadRecord', false);
    expect(ReadingTimer(Book(bookUrl: 'n')).enabled, isTrue); // 单本统计 still on
    await Storage.setBool('perBookReadRecord', false);
    final t = ReadingTimer(Book(bookUrl: 'n'))..start();
    expect(t.running, isFalse);
  });
}
