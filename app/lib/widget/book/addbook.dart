// widget/book/addbook.dart — `AddBookDialog`: 「添加书籍」 sheet of the shelf's 更多 menu (sub_86af78), returning an
// [AddBookResult] with the chosen import way.
import 'package:flutter/material.dart';

enum AddBookType { local, backend, remote, backup, progress, url }

class AddBookResult {
  final AddBookType type;
  const AddBookResult(this.type);
}

/// One row of the import sheets (icon, title, subtitle).
class ImportOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const ImportOption({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: scheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Header + options + 取消, shared by [AddBookDialog] and `AddConfigDialog`.
class ImportSheet extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> options;

  const ImportSheet({super.key, required this.icon, required this.title, required this.subtitle, required this.options});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          ...options,
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        ]),
      ),
    );
  }
}

class AddBookDialog extends StatefulWidget {
  const AddBookDialog({super.key});

  static Future<AddBookResult?> show(BuildContext context) =>
      showModalBottomSheet<AddBookResult>(context: context, isScrollControlled: true, builder: (_) => const AddBookDialog());

  @override
  State<AddBookDialog> createState() => _AddBookDialogState();
}

class _AddBookDialogState extends State<AddBookDialog> {
  void _pick(AddBookType t) => Navigator.of(context).pop(AddBookResult(t));

  @override
  Widget build(BuildContext context) {
    return ImportSheet(icon: Icons.library_add, title: '添加书籍', subtitle: '选择您喜欢的导入方式', options: [
      ImportOption(key: const Key('add_local'), icon: Icons.folder_open, title: '本地导入', subtitle: '从设备中选择书籍文件', onTap: () => _pick(AddBookType.local)),
      ImportOption(key: const Key('add_backend'), icon: Icons.dns_outlined, title: '导入后端', subtitle: '需要轻阅读后端允许导入', onTap: () => _pick(AddBookType.backend)),
      ImportOption(key: const Key('add_remote'), icon: Icons.link, title: '远程导入', subtitle: '通过链接在电脑端导入', onTap: () => _pick(AddBookType.remote)),
      ImportOption(key: const Key('add_backup'), icon: Icons.cloud_download, title: '备份导入', subtitle: '从云端备份恢复书籍', onTap: () => _pick(AddBookType.backup)),
      ImportOption(key: const Key('add_progress'), icon: Icons.pending, title: '进度导入', subtitle: '批量更新书籍阅读进度', onTap: () => _pick(AddBookType.progress)),
      ImportOption(key: const Key('add_url'), icon: Icons.language, title: '网址导入', subtitle: '通过网址链接导入书籍', onTap: () => _pick(AddBookType.url)),
    ]);
  }
}
