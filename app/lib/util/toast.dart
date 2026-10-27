// util/toast.dart — one place that shows short messages ("此功能为会员功能", API errors). Tests replace [Toast.sink].
import 'package:flutter/material.dart';
import 'package:get/get.dart';

abstract class Toast {
  /// Every message also lands in [log] so tests and the debug console can see it.
  static final List<String> log = [];

  static void Function(String message, bool isError) sink = _defaultSink;

  static void show(String message, {bool iserror = false}) {
    log.add(message);
    sink(message, iserror);
  }

  static void _defaultSink(String message, bool isError) {
    BuildContext? ctx;
    try {
      ctx = Get.context;
    } catch (_) {
      return; // no widgets binding (plain Dart tests, background isolates): the message is only logged
    }
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : null,
      duration: const Duration(seconds: 2),
    ));
  }
}
