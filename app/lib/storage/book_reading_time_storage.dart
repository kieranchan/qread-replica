// storage/book_reading_time_storage.dart — reading-time bookkeeping: per-book seconds in `<root>/book_reading_time/<md5(bookKey)>.json`
// (0xf2cc78) and per-day seconds in `<root>/reading_time/<yyyyMMdd>.json` (0xf2d920; the date text has its dashes removed).
// Both are JSON maps with a `seconds` entry (the day range query 0x10dfb2c sums `seconds`; failure text `获取阅读时间范围失败: …`).
// Writes of the same file are chained through `_saveLocks` (static 0x4cc0, Map<String, Future<void>>) so concurrent adds do not lose updates.
// TODO(asm 0x10dfb2c): the per-day file layout beyond `seconds` is not recovered; the replica writes `{"seconds": n}` only.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../common/app_dirs.dart';
import 'storage.dart';

abstract class BookReadingTimeStorage {
  static final Map<String, Future<void>> _saveLocks = {};

  static String _bookFile(String bookKey) => p.join(AppDirs.path('book_reading_time'), '${Storage.md5Of(bookKey)}.json');

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static String _dayFile(DateTime d) => p.join(AppDirs.path('reading_time'), '${dayKey(d)}.json');

  static Future<int> _readSeconds(String path) async {
    try {
      final text = await Storage.readFile(path);
      if (text.isEmpty) return 0;
      final v = jsonDecode(text);
      if (v is Map) return int.tryParse('${v['seconds'] ?? 0}') ?? 0;
    } catch (_) {}
    return 0;
  }

  /// Adds [seconds] to [path] after every earlier add to the same file finished.
  static Future<void> _add(String path, int seconds) {
    final previous = _saveLocks[path] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      await Directory(p.dirname(path)).create(recursive: true);
      final now = await _readSeconds(path);
      await Storage.writeFile(path, jsonEncode({'seconds': now + seconds}));
    });
    _saveLocks[path] = next;
    return next.whenComplete(() {
      if (identical(_saveLocks[path], next)) _saveLocks.remove(path);
    });
  }

  /// Total seconds read in this book.
  static Future<int> bookSeconds(String bookKey) => _readSeconds(_bookFile(bookKey));

  /// Records a reading session of [seconds] for [bookKey], counted on [day] (default today).
  static Future<void> addReading(String bookKey, int seconds, {DateTime? day}) async {
    if (seconds <= 0) return;
    await _add(_bookFile(bookKey), seconds);
    await _add(_dayFile(day ?? DateTime.now()), seconds);
  }

  static Future<int> daySeconds(DateTime day) => _readSeconds(_dayFile(day));

  /// Sum of the daily files from [from] to [to] (both inclusive, local dates).
  static Future<int> secondsInRange(DateTime from, DateTime to) async {
    var total = 0;
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end)) {
      total += await _readSeconds(_dayFile(d));
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return total;
  }

  /// Forgets a book's total (when the book is removed from the shelf).
  static Future<void> clearBook(String bookKey) async {
    final f = File(_bookFile(bookKey));
    if (f.existsSync()) await f.delete();
  }
}
