// pages/reading_statistics_page.dart — 阅读统计 (`ReadingStatisticsPage`, 15 functions), from storage/book_reading_time_storage.dart:
// 累计时长 (all daily files; `小时` / `分钟`), 在读书籍 n 本 (books with a reading-time file), and 近30日阅读记录 as a bar chart with
// `月` / `日` labels. Load failures: `加载累计阅读时间失败: …`, `加载在读书籍数量失败: …`, `加载近30天阅读记录失败: …`,
// `获取阅读时间范围失败: …`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../common/app_dirs.dart';
import '../storage/book_reading_time_storage.dart';
import '../util/toast.dart';

class ReadingStats {
  final int totalSeconds;
  final int books;

  /// Oldest first, 30 entries.
  final List<(DateTime, int)> days;
  const ReadingStats(this.totalSeconds, this.books, this.days);

  static int _seconds(File f) {
    try {
      final v = jsonDecode(f.readAsStringSync());
      if (v is Map) return int.tryParse('${v['seconds'] ?? 0}') ?? 0;
    } catch (_) {}
    return 0;
  }

  static Future<ReadingStats> load({DateTime? today}) async {
    var total = 0;
    try {
      final d = AppDirs.dir('reading_time');
      if (d.existsSync()) {
        for (final f in d.listSync().whereType<File>()) {
          if (p.extension(f.path) == '.json') total += _seconds(f);
        }
      }
    } catch (e) {
      Toast.show('加载累计阅读时间失败: $e', iserror: true);
    }
    var books = 0;
    try {
      final d = AppDirs.dir('book_reading_time');
      if (d.existsSync()) books = d.listSync().whereType<File>().where((f) => _seconds(f) > 0).length;
    } catch (e) {
      Toast.show('加载在读书籍数量失败: $e', iserror: true);
    }
    final days = <(DateTime, int)>[];
    try {
      final t = today ?? DateTime.now();
      for (var i = 29; i >= 0; i--) {
        final d = DateTime(t.year, t.month, t.day - i);
        days.add((d, await BookReadingTimeStorage.daySeconds(d)));
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              Row(children: [
                _tile('累计时长', s.totalSeconds >= 3600 ? (s.totalSeconds / 3600).toStringAsFixed(1) : '${s.totalSeconds ~/ 60}', s.totalSeconds >= 3600 ? '小时' : '分钟'),
                _tile('在读书籍', '${s.books}', '本'),
              ]),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('近30日阅读记录', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    SizedBox(height: 180, child: CustomPaint(size: Size.infinite, painter: _BarsPainter(s.days, cs.primary, cs.outline))),
                    const SizedBox(height: 8),
                    if (s.days.isNotEmpty)
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('${s.days.first.$1.month}月${s.days.first.$1.day}日', style: TextStyle(fontSize: 11, color: cs.outline)),
                        Text('${s.days.last.$1.month}月${s.days.last.$1.day}日', style: TextStyle(fontSize: 11, color: cs.outline)),
                      ]),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              for (final d in s.days.reversed.where((e) => e.$2 > 0))
                ListTile(dense: true, title: Text('${d.$1.month}月${d.$1.day}日'), trailing: Text(formatDuration(d.$2))),
            ]),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<(DateTime, int)> days;
  final Color color;
  final Color axis;
  _BarsPainter(this.days, this.color, this.axis);

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final maxV = days.map((e) => e.$2).fold<int>(0, (a, b) => b > a ? b : a);
    final w = size.width / days.length;
    final paint = Paint()..color = color;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = axis.withValues(alpha: 0.4));
    if (maxV == 0) return;
    for (var i = 0; i < days.length; i++) {
      final h = (days[i].$2 / maxV) * (size.height - 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(i * w + w * 0.15, size.height - h, w * 0.7, h), const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.days != days || old.color != color;
}
