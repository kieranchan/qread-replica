// read/util/down_notification.dart — progress of the chapter downloads ("批量下载" / "缓存章节").
//
// Original: `DownNotificationHelper` (`Common.notificationHelper` 0x3bf8) posts a system notification with the progress of every
// `CacheBook` task and bumps `Common.floatingnoticy` for the floating notice. No notification plugin is bundled here: the helper keeps
// the progress per book in [tasks] (listenable), the floating notice / download manager can show it, and [sink] can be pointed at a
// system notification by the app. TODO(asm down_notification.dart): system notifications.
import 'package:flutter/foundation.dart';

import '../../common/common.dart';

class DownTask {
  final String bookUrl;
  final String bookName;
  final int done;
  final int total;
  final bool finished;
  final int failed;

  const DownTask(this.bookUrl, this.bookName, this.done, this.total, {this.finished = false, this.failed = 0});

  String get text => finished ? '缓存加载完成' : '$bookName 缓存中 $done/$total';
}

class DownNotificationHelper {
  static final DownNotificationHelper instance = DownNotificationHelper._();
  DownNotificationHelper._();

  final ValueNotifier<Map<String, DownTask>> tasks = ValueNotifier<Map<String, DownTask>>({});

  /// Optional system notification hook.
  void Function(DownTask task)? sink;

  void update(DownTask t) {
    tasks.value = {...tasks.value, t.bookUrl: t};
    Common.floatingnoticy.value++;
    sink?.call(t);
  }

  void remove(String bookUrl) {
    final m = {...tasks.value}..remove(bookUrl);
    tasks.value = m;
    Common.floatingnoticy.value++;
  }
}
