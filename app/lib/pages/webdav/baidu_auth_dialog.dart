// pages/webdav/baidu_auth_dialog.dart — 百度网盘 device-code login (`BaiduAuthDialog`, 20 functions: `正在获取授权码...`, QR code /
// `用户码` + `复制用户码` / `打开授权页`, `等待用户授权...`, `授权超时，请重新获取授权码`, `授权返回的凭证不完整，请重试`). The login needs the
// original developer's Baidu app key, which this build does not ship, so the dialog stops at `获取授权码失败` with the reason and a
// 重新获取 button. Returns null (nothing is added).
import 'package:flutter/material.dart';

import '../../data/cloud/baidu/baidu_drive.dart';

class BaiduAuthDialog extends StatefulWidget {
  const BaiduAuthDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(context: context, builder: (_) => const BaiduAuthDialog());

  @override
  State<BaiduAuthDialog> createState() => _BaiduAuthDialogState();
}

class _BaiduAuthDialogState extends State<BaiduAuthDialog> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _request();
  }

  Future<void> _request() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('百度网盘'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_loading) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          const Text('正在获取授权码...'),
        ] else ...[
          Icon(Icons.error_outline, size: 40, color: cs.error),
          const SizedBox(height: 8),
          const Text('获取授权码失败'),
          const SizedBox(height: 4),
          Text(BaiduDrive.unsupported, style: TextStyle(fontSize: 12, color: cs.outline), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('用百度网盘 App 扫码，或打开授权页输入用户码', style: TextStyle(fontSize: 12, color: cs.outline)),
        ],
      ]),
      actions: [
        TextButton(onPressed: _loading ? null : _request, child: const Text('重新获取')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
      ],
    );
  }
}
