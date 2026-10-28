// read/util/down_notification.dart — progress of the chapter downloads ("批量下载" / "缓存章节").
//
// Original: `DownNotificationHelper` (`Common.notificationHelper` 0x3bf8, flutter_local_notifications with a background tap handler
// `notificationTapBackground` 0x530718) posts a system notification with the progress of every `CacheBook` task and bumps
// `Common.floatingnoticy` for the floating notice. The progress per book is kept in [tasks] (listenable for the 缓存 page) and sent to
// [sink] — by default [LocalNotificationSink] (one notification per book, silent updates, removed when the task is gone).
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

/// Where the progress goes (a system notification by default; tests use a fake).
abstract class DownSink {
  Future<void> show(DownTask t);
  Future<void> remove(String bookUrl);
}

class DownNotificationHelper {
  static final DownNotificationHelper instance = DownNotificationHelper._();
  DownNotificationHelper._();

  final ValueNotifier<Map<String, DownTask>> tasks = ValueNotifier<Map<String, DownTask>>({});

  /// The system notification (null = only the in-app list).
  DownSink? sink = kIsWeb ? null : LocalNotificationSink();

  void update(DownTask t) {
    tasks.value = {...tasks.value, t.bookUrl: t};
    Common.floatingnoticy.value++;
    sink?.show(t).catchError((_) {});
  }

  void remove(String bookUrl) {
    final m = {...tasks.value}..remove(bookUrl);
    tasks.value = m;
    Common.floatingnoticy.value++;
    sink?.remove(bookUrl).catchError((_) {});
  }
}

/// flutter_local_notifications: initialised on first use; the notification id is derived from the book url.
class LocalNotificationSink implements DownSink {
  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  Future<bool?>? _init;

  Future<void> _ensure() => _init ??= _p.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestSoundPermission: false, requestBadgePermission: false),
        ),
      );

  static int idOf(String bookUrl) => bookUrl.hashCode & 0x7fffffff;

  @override
  Future<void> show(DownTask t) async {
    await _ensure();
    await _p.show(
      id: idOf(t.bookUrl),
      title: t.bookName,
      body: t.finished ? (t.failed > 0 ? '缓存加载完成，失败 ${t.failed} 章' : '缓存加载完成') : '缓存中 ${t.done}/${t.total}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'cachebook',
          '缓存进度',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: !t.finished,
          maxProgress: t.total,
          progress: t.done,
        ),
        iOS: const DarwinNotificationDetails(presentSound: false, presentBadge: false),
      ),
    );
  }

  @override
  Future<void> remove(String bookUrl) async {
    await _ensure();
    await _p.cancel(id: idOf(bookUrl));
  }
}
