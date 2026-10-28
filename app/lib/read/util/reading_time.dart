// read/util/reading_time.dart — the reading-time recorder of the reader (original 0xf2b8e0: a session start time; on save the seconds are
// added for the book and the day, a session over midnight is split ("跨天阅读时间已保存"), audio and video books (types 1 / 4) are not
// counted, failures print "保存阅读时间失败: "). Counted only while the reader is open and the app in the foreground, saved every
// minute and when the reader pauses / closes, through `storage/book_reading_time_storage.dart`. Switched off when both 全局统计
// (`globalReadRecord`) and 单本统计 (`perBookReadRecord`) are off (both default on).
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/bookself.dart';
import '../../models/book.dart';
import '../../storage/book_reading_time_storage.dart';
import '../../storage/storage.dart';

class ReadingTimer {
  final Book book;

  /// Clock (tests).
  final DateTime Function() now;

  /// The write (tests replace it).
  static Future<void> Function(String bookKey, int seconds, {DateTime? day}) record = BookReadingTimeStorage.addReading;

  static Duration flushEvery = const Duration(minutes: 1);

  DateTime? _since;
  Timer? _timer;

  ReadingTimer(this.book, {DateTime Function()? now}) : now = now ?? DateTime.now;

  static bool _flag(String key) => Storage.getString(key).isEmpty || Storage.getBool(key, true);

  /// Whether this book's time is recorded.
  bool get enabled => book.type_ != 1 && book.type_ != 4 && (_flag('globalReadRecord') || _flag('perBookReadRecord'));

  bool get running => _since != null;

  void start() {
    if (!enabled || _since != null) return;
    _since = now();
    _timer?.cancel();
    _timer = Timer.periodic(flushEvery, (_) => flush());
  }

  /// Saves the time since the last save; the session goes on.
  Future<void> flush() async {
    final s = _since;
    if (s == null) return;
    final t = now();
    _since = t;
    await _save(s, t);
  }

  /// App in the background / reader closed: saves and stops counting.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final s = _since;
    _since = null;
    if (s != null) await _save(s, now());
  }

  Future<void> _save(DateTime from, DateTime to) async {
    if (!to.isAfter(from)) return;
    final key = bookKey(book);
    try {
      final midnight = DateTime(to.year, to.month, to.day);
      if (from.isBefore(midnight)) {
        // 跨天: the part before midnight belongs to the day before
        await record(key, midnight.difference(from).inSeconds, day: from);
        await record(key, to.difference(midnight).inSeconds, day: to);
        debugPrint('跨天阅读时间已保存');
      } else {
        await record(key, to.difference(from).inSeconds, day: to);
        debugPrint('书籍阅读时间已保存');
      }
    } catch (e) {
      debugPrint('保存阅读时间失败: $e');
    }
  }
}
