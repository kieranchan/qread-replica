// pages/scanner/mobile_scanner.dart — `MobileScannerPage` (扫码): returns the url of a scanned QR code (used by the 扫码导入 items).
// Original `_MobileScannerPageState` (build 0x7f35a4 with the `mobile_scanner` camera view and an image-picker button `_pickImage`;
// detection 0x7f3b24 keeps codes starting with `http`; errors 0x10902ec `检测到的二维码不是有效的URL: ` / `二维码解析失败: ` /
// `选择图片失败: `).
//
// This build has no camera / barcode plugin, so the page offers a manual input (type or paste the url the QR code contains)
// and says that scanning is not available.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String scannerUnavailableNote = '此版本未包含扫码组件，无法使用相机扫描。请手动输入或粘贴二维码中的网址。';

class MobileScannerPage extends StatefulWidget {
  const MobileScannerPage({super.key});

  @override
  State<MobileScannerPage> createState() => _MobileScannerPageState();
}

class _MobileScannerPageState extends State<MobileScannerPage> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0x7f3b24: only urls are accepted.
  void _submit() {
    final v = _c.text.trim();
    if (!v.startsWith('http')) {
      setState(() => _error = '检测到的二维码不是有效的URL: $v');
      return;
    }
    Navigator.of(context).pop(v);
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _c.text = d!.text!.trim());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('扫码')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Icon(Icons.qr_code_scanner, size: 72, color: cs.outline),
          const SizedBox(height: 12),
          Text(scannerUnavailableNote, key: const Key('scanner_note'), textAlign: TextAlign.center, style: TextStyle(color: cs.outline, height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('scanner_input'),
            controller: _c,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: '网址',
              hintText: 'https://',
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(tooltip: '粘贴', icon: const Icon(Icons.content_paste), onPressed: _paste),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          ElevatedButton(key: const Key('scanner_ok'), onPressed: _submit, child: const Text('确定')),
        ]),
      ),
    );
  }
}
