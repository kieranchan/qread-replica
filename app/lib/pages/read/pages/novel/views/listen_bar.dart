// pages/read/pages/novel/views/listen_bar.dart — the read-aloud bar shown at the bottom of the reader while reading aloud (original:
// the listen menu of `_NovelViewState`, `_listenMenuAnimationController`): previous / pause-resume / next paragraph, speed, stop timer,
// open the full listen page, stop.
import 'package:flutter/material.dart';

import '../../../listen_page.dart';
import '../../../read_aloud.dart';
import 'reader_host.dart';

/// "定时停止": the minutes offered by the timer sheet.
const List<int> listenTimerChoices = [15, 30, 45, 60, 90, 120];

Future<void> showListenTimer(BuildContext context, ReadAloudController c) async {
  if (c.stopAt != null) {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消定时'),
        content: const Text('当前已设置定时，是否确认要取消定时？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (cancel == true) c.setTimer(0);
    return;
  }
  if (!context.mounted) return;
  final m = await showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('定时停止')),
        for (final m in listenTimerChoices) ListTile(title: Text('$m 分钟'), onTap: () => Navigator.pop(ctx, m)),
      ]),
    ),
  );
  if (m != null) c.setTimer(m);
}

String formatLeft(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class ListenBar extends StatelessWidget {
  final ReadAloudController controller;
  final ReaderHost host;

  const ListenBar({super.key, required this.controller, required this.host});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final left = c.timerLeft;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Text('语速'),
                Expanded(
                  child: Slider(value: c.rate.clamp(0.2, 3.0), min: 0.2, max: 3.0, divisions: 28, label: c.rate.toStringAsFixed(1), onChanged: c.setRate),
                ),
                Text(c.rate.toStringAsFixed(1)),
              ]),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(tooltip: '上一段', icon: const Icon(Icons.skip_previous), onPressed: c.prevSegment),
                  IconButton(
                    tooltip: c.paused ? '继续' : '暂停',
                    icon: Icon(c.paused ? Icons.play_arrow : Icons.pause),
                    onPressed: c.paused ? c.resume : c.pause,
                  ),
                  IconButton(tooltip: '下一段', icon: const Icon(Icons.skip_next), onPressed: c.nextSegment),
                  TextButton.icon(
                    icon: const Icon(Icons.timer_outlined),
                    label: Text(left == null ? '定时' : formatLeft(left)),
                    onPressed: () => showListenTimer(context, c),
                  ),
                  IconButton(
                    tooltip: '听书',
                    icon: const Icon(Icons.headphones),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ListenPage(controller: c, bookName: host.book.name, coverUrl: host.book.coverUrl)),
                    ),
                  ),
                  IconButton(tooltip: '退出', icon: const Icon(Icons.stop_circle_outlined), onPressed: c.stop),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
