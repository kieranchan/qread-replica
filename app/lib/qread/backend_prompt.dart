// qread/backend_prompt.dart — 书源解析服务提示 (original util/util.dart 0x1c780c): what the app says when an 开源阅读 (Legado) feature
// needs the bound 轻阅读后端 and none is bound. The original's 查看搭建文档 button opened its hosting guide; the replica has no such
// page, so the dialog explains and offers to open 后端绑定 instead.
import 'package:flutter/material.dart';

import '../common/nav.dart';

abstract class BackendPrompt {
  static const String title = '书源解析服务提示';
  static const String message = '开源阅读书源需要借助轻阅读后端进行解析，请先在书源设置中绑定轻阅读后端！';
  static const List<String> notes = [
    '• 轻阅读通过将阅读安卓代码做成Java服务端来支持阅读书源',
    '• 后端服务需要您自行搭建',
    '• 不会搭建？您可以使用轻悦时光书源（无需任何外部支持）',
  ];

  /// Shows the prompt; true when the user chose to go to 后端绑定 (the caller opens `qread_login`).
  static Future<bool> show(BuildContext context) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(message),
              const SizedBox(height: 12),
              const Text('轻阅读后端说明：', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(n, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('知道了')),
          TextButton(key: const Key('backend_prompt_bind'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('去绑定')),
        ],
      ),
    );
    return r == true;
  }

  /// The prompt followed by the 后端绑定 page when asked for.
  static Future<void> showAndBind(BuildContext context) async {
    if (!await show(context)) return;
    if (context.mounted) await Nav.openNamed(context, 'qread_login');
  }
}
