// pages/read/pages/cachebook.dart — the cache progress dialog (original `_CacheBookProgressDialoggState` [sic]); it follows the task of
// one book in `DownNotificationHelper`.
import 'package:flutter/material.dart';

import '../../../read/util/down_notification.dart';

class CacheBookProgressDialog extends StatefulWidget {
  final String bookUrl;
  const CacheBookProgressDialog({super.key, required this.bookUrl});

  static Future<void> show(BuildContext context, String bookUrl) =>
      showDialog<void>(context: context, builder: (_) => CacheBookProgressDialog(bookUrl: bookUrl));

  @override
  State<CacheBookProgressDialog> createState() => _CacheBookProgressDialoggState();
}

class _CacheBookProgressDialoggState extends State<CacheBookProgressDialog> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, DownTask>>(
      valueListenable: DownNotificationHelper.instance.tasks,
      builder: (context, tasks, _) {
        final t = tasks[widget.bookUrl];
        final p = t == null || t.total == 0 ? null : t.done / t.total;
        return AlertDialog(
          title: Text(t?.bookName ?? ''),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: t?.finished == true ? 1 : p),
            const SizedBox(height: 8),
            Text(t?.text ?? '准备缓存...'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
        );
      },
    );
  }
}
