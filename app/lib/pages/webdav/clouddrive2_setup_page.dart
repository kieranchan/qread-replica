// pages/webdav/clouddrive2_setup_page.dart — CloudDrive2 (`CloudDrive2SetupPage`, 21 functions). CD2 exposes its mounted clouds over
// WebDAV, so the entry is a WebDAV server (type `clouddrive2`) whose url is completed as `http://host:19798/dav` — `端口和 /dav 只在未填写时
// 才补全，自定义端口不受影响` (`实际连接地址：…`). Fields 名称, 服务器地址, CD2 账号 (`登录 CloudDrive2 的邮箱（或 @ 前面的部分）`),
// CD2 密码; 测试连接 → `连接成功，发现 n 个云盘目录` / `连接成功，但还没有挂载任何云盘，请先在 CD2 网页管理里添加云盘` /
// `找不到主机，请检查地址里的 IP 或域名是否正确` / `HTTPS 证书校验失败，…` / `连接失败：…`; 保存 → `CloudDrive2 添加成功` / `已保存`.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/cloud/cloud_drive.dart';
import '../../data/cloud/webdav_drive.dart';
import '../../data/webdav.dart';
import '../../models/webdavserver.dart';
import '../../util/toast.dart';

class CloudDrive2SetupPage extends StatefulWidget {
  final WebDavServer? server;
  const CloudDrive2SetupPage({super.key, this.server});

  static const int defaultPort = 19798;

  /// Completes scheme, port and `/dav` only when missing.
  static String normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null) return s;
    final port = u.hasPort ? u.port : defaultPort;
    final path = (u.path.isEmpty || u.path == '/') ? '/dav' : u.path;
    return u.replace(port: port, path: path).toString();
  }

  /// Message of a connection error.
  static String errorText(Object e) {
    final s = '$e';
    if (s.contains('Failed host lookup') || s.contains('SocketException: Failed host')) return '找不到主机，请检查地址里的 IP 或域名是否正确';
    if (s.contains('HandshakeException') || s.contains('CERTIFICATE')) return 'HTTPS 证书校验失败，自签名证书请改用 http 地址或配置受信任的证书';
    return '连接失败：$s';
  }

  @override
  State<CloudDrive2SetupPage> createState() => _CloudDrive2SetupPageState();
}

class _CloudDrive2SetupPageState extends State<CloudDrive2SetupPage> {
  late final TextEditingController _name = TextEditingController(text: widget.server?.name ?? 'CloudDrive2');
  late final TextEditingController _url = TextEditingController(text: widget.server?.url ?? '');
  late final TextEditingController _user = TextEditingController(text: widget.server?.username ?? '');
  late final TextEditingController _pass = TextEditingController(text: widget.server?.password ?? '');
  bool _testing = false;

  WebDavServer? _build() {
    final url = CloudDrive2SetupPage.normalize(_url.text);
    if (url.isEmpty) {
      Toast.show('服务器地址不能为空', iserror: true);
      return null;
    }
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      Toast.show('请填写 CD2 的登录账号和密码', iserror: true);
      return null;
    }
    return WebDavServer(
      id: widget.server?.id ?? '',
      name: _name.text.trim().isEmpty ? 'CloudDrive2' : _name.text.trim(),
      url: url,
      username: _user.text.trim(),
      password: _pass.text,
      type_: CloudDrive.typeCloudDrive2,
    );
  }

  Future<void> _test() async {
    if (_url.text.trim().isEmpty) return Toast.show('请先填写服务器地址', iserror: true);
    final s = _build();
    if (s == null) return;
    setState(() => _testing = true);
    try {
      final dirs = (await WebDavDrive(s).list('/')).where((f) => f.isDir).length;
      Toast.show(dirs > 0 ? '连接成功，发现 $dirs 个云盘目录' : '连接成功，但还没有挂载任何云盘，请先在 CD2 网页管理里添加云盘');
    } catch (e) {
      Toast.show(CloudDrive2SetupPage.errorText(e), iserror: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final s = _build();
    if (s == null) return;
    if (widget.server == null) {
      await WebDav.add(s);
      Toast.show('CloudDrive2 添加成功');
    } else {
      await WebDav.update(s);
      Toast.show('已保存');
    }
    Get.back(result: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    InputDecoration deco(String l, [String? h]) => InputDecoration(labelText: l, hintText: h, border: const OutlineInputBorder(), isDense: true);
    return Scaffold(
      appBar: AppBar(title: const Text('CloudDrive2'), actions: [
        TextButton(key: const Key('cd2_save'), onPressed: _save, child: Text(widget.server == null ? '保存' : '保存修改')),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: deco('名称')),
        const SizedBox(height: 16),
        Text('连接信息', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(key: const Key('cd2_url'), controller: _url, onChanged: (_) => setState(() {}), decoration: deco('服务器地址', '192.168.1.10')),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('端口和 /dav 只在未填写时才补全，自定义端口不受影响\n实际连接地址：${CloudDrive2SetupPage.normalize(_url.text)}',
              style: TextStyle(fontSize: 12, color: cs.outline)),
        ),
        TextField(controller: _user, decoration: deco('CD2 账号', '登录 CloudDrive2 的邮箱（或 @ 前面的部分）')),
        const SizedBox(height: 12),
        TextField(controller: _pass, obscureText: true, decoration: deco('CD2 密码', 'CloudDrive2 的登录密码')),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _testing ? null : _test,
          icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
          label: const Text('测试连接'),
        ),
      ]),
    );
  }
}
