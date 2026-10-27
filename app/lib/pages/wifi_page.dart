// pages/wifi_page.dart — Wi-Fi传书 (`WiFiPage`, 26 functions): an in-app HTTP server on port 5757 (`HttpServer.bind(anyIPv4, 5757)`,
// 0xfd6f98) serving an upload page (0x5f0be0) and accepting multipart uploads (0xfd7178 / parser 0xfd7a48: boundary, `filename="…"`).
// Accepted books: `.txt` `.epub` `.mobi` (0xfd7808, otherwise `上传失败：请先选择需要上传的书本`); the file is saved under `<root>/books`
// and imported into the shelf (`文件上传并导入书架成功`); the reply is JSON `{status, message}`. The page shows 服务器状态 (已启动),
// 访问地址 `http://<ip>:5757` (tap copies: `地址已复制到剪贴板`; IP from the en/eth/wlan interfaces, `获取IP失败` / `无法获取IP地址`),
// 启动服务器 / 停止服务器 and 已上传文件. The import into the shelf belongs to the reading core: [WiFiPage.importBook] is the hook.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../common/app_dirs.dart';
import '../util/toast.dart';

class UploadedBook {
  final String name;
  final String path;
  final int size;
  final DateTime time;
  const UploadedBook(this.name, this.path, this.size, this.time);
}

/// Multipart parsing of one upload (0xfd7a48): the first part with a `filename`.
class UploadPart {
  final String filename;
  final Uint8List data;
  const UploadPart(this.filename, this.data);

  static int _indexOf(Uint8List h, List<int> n, [int start = 0]) {
    outer:
    for (var i = start; i <= h.length - n.length; i++) {
      for (var j = 0; j < n.length; j++) {
        if (h[i + j] != n[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static UploadPart? parse(Uint8List body, String boundary) {
    final delim = utf8.encode('--$boundary');
    var pos = _indexOf(body, delim);
    final sep = utf8.encode('\r\n\r\n');
    while (pos >= 0) {
      final headStart = pos + delim.length + 2;
      final headEnd = _indexOf(body, sep, headStart);
      if (headEnd < 0) return null;
      final head = utf8.decode(body.sublist(headStart, headEnd), allowMalformed: true);
      final next = _indexOf(body, delim, headEnd + 4);
      if (next < 0) return null;
      final m = RegExp(r'filename="([^"]+)"').firstMatch(head);
      if (head.toLowerCase().contains('content-disposition:') && m != null) {
        var end = next;
        if (end >= 2 && body[end - 2] == 13 && body[end - 1] == 10) end -= 2;
        return UploadPart(m.group(1)!, Uint8List.sublistView(body, headEnd + 4, end));
      }
      pos = next;
    }
    return null;
  }
}

class WifiTransferServer {
  static const int defaultPort = 5757;
  static const List<String> extensions = ['.txt', '.epub', '.mobi'];

  HttpServer? _server;
  final List<UploadedBook> uploaded = [];
  final StreamController<UploadedBook> _events = StreamController<UploadedBook>.broadcast();
  Stream<UploadedBook> get onUpload => _events.stream;

  /// Imports a saved file into the shelf; returns an error text or null. Default: [WiFiPage.importBook].
  final Future<String?> Function(File file) importer;
  WifiTransferServer({Future<String?> Function(File file)? importer}) : importer = importer ?? ((f) => WiFiPage.importBook(f));

  bool get running => _server != null;
  int get port => _server?.port ?? defaultPort;

  Future<void> start({int port = defaultPort, InternetAddress? address}) async {
    if (_server != null) return;
    final s = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server = s;
    s.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  Future<void> _reply(HttpRequest req, int status, Map<String, dynamic> body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method == 'GET') {
        req.response
          ..headers.contentType = ContentType.html
          ..write(page);
        await req.response.close();
        return;
      }
      if (req.method != 'POST') return _reply(req, 405, {'status': 'error', 'message': 'method not allowed'});
      final boundary = req.headers.contentType?.parameters['boundary'];
      final builder = BytesBuilder(copy: false);
      await for (final chunk in req) {
        builder.add(chunk);
      }
      final body = builder.takeBytes();
      final file = boundary == null ? null : UploadPart.parse(body, boundary);
      if (file == null || !extensions.contains(p.extension(file.filename).toLowerCase())) {
        return _reply(req, 400, {'status': 'error', 'message': '上传失败：请先选择需要上传的书本'});
      }
      final dir = await AppDirs.ensure('books');
      var dest = File(p.join(dir.path, p.basename(file.filename)));
      if (dest.existsSync()) {
        dest = File(p.join(dir.path, '${p.basenameWithoutExtension(file.filename)}_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.filename)}'));
      }
      await dest.writeAsBytes(file.data, flush: true);
      final err = await importer(dest);
      if (err != null) return _reply(req, 500, {'status': 'error', 'message': '上传失败: $err'});
      final u = UploadedBook(p.basename(file.filename), dest.path, file.data.length, DateTime.now());
      uploaded.insert(0, u);
      if (!_events.isClosed) _events.add(u);
      return _reply(req, 200, {'status': 'success', 'message': '文件上传并导入书架成功'});
    } catch (e) {
      try {
        await _reply(req, 500, {'status': 'error', 'message': '上传失败: $e'});
      } catch (_) {}
    }
  }

  /// The local IPv4 address of a Wi-Fi / ethernet interface (0x10ccdf8 prefers `en`, `eth`, `wlan`).
  static Future<String?> localIp() async {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final prefix in const ['en', 'eth', 'wlan']) {
      for (final i in list) {
        if (i.name.toLowerCase().startsWith(prefix) && i.addresses.isNotEmpty) return i.addresses.first.address;
      }
    }
    for (final i in list) {
      if (i.addresses.isNotEmpty) return i.addresses.first.address;
    }
    return null;
  }

  /// The upload page (the replica's own markup).
  static const String page = '''<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Wi-Fi传书</title>
  <style>
    body{font-family:-apple-system,sans-serif;max-width:560px;margin:40px auto;padding:0 16px;color:#222}
    h1{font-size:22px} .box{border:2px dashed #8bc34a;border-radius:12px;padding:32px;text-align:center}
    button{margin-top:16px;padding:10px 28px;border:0;border-radius:8px;background:#4caf50;color:#fff;font-size:16px}
    #msg{margin-top:16px;white-space:pre-line}
  </style>
</head>
<body>
  <h1>Wi-Fi传书</h1>
  <p>选择 TXT / EPUB / MOBI 文件上传到轻悦时光书架。</p>
  <div class="box">
    <input id="f" type="file" accept=".txt,.epub,.mobi" multiple>
    <br><button onclick="up()">上传</button>
    <div id="msg"></div>
  </div>
  <script>
    async function up(){
      const files=document.getElementById('f').files, msg=document.getElementById('msg');
      if(!files.length){msg.textContent='上传失败：请先选择需要上传的书本';return;}
      msg.textContent='';
      for(const file of files){
        const fd=new FormData(); fd.append('file',file,file.name);
        try{const r=await fetch('/upload',{method:'POST',body:fd}); const j=await r.json(); msg.textContent+=file.name+'：'+j.message+'\\n';}
        catch(e){msg.textContent+=file.name+'：上传失败: '+e+'\\n';}
      }
    }
  </script>
</body>
</html>''';
}

class WiFiPage extends StatefulWidget {
  const WiFiPage({super.key});

  /// Imports an uploaded book into the shelf; returns an error text or null. The reading core wires the real import
  /// (`Nav`/lead); until then the file stays in `<root>/books`.
  static Future<String?> Function(File file) importBook = (_) async => null;

  @override
  State<WiFiPage> createState() => _WiFiPageState();
}

class _WiFiPageState extends State<WiFiPage> {
  final WifiTransferServer _server = WifiTransferServer();
  StreamSubscription<UploadedBook>? _sub;
  String _ip = '';
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _sub = _server.onUpload.listen((u) {
      if (mounted) setState(() {});
      Toast.show('成功 ${u.name}');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _server.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await _server.start();
      String? ip;
      try {
        ip = await WifiTransferServer.localIp();
      } catch (_) {
        Toast.show('获取IP失败', iserror: true);
      }
      if (ip == null) Toast.show('无法获取IP地址', iserror: true);
      _ip = ip ?? '127.0.0.1';
      Toast.show('服务器已启动');
    } catch (e) {
      Toast.show('启动失败: $e', iserror: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    await _server.stop();
    Toast.show('服务器已停止');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = _server.running;
    final url = 'http://$_ip:${_server.port}';
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi传书')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('服务器状态', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Icon(Icons.circle, size: 10, color: running ? Colors.green : cs.outline),
                const SizedBox(width: 6),
                Text(running ? '已启动' : '未启动'),
              ]),
              const SizedBox(height: 12),
              const Text('访问地址'),
              const SizedBox(height: 6),
              InkWell(
                onTap: running
                    ? () {
                        Clipboard.setData(ClipboardData(text: url));
                        Toast.show('地址已复制到剪贴板');
                      }
                    : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                  child: Text(running ? url : '请先启动服务器', style: const TextStyle(fontFamily: 'Monaco', fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('wifi_toggle'),
                  style: running ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
                  onPressed: _starting ? null : (running ? _stop : _start),
                  child: Text(_starting ? '启动中...' : (running ? '停止服务器' : '启动服务器')),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text('已上传文件', style: Theme.of(context).textTheme.titleSmall),
        if (_server.uploaded.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('使用浏览器访问上方地址上传文件', style: TextStyle(color: cs.outline)))),
        for (final u in _server.uploaded)
          ListTile(leading: const Icon(Icons.menu_book_outlined), title: Text(u.name), subtitle: Text('${(u.size / 1024).toStringAsFixed(1)} KB')),
      ]),
    );
  }
}
