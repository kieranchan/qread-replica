// pages/webdav/webdav_browser_page.dart — `<name> - 文件浏览` (`WebDavBrowserPage` + `_DirectoryPickerDialogState`, 67 functions): folders
// first (`加载文件中...`, `当前目录为空`), per entry 打开 (books only: `是否要打开文件 x`, others `暂不支持打开非书本文件`) / 下载文件
// (`正在下载: …`, `下载文件失败: …`) / 复制路径 (`路径已复制到剪贴板`) / 重命名 (新名称, `名称不能为空`, `重命名成功` / `重命名失败: …`) /
// 移动 (directory picker 选择 → `移动成功` / `移动失败: …`) / 删除 (`确定要删除 x 吗？` → `删除成功` / `删除失败: …`), and the recursive
// search `输入关键词，搜索当前目录及其所有子目录` (`已扫描 n 个目录...`, `找到 n 个结果`, `未找到匹配的文件`). Downloaded books land in
// `<root>/books` and go to [WebDavBrowserPage.openBook] (the reading core imports / opens them).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../common/app_dirs.dart';
import '../../data/cloud/cloud_drive.dart';
import '../../models/webdavserver.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';

class WebDavBrowserPage extends StatefulWidget {
  final WebDavServer server;
  final CloudDrive? drive;
  const WebDavBrowserPage({super.key, required this.server, this.drive});

  /// Opens / imports a downloaded book (wired by the lead to the reading core). Default: keep the file.
  static Future<void> Function(BuildContext context, File file) openBook = (_, _) async {};

  @override
  State<WebDavBrowserPage> createState() => _WebDavBrowserPageState();
}

class _WebDavBrowserPageState extends State<WebDavBrowserPage> {
  late final CloudDrive _d = widget.drive ?? CloudDrive.of(widget.server);
  String _path = '/';
  List<CloudFile>? _items;
  String _error = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load('/');
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _items = null;
      _error = '';
    });
    try {
      final l = await _d.list(path);
      if (mounted) setState(() => _items = l);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String get _parent {
    final t = _path.endsWith('/') && _path.length > 1 ? _path.substring(0, _path.length - 1) : _path;
    final i = t.lastIndexOf('/');
    return i <= 0 ? '/' : '${t.substring(0, i)}/';
  }

  Future<File?> _download(CloudFile f) async {
    setState(() => _status = '正在下载: ${f.name}');
    try {
      final data = await _d.read(f.path, onProgress: (c, t) {
        if (t > 0 && mounted) setState(() => _status = '正在下载: ${f.name} ${(c * 100 / t).toStringAsFixed(0)}%');
      });
      final dir = await AppDirs.ensure('books');
      final out = File(p.join(dir.path, f.name));
      await out.writeAsBytes(data, flush: true);
      return out;
    } catch (e) {
      Toast.show('下载文件失败: $e', iserror: true);
      return null;
    } finally {
      if (mounted) setState(() => _status = '');
    }
  }

  Future<void> _open(CloudFile f) async {
    if (f.isDir) return _load(f.path);
    if (!f.isBook) return Toast.show('暂不支持打开非书本文件');
    if (!await Dialogs.confirm(context, '打开文件', '是否要打开文件 ${f.name}')) return;
    final file = await _download(f);
    if (file != null && mounted) await WebDavBrowserPage.openBook(context, file);
  }

  Future<void> _rename(CloudFile f) async {
    final name = await Dialogs.input(context, '重命名', hint: '新名称', initial: f.name);
    if (name == null) return;
    if (name.trim().isEmpty) return Toast.show('名称不能为空', iserror: true);
    try {
      final base = f.path.endsWith('/') ? f.path.substring(0, f.path.length - 1) : f.path;
      final dir = base.substring(0, base.lastIndexOf('/') + 1);
      await _d.rename(f.path, '$dir${name.trim()}${f.isDir ? '/' : ''}');
      Toast.show('重命名成功');
    } catch (e) {
      Toast.show('重命名失败: $e', iserror: true);
    }
    await _load(_path);
  }

  Future<void> _move(CloudFile f) async {
    final target = await showDialog<String>(context: context, builder: (_) => _DirectoryPickerDialog(drive: _d, start: _path));
    if (target == null) return;
    try {
      await _d.rename(f.path, '$target${f.name}${f.isDir ? '/' : ''}');
      Toast.show('移动成功');
    } catch (e) {
      Toast.show('移动失败: $e', iserror: true);
    }
    await _load(_path);
  }

  Future<void> _delete(CloudFile f) async {
    if (!await Dialogs.confirm(context, '删除确认', '确定要删除 ${f.name} 吗？', danger: true)) return;
    try {
      await _d.remove(f.path);
      Toast.show('删除成功');
    } catch (e) {
      Toast.show('删除失败: $e', iserror: true);
    }
    await _load(_path);
  }

  Future<void> _search() async {
    final k = await Dialogs.input(context, '搜索', hint: '输入关键词，搜索当前目录及其所有子目录');
    if (k == null || k.trim().isEmpty) return;
    setState(() => _status = '已扫描 0 个目录...');
    final r = await _d.search(_path, k.trim(), onDir: (n) {
      if (mounted) setState(() => _status = '已扫描 $n 个目录...');
    });
    if (!mounted) return;
    setState(() => _status = '');
    if (r.isEmpty) return Toast.show('未找到匹配的文件');
    Toast.show('找到 ${r.length} 个结果');
    setState(() => _items = r);
  }

  Widget _tile(CloudFile f) {
    return ListTile(
      leading: Icon(f.isDir ? Icons.folder_outlined : (f.isBook ? Icons.menu_book_outlined : Icons.insert_drive_file_outlined)),
      title: Text(f.name),
      subtitle: f.isDir ? null : Text(formatBytes(f.size)),
      onTap: () => _open(f),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'download':
              final file = await _download(f);
              if (file != null) Toast.show('已下载到 ${file.path}');
            case 'copy':
              await Clipboard.setData(ClipboardData(text: f.path));
              Toast.show('路径已复制到剪贴板');
            case 'rename':
              await _rename(f);
            case 'move':
              await _move(f);
            case 'delete':
              await _delete(f);
          }
        },
        itemBuilder: (_) => [
          if (!f.isDir) const PopupMenuItem(value: 'download', child: Text('下载文件')),
          const PopupMenuItem(value: 'copy', child: Text('复制路径')),
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          const PopupMenuItem(value: 'move', child: Text('移动')),
          const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _path == '/',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _load(_parent);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.server.name} - 文件浏览'),
          actions: [IconButton(tooltip: '搜索', icon: const Icon(Icons.search), onPressed: _search)],
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.surfaceContainerHighest,
            child: Text(_path, style: const TextStyle(fontSize: 12)),
          ),
          if (_status.isNotEmpty) ...[const LinearProgressIndicator(), Text(_status, style: const TextStyle(fontSize: 12))],
          Expanded(
            child: _error.isNotEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center)))
                : items == null
                    ? const Center(child: Text('加载文件中...'))
                    : RefreshIndicator(
                        onRefresh: () => _load(_path),
                        child: items.isEmpty
                            ? ListView(children: const [SizedBox(height: 120), Center(child: Text('当前目录为空'))])
                            : ListView(children: [
                                if (_path != '/') ListTile(leading: const Icon(Icons.arrow_upward), title: const Text('..'), onTap: () => _load(_parent)),
                                for (final f in items) _tile(f),
                              ]),
                      ),
          ),
        ]),
      ),
    );
  }
}

/// 移动 target picker (`_DirectoryPickerDialogState`): folders only, returns the chosen folder path.
class _DirectoryPickerDialog extends StatefulWidget {
  final CloudDrive drive;
  final String start;
  const _DirectoryPickerDialog({required this.drive, required this.start});

  @override
  State<_DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<_DirectoryPickerDialog> {
  late String _path = widget.start;
  List<CloudFile>? _dirs;

  @override
  void initState() {
    super.initState();
    _load(_path);
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _dirs = null;
    });
    try {
      final l = (await widget.drive.list(path)).where((f) => f.isDir).toList();
      if (mounted) setState(() => _dirs = l);
    } catch (_) {
      if (mounted) setState(() => _dirs = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirs = _dirs;
    return AlertDialog(
      title: Text('目录 $_path', style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: dirs == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                if (_path != '/')
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('..'),
                    onTap: () {
                      final t = _path.substring(0, _path.length - 1);
                      final i = t.lastIndexOf('/');
                      _load(i <= 0 ? '/' : '${t.substring(0, i)}/');
                    },
                  ),
                for (final d in dirs) ListTile(leading: const Icon(Icons.folder_outlined), title: Text(d.name), onTap: () => _load(d.path)),
                if (dirs.isEmpty) Center(child: Text('${dirs.length} 个目录')),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.of(context).pop(_path), child: const Text('选择')),
      ],
    );
  }
}
