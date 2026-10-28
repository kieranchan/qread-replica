// storage/book_reading_time_storage.dart — reading-time bookkeeping, file layouts as the original:
//   per day   `<root>/reading_time/<yyyyMMdd>.json` (path 0xf2d920, writer 0xf2d4f4):
//             `{"date": "yyyy-MM-dd", "seconds": n, "createdAt": iso, "updatedAt": iso}`; an add bumps `seconds` + `updatedAt`
//   per book  `<root>/book_reading_time/<md5(bookKey)>.json` (path 0xf2cc78, writer 0xf2bd98):
//             `{"totalSeconds": n, "records": {"yyyy-MM-dd": seconds}}` (`保存书籍阅读时间失败: …`)
//   range     0x10dfb2c: every day file whose date lies after `from` and before `to` + 1 day → `{"yyyy-MM-dd": seconds}`
//             (`获取阅读时间范围失败: …`)
// Files of earlier replica builds (`{"seconds": n}` only) are still read. Writes of the same file are chained through `_saveLocks`
// (static 0x4cc0, Map<String, Future<void>>) so concurrent adds do not lose updates.
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

  /// `yyyy-MM-dd` of [d] (what `DateTime.toString().split(' ')[0]` gives in the original).
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<Map<String, dynamic>> _readMap(String path) async {
    try {
      final text = await Storage.readFile(path);
      if (text.isEmpty) return {};
      final v = jsonDecode(text);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return {};
  }

  static int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0);

  static Future<int> _readSeconds(String path) async {
    final m = await _readMap(path);
    return _int(m['totalSeconds'] ?? m['seconds']);
  }

  /// Runs [update] on the map stored in [path] after every earlier update of the same file finished.
  static Future<void> _update(String path, void Function(Map<String, dynamic> m) update) {
    final previous = _saveLocks[path] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      await Directory(p.dirname(path)).create(recursive: true);
      final m = await _readMap(path);
      update(m);
      await Storage.writeFile(path, jsonEncode(m));
    });
    _saveLocks[path] = next;
    return next.whenComplete(() {
      if (identical(_saveLocks[path], next)) _saveLocks.remove(path);
    });
  }

  /// 0xf2d4f4: a new day file gets `date` / `createdAt`; every add bumps `seconds` and `updatedAt`.
  static Future<void> _addDay(DateTime day, int seconds) => _update(_dayFile(day), (m) {
        final now = DateTime.now().toIso8601String();
        if (m.isEmpty) {
          m.addAll({'date': dateKey(day), 'seconds': seconds, 'createdAt': now, 'updatedAt': now});
        } else {
          m['seconds'] = _int(m['seconds']) + seconds;
          m['updatedAt'] = now;
        }
      });

  /// 0xf2bd98: `totalSeconds` plus the per-day `records` of a book.
  static Future<void> _addBook(String bookKey, DateTime day, int seconds) => _update(_bookFile(bookKey), (m) {
        final total = _int(m['totalSeconds'] ?? m['seconds']);
        m.remove('seconds');
        final records = m['records'] is Map ? Map<String, dynamic>.from(m['records'] as Map) : <String, dynamic>{};
        final k = dateKey(day);
        records[k] = _int(records[k]) + seconds;
        m['totalSeconds'] = total + seconds;
        m['records'] = records;
      });

  /// Total seconds read in this book.
  static Future<int> bookSeconds(String bookKey) => _readSeconds(_bookFile(bookKey));

  /// Records a reading session of [seconds] for [bookKey], counted on [day] (default today).
  static Future<void> addReading(String bookKey, int seconds, {DateTime? day}) async {
    if (seconds <= 0) return;
    final d = day ?? DateTime.now();
    await _addBook(bookKey, d, seconds);
    await _addDay(d, seconds);
  }

  /// The per-day records of a book (`yyyy-MM-dd` → seconds).
  static Future<Map<String, int>> bookRecords(String bookKey) async {
    final r = (await _readMap(_bookFile(bookKey)))['records'];
    return r is Map ? {for (final e in r.entries) '${e.key}': _int(e.value)} : <String, int>{};
  }

  /// 0x10dfb2c: seconds per day (`yyyy-MM-dd`) of the day files dated after [from] and before [to] + 1 day (dates compared at
  /// midnight, as the original parses the `yyyy-MM-dd` texts). Throws `获取阅读时间范围失败: …` on errors.
  static Future<Map<String, int>> readingTimeRange(DateTime from, DateTime to) async {
    final out = <String, int>{};
    try {
      final dir = Directory(AppDirs.path('reading_time'));
      if (!dir.existsSync()) return out;
      final start = DateTime(from.year, from.month, from.day);
      final end = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
      for (final f in dir.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (!name.endsWith('.json')) continue;
        final stem = name.replaceAll('.json', '');
        if (stem.length != 8) continue;
        final key = '${stem.substring(0, 4)}-${stem.substring(4, 6)}-${stem.substring(6, 8)}';
        final date = DateTime.tryParse(key);
        if (date == null || !date.isAfter(start) || !date.isBefore(end)) continue;
        final m = await _readMap(f.path);
        if (m.isEmpty) continue;
        out[key] = _int(m['seconds']);
      }
    } catch (e) {
      throw Exception('获取阅读时间范围失败: $e');
    }
    return out;
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
