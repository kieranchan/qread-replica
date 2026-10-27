// widget/book/addset.dart — `AddConfigDialog`: 「添加配置」 sheet of the shelf's 更多 menu (sub_86cdd0): import replace rules,
// TTS engines … from a file, a link or a QR code. The import itself belongs to the areas that own those stores; the shelf
// forwards the choice through `Nav.openNamed(context, 'config_import', arguments: {'type': 'file'|'url'|'qr'})`.
import 'package:flutter/material.dart';

import 'addbook.dart';

enum AddConfigType { file, url, qr }

class AddConfigResult {
  final AddConfigType type;
  const AddConfigResult(this.type);
}

class AddConfigDialog extends StatefulWidget {
  const AddConfigDialog({super.key});

  static Future<AddConfigResult?> show(BuildContext context) =>
      showModalBottomSheet<AddConfigResult>(context: context, isScrollControlled: true, builder: (_) => const AddConfigDialog());

  @override
  State<AddConfigDialog> createState() => _AddConfigDialogState();
}

class _AddConfigDialogState extends State<AddConfigDialog> {
  void _pick(AddConfigType t) => Navigator.of(context).pop(AddConfigResult(t));

  @override
  Widget build(BuildContext context) {
    return ImportSheet(icon: Icons.settings, title: '添加配置', subtitle: '支持导入替换净化，朗读引擎等', options: [
      ImportOption(icon: Icons.folder_open, title: '文件导入', subtitle: '从设备中选择配置文件', onTap: () => _pick(AddConfigType.file)),
      ImportOption(icon: Icons.link, title: '网络导入', subtitle: '通过链接下载配置文件', onTap: () => _pick(AddConfigType.url)),
      ImportOption(icon: Icons.qr_code_scanner, title: '扫码导入', subtitle: '扫描二维码导入配置', onTap: () => _pick(AddConfigType.qr)),
    ]);
  }
}
