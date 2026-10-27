// pages/setting/backup_page.dart — 备份管理 (`BackupPage`, 63 functions). 备份操作: 快速备份 / 完整备份 / 导入备份 (`确认导入`); 自动备份
// (number kept, prefs `autoBackupNum`); 备份历史 (`暂无备份历史` / `点击"快速备份"开始创建备份`) with per item 恢复 (`确认恢复` /
// `确定要恢复此备份吗？这将覆盖当前的所有数据。恢复完成后应用将重启。`, progress `准备恢复...` `读取备份文件...` `应用备份设置...`
// `保存设置...` `完成恢复...` → `即将重启应用`), 导出备份 (share), 删除备份 (`确定要删除备份 "x" 吗？此操作不可恢复。` → `备份删除成功` /
// `删除备份失败：…`). Replica addition: 上传到网盘 / 从网盘恢复 through a WebDAV server of 网盘管理 (data/cloud).
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/cloud/cloud_drive.dart';
import '../../data/webdav.dart';
import '../../models/backup.dart';
import '../../models/webdavserver.dart';
import '../../storage/storage.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import 'backup_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  List<BackupItem> _items = [];
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final l = await BackupService.list();
      if (mounted) setState(() => _items = l);
    } catch (e) {
      Toast.show('解析备份项失败: $e', iserror: true);
    }
  }

  Future<void> _run(String label, Future<void> Function() body) async {
    if (_busy.isNotEmpty) return;
    setState(() => _busy = label);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _backup({required bool quick}) => _run(quick ? '快速备份' : '完整备份', () async {
        try {
          await BackupService.create(name: quick ? '快速备份' : '完整备份', isquick: quick);
          Toast.show('备份成功');
        } on BackupException catch (e) {
          Toast.show('备份失败：${e.message}', iserror: true);
        } catch (e) {
          Toast.show('备份失败：$e', iserror: true);
        }
        await _reload();
      });

  Future<void> _import() async {
    final f = await DeviceIo.pickFile(extensions: const ['zip']);
    if (f == null || !mounted) return;
    if (!await Dialogs.confirm(context, '确认导入', '确定要导入备份 "${f.uri.pathSegments.last}" 吗？')) return;
    try {
      await BackupService.importZip(f);
      Toast.show('导入成功');
    } catch (e) {
      Toast.show('导入备份失败：$e', iserror: true);
    }
    await _reload();
  }

  Future<void> _restore(BackupItem b) async {
    if (!await Dialogs.confirm(context, '确认恢复', '确定要恢复此备份吗？这将覆盖当前的所有数据。恢复完成后应用将重启。', confirmText: '恢复', danger: true)) return;
    await _run('准备恢复...', () async {
      try {
        setState(() => _busy = '读取备份文件...');
        await BackupService.restore(b.path);
        setState(() => _busy = '完成恢复...');
        Toast.show('即将重启应用');
      } on BackupException catch (e) {
        Toast.show(e.message, iserror: true);
      } catch (e) {
        Toast.show('恢复备份失败：$e', iserror: true);
      }
    });
    await _reload();
  }

  Future<void> _delete(BackupItem b) async {
    if (!await Dialogs.confirm(context, '删除备份', '确定要删除备份 "${b.name}" 吗？此操作不可恢复。', confirmText: '删除', danger: true)) return;
    try {
      await BackupService.delete(b);
      Toast.show('备份删除成功');
    } catch (e) {
      Toast.show('删除备份失败：$e', iserror: true);
    }
    await _reload();
  }

  Future<WebDavServer?> _pickServer() async {
    await WebDav.load();
    final servers = WebDav.servers.where((s) => s.type_.isEmpty || s.type_ == CloudDrive.typeWebdav || s.type_ == CloudDrive.typeCloudDrive2).toList();
    if (servers.isEmpty) {
      Toast.show('请先添加 WebDAV 服务器', iserror: true);
      return null;
    }
    if (servers.length == 1 || !mounted) return servers.first;
    final i = await Dialogs.choose(context, '选择 WebDAV 服务器', [for (final s in servers) s.name.isEmpty ? s.url : s.name]);
    return i == null ? null : servers[i];
  }

  Future<void> _upload(BackupItem b) async {
    final s = await _pickServer();
    if (s == null) return;
    await _run('上传中...', () async {
      try {
        final remote = await BackupService.upload(b, s);
        Toast.show('上传成功：$remote');
      } catch (e) {
        Toast.show('上传失败：$e', iserror: true);
      }
    });
  }

  Future<void> _fromDrive() async {
    final s = await _pickServer();
    if (s == null) return;
    List<CloudFile> files = [];
    await _run('加载中...', () async {
      files = await BackupService.remoteList(s);
    });
    if (!mounted) return;
    if (files.isEmpty) return Toast.show('您还没有备份');
    final i = await Dialogs.choose(context, '从网盘恢复', [for (final f in files) f.name]);
    if (i == null) return;
    await _run('正在下载: ${files[i].name}', () async {
      try {
        await BackupService.download(files[i], s);
        Toast.show('下载完成，可在备份历史中恢复');
      } catch (e) {
        Toast.show('下载文件失败: $e', iserror: true);
      }
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keep = Storage.getInt(BackupService.autoBackupNumKey, 7);
    return Scaffold(
      appBar: AppBar(title: const Text('备份管理')),
      body: Column(children: [
        if (_busy.isNotEmpty) LinearProgressIndicator(semanticsLabel: _busy),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            SectionCard(title: '备份操作', children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton.icon(key: const Key('backup_quick'), onPressed: () => _backup(quick: true), icon: const Icon(Icons.flash_on), label: const Text('快速备份')),
                  FilledButton.tonalIcon(key: const Key('backup_full'), onPressed: () => _backup(quick: false), icon: const Icon(Icons.inventory_2_outlined), label: const Text('完整备份')),
                  OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.file_open_outlined), label: const Text('导入备份')),
                  OutlinedButton.icon(onPressed: _fromDrive, icon: const Icon(Icons.cloud_download_outlined), label: const Text('从网盘恢复')),
                ]),
              ),
              if (_busy.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: Text(_busy, style: TextStyle(color: cs.primary))),
            ]),
            SectionCard(title: '自动备份', children: [
              ListTile(
                title: const Text('保留数量'),
                subtitle: const Text('应用启动时自动备份数据，超出数量的旧备份会被删除'),
                trailing: Text('$keep'),
                onTap: () async {
                  final v = await Dialogs.input(context, '自动备份', initial: '$keep', keyboardType: TextInputType.number);
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 1) return;
                  try {
                    await Storage.setInt(BackupService.autoBackupNumKey, n);
                  } catch (e) {
                    Toast.show('备份设置失败, 错误: $e', iserror: true);
                  }
                  setState(() {});
                },
              ),
            ]),
            SectionCard(title: '备份历史', children: [
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(children: [
                      const Text('暂无备份历史'),
                      Text('点击"快速备份"开始创建备份', style: TextStyle(fontSize: 12, color: cs.outline)),
                    ]),
                  ),
                ),
              for (final b in _items)
                ListTile(
                  key: Key('backup_${b.id}'),
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(b.name),
                  subtitle: Text('${b.date.length >= 19 ? b.date.substring(0, 19).replaceFirst('T', ' ') : b.date} · ${formatBytes(int.tryParse(b.size) ?? 0)}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'restore':
                          await _restore(b);
                        case 'export':
                          await DeviceIo.shareFile(File(b.path));
                        case 'upload':
                          await _upload(b);
                        case 'delete':
                          await _delete(b);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'restore', child: Text('恢复')),
                      PopupMenuItem(value: 'export', child: Text('导出备份')),
                      PopupMenuItem(value: 'upload', child: Text('上传到网盘')),
                      PopupMenuItem(value: 'delete', child: Text('删除备份', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
