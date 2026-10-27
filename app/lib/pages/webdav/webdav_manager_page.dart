// pages/webdav/webdav_manager_page.dart — 网盘管理 (`WebDavManagerPage`, 31 functions): the servers of data/webdav.dart. Member-only:
// adding and browsing show `网盘为会员独享功能！`. 添加网盘 offers WebDAV (`群晖、坚果云、Alist 等`), CloudDrive2 (`聚合 115、阿里云盘、天翼等，
// 填地址即可`), 百度网盘 (`需扫码授权登录`) and 腾讯微云 (`填入 API Key 即可`). WebDAV form: 添加 / 编辑 WebDAV 服务器, 服务器名称,
// 服务器地址, 用户名, 密码 (`服务器名称和地址不能为空`). Each server: 浏览, 编辑 (重新授权 / 更新 Key for Baidu / Weiyun), 删除服务器
// (`确定要删除服务器 "x" 吗？`). Empty: `暂无网盘账号` / `点击下方按钮添加网盘`. Load failure: `加载 WebDAV 服务器失败: …`.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/cloud/cloud_drive.dart';
import '../../data/webdav.dart';
import '../../models/webdavserver.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';
import 'baidu_auth_dialog.dart';
import 'clouddrive2_setup_page.dart';
import 'webdav_browser_page.dart';
import 'weiyun_token_dialog.dart';

class WebDavManagerPage extends StatefulWidget {
  const WebDavManagerPage({super.key});

  static const String vipText = '网盘为会员独享功能！';

  @override
  State<WebDavManagerPage> createState() => _WebDavManagerPageState();
}

class _WebDavManagerPageState extends State<WebDavManagerPage> {
  @override
  void initState() {
    super.initState();
    WebDav.load().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object e) {
      Toast.show('加载 WebDAV 服务器失败: $e', iserror: true);
    });
  }

  Future<void> _add() async {
    if (!Vip.require(WebDavManagerPage.vipText)) return;
    final i = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(12), child: Text('添加网盘', style: TextStyle(fontWeight: FontWeight.w600))),
          ListTile(leading: const Icon(Icons.storage_outlined), title: const Text('WebDAV'), subtitle: const Text('群晖、坚果云、Alist 等'), onTap: () => Navigator.of(ctx).pop(0)),
          ListTile(leading: const Icon(Icons.hub_outlined), title: const Text('CloudDrive2'), subtitle: const Text('聚合 115、阿里云盘、天翼等，填地址即可'), onTap: () => Navigator.of(ctx).pop(1)),
          ListTile(leading: const Icon(Icons.cloud_outlined), title: const Text('百度网盘'), subtitle: const Text('需扫码授权登录'), onTap: () => Navigator.of(ctx).pop(2)),
          ListTile(leading: const Icon(Icons.cloud_circle_outlined), title: const Text('腾讯微云'), subtitle: const Text('填入 API Key 即可'), onTap: () => Navigator.of(ctx).pop(3)),
        ]),
      ),
    );
    if (!mounted || i == null) return;
    switch (i) {
      case 0:
        await _webdavForm();
      case 1:
        await Get.to(() => const CloudDrive2SetupPage());
      case 2:
        await BaiduAuthDialog.show(context);
      case 3:
        await WeiyunTokenDialog.show(context);
    }
    if (mounted) setState(() {});
  }

  Future<void> _webdavForm([WebDavServer? old]) async {
    final name = TextEditingController(text: old?.name ?? '');
    final url = TextEditingController(text: old?.url ?? '');
    final user = TextEditingController(text: old?.username ?? '');
    final pass = TextEditingController(text: old?.password ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? '添加 WebDAV 服务器' : '编辑 WebDAV 服务器'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('wd_name'), controller: name, decoration: const InputDecoration(labelText: '服务器名称', hintText: '输入服务器名称')),
            TextField(key: const Key('wd_url'), controller: url, decoration: const InputDecoration(labelText: '服务器地址', hintText: 'https://dav.example.com/dav/')),
            TextField(key: const Key('wd_user'), controller: user, decoration: const InputDecoration(labelText: '用户名', hintText: '输入用户名')),
            TextField(key: const Key('wd_pass'), controller: pass, obscureText: true, decoration: const InputDecoration(labelText: '密码', hintText: '输入密码')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(key: const Key('wd_save'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty || url.text.trim().isEmpty) return Toast.show('服务器名称和地址不能为空', iserror: true);
    final s = WebDavServer(
      id: old?.id ?? '',
      name: name.text.trim(),
      url: url.text.trim(),
      username: user.text.trim(),
      password: pass.text,
      type_: CloudDrive.typeWebdav,
    );
    if (old == null) {
      await WebDav.add(s);
    } else {
      await WebDav.update(s);
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit(WebDavServer s) async {
    switch (s.type_) {
      case CloudDrive.typeBaidu:
        await BaiduAuthDialog.show(context);
      case CloudDrive.typeWeiyun:
        await WeiyunTokenDialog.show(context, server: s);
      case CloudDrive.typeCloudDrive2:
        await Get.to(() => CloudDrive2SetupPage(server: s));
      default:
        await _webdavForm(s);
    }
    if (mounted) setState(() {});
  }

  Future<void> _delete(WebDavServer s) async {
    if (!await Dialogs.confirm(context, '删除服务器', '确定要删除服务器 "${s.name}" 吗？', danger: true)) return;
    await WebDav.delete(s.id);
    if (mounted) setState(() {});
  }

  void _browse(WebDavServer s) {
    if (!Vip.require(WebDavManagerPage.vipText)) return;
    Get.to(() => WebDavBrowserPage(server: s));
  }

  @override
  Widget build(BuildContext context) {
    final list = WebDav.servers;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('网盘管理')),
      floatingActionButton: FloatingActionButton.extended(key: const Key('wd_add'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('添加网盘')),
      body: list.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_off_outlined, size: 56, color: cs.outline),
                const SizedBox(height: 8),
                const Text('暂无网盘账号'),
                Text('点击下方按钮添加网盘', style: TextStyle(color: cs.outline)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i];
                final label = switch (s.type_) {
                  CloudDrive.typeBaidu => '百度网盘',
                  CloudDrive.typeWeiyun => '腾讯微云',
                  CloudDrive.typeCloudDrive2 => 'CloudDrive2',
                  _ => 'WebDAV',
                };
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: ListTile(
                    key: Key('wd_${s.id}'),
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(s.name),
                    subtitle: Text([label, if (s.url.isNotEmpty) s.url, if (s.username.isNotEmpty) '用户名: ${s.username}'].join('\n')),
                    isThreeLine: s.url.isNotEmpty,
                    onTap: () => _browse(s),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'browse') return _browse(s);
                        v == 'edit' ? _edit(s) : _delete(s);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'browse', child: Text('浏览')),
                        PopupMenuItem(
                            value: 'edit',
                            child: Text(switch (s.type_) { CloudDrive.typeBaidu => '重新授权', CloudDrive.typeWeiyun => '更新 Key', _ => '编辑' })),
                        const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
