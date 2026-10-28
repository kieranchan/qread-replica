// pages/reading_statistics_page.dart — 阅读统计 (`ReadingStatisticsPage`, 15 functions; build 0x7ef744, loader 0x10df3a8) as the original:
//   累计时长   0x10df938: the sum of `readingTimeRange(now - 30 days, now)` (storage/book_reading_time_storage.dart, 0x10dfb2c)
//   在读书籍   0x10e02f0: shelf books with `type != 1` and `durChapterIndex < totalChapterNum` (closure 0x925fc0), `本`
//   近30日阅读记录 0x10df4f4: the 30 days up to today labelled `M月d日`, rows sorted newest first (0x7f0b0c); each row (0x7f04c8) =
//              80 px date, a 24 px bar whose length is minutes / 480 (at least 0.05), 60 px `n分钟`.
// Load failures: `加载累计阅读时间失败: …`, `加载在读书籍数量失败: …`, `加载近30天阅读记录失败: …`, `加载阅读统计数据失败: …`.
import 'package:flutter/material.dart';

import '../data/bookself.dart';
import '../models/book.dart';
import '../storage/book_reading_time_storage.dart';
import '../util/toast.dart';

class ReadingStats {
  final int totalSeconds;
  final int books;

  /// Oldest first, 30 entries (today last).
  final List<(DateTime, int)> days;
  const ReadingStats(this.totalSeconds, this.books, this.days);

  /// 0x925fc0.
  static bool inProgress(Book b) => b.type_ != 1 && b.durChapterIndex < b.totalChapterNum;

  static Future<ReadingStats> load({DateTime? today}) async {
    final now = today ?? DateTime.now();
    var total = 0;
    try {
      final m = await BookReadingTimeStorage.readingTimeRange(now.subtract(const Duration(days: 30)), now);
      m.forEach((_, v) => total += v);
    } catch (e) {
      Toast.show('加载累计阅读时间失败: $e', iserror: true);
    }
    var books = 0;
    try {
      books = (await Bookdata.load()).where(inProgress).length;
    } catch (e) {
      Toast.show('加载在读书籍数量失败: $e', iserror: true);
    }
    final days = <(DateTime, int)>[];
    try {
      final range = await BookReadingTimeStorage.readingTimeRange(DateTime(now.year, now.month, now.day - 30), now);
      for (var i = 29; i >= 0; i--) {
        final d = DateTime(now.year, now.month, now.day - i);
        days.add((d, range[BookReadingTimeStorage.dateKey(d)] ?? 0));
      }
    } catch (e) {
      Toast.show('加载近30天阅读记录失败: $e', iserror: true);
    }
    return ReadingStats(total, books, days);
  }
}

String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  if (m < 60) return '$m分钟';
  return '${m ~/ 60}小时${m % 60 > 0 ? '${m % 60}分钟' : ''}';
}

class ReadingStatisticsPage extends StatefulWidget {
  const ReadingStatisticsPage({super.key});

  @override
  State<ReadingStatisticsPage> createState() => _ReadingStatisticsPageState();
}

class _ReadingStatisticsPageState extends State<ReadingStatisticsPage> {
  ReadingStats? _s;

  @override
  void initState() {
    super.initState();
    ReadingStats.load().then((s) {
      if (mounted) setState(() => _s = s);
    });
  }

  Widget _tile(String label, String value, String unit) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: cs.outline)),
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              TextSpan(text: value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              TextSpan(text: ' $unit', style: TextStyle(color: cs.outline)),
            ])),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              Row(children: [
                _tile('累计时长', s.totalSeconds >= 3600 ? (s.totalSeconds / 3600).toStringAsFixed(1) : '${s.totalSeconds ~/ 60}', s.totalSeconds >= 3600 ? '小时' : '分钟'),
                _tile('在读书籍', '${s.books}', '本'),
              ]),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('近30日阅读记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              for (final d in s.days.reversed) _row(d.$1, d.$2),
            ]),
    );
  }

  /// 0x7f04c8.
  Widget _row(DateTime day, int seconds) {
    final cs = Theme.of(context).colorScheme;
    final minutes = seconds ~/ 60;
    return Container(
      key: Key('stat_${day.month}_${day.day}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 80, child: Text('${day.month}月${day.day}日', style: const TextStyle(fontSize: 14))),
        Expanded(
          child: Stack(children: [
            Container(height: 24, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12))),
            FractionallySizedBox(
              widthFactor: (minutes / 480).clamp(0.05, 1.0).toDouble(),
              child: Container(height: 24, decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12))),
            ),
          ]),
        ),
        Container(width: 60, alignment: Alignment.centerRight, child: Text('$minutes分钟', style: const TextStyle(fontSize: 14))),
      ]),
    );
  }
}
