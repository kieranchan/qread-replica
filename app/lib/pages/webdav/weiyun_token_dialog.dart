// pages/webdav/weiyun_token_dialog.dart — 腾讯微云 API Key (`WeiyunTokenDialog`, 20 functions): 名称, the key field (`粘贴微云授权页面生成的
// API Key`, 粘贴 / `剪贴板中没有内容`), `请先在微云授权页面用微信或 QQ 登录，获取 API Key 后粘贴到下方。`; 校验 fails with `校验失败：…`
// (`API Key 无效或已过期，请重新获取`). The Weiyun API is not available in this build: the key can be stored, browsing reports
// `当前版本不支持腾讯微云`. Returns the saved server or null.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/cloud/cloud_drive.dart';
import '../../data/cloud/weiyun/weiyun_drive.dart';
import '../../data/webdav.dart';
import '../../models/webdavserver.dart';
import '../../util/toast.dart';

class WeiyunTokenDialog extends StatefulWidget {
  final WebDavServer? server;
  const WeiyunTokenDialog({super.key, this.server});

  static Future<WebDavServer?> show(BuildContext context, {WebDavServer? server}) =>
      showDialog<WebDavServer>(context: context, builder: (_) => WeiyunTokenDialog(server: server));

  @override
  State<WeiyunTokenDialog> createState() => _WeiyunTokenDialogState();
}

class _WeiyunTokenDialogState extends State<WeiyunTokenDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.server?.name ?? '腾讯微云');
  late final TextEditingController _key = TextEditingController(text: widget.server?.accessToken ?? '');

  Future<void> _save() async {
    if (_key.text.trim().isEmpty) return Toast.show('请先填写 API Key', iserror: true);
    final s = WebDavServer(
      id: widget.server?.id ?? '',
      name: _name.text.trim().isEmpty ? '腾讯微云' : _name.text.trim(),
      type_: CloudDrive.typeWeiyun,
      accessToken: _key.text.trim(),
    );
    final saved = widget.server == null ? await WebDav.add(s) : (await WebDav.update(s).then((_) => s));
    Toast.show('校验失败：${WeiyunDrive.unsupported}');
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('腾讯微云'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('请先在微云授权页面用微信或 QQ 登录，获取 API Key 后粘贴到下方。', style: TextStyle(fontSize: 13)),
        TextField(controller: _name, decoration: const InputDecoration(labelText: '名称')),
        TextField(
          controller: _key,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: '粘贴微云授权页面生成的 API Key',
            suffixIcon: TextButton(
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if ((d?.text ?? '').trim().isEmpty) return Toast.show('剪贴板中没有内容', iserror: true);
                _key.text = d!.text!.trim();
              },
              child: const Text('粘贴'),
            ),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
