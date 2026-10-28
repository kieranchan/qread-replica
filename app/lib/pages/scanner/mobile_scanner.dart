// pages/scanner/mobile_scanner.dart — `MobileScannerPage` (扫码): returns the url of a scanned QR code (used by the 扫码导入 items of the
// source manager, the RSS manager and 添加配置, all through `SourceImport.scan`).
// Original `_MobileScannerPageState` (build 0x7f35a4): app bar 「扫码」 with an image button (`_pickImage` 0x7f3cc4), a
// `MobileScanner` camera view (BoxFit.cover) under a square frame of 0.7 × the width; detection 0x7f3b24 pops with the first code
// that starts with `http`; the picked image goes through `controller.analyzeImage` (0x10902ec) with the snack bars
// `检测到的二维码不是有效的URL: ` / `二维码解析失败: ` / `选择图片失败: `.
//
// The replica adds a manual input (type or paste the url) as a fallback: from the app bar, when the camera fails (no permission,
// no camera) and on hosts without a camera (desktop, unit tests).
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const String scannerUnavailableNote = '当前设备无法使用相机扫描，请手动输入或粘贴二维码中的网址。';

class MobileScannerPage extends StatefulWidget {
  const MobileScannerPage({super.key});

  /// Whether the camera view is shown (iOS / Android); tests and desktop hosts get the manual input only.
  static bool Function() cameraAvailable = () {
    try {
      return Platform.isIOS || Platform.isAndroid;
    } catch (_) {
      return false;
    }
  };

  /// Picks a photo and returns its path (tests replace it).
  static Future<String?> Function() pickImagePath = () async => (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;

  /// Reads the codes of the image at a path (tests replace it); default: mobile_scanner's `analyzeImage`.
  static Future<List<String>> Function(MobileScannerController? controller, String path)? analyzeImage;

  @override
  State<MobileScannerPage> createState() => _MobileScannerPageState();
}

class _MobileScannerPageState extends State<MobileScannerPage> {
  MobileScannerController? controller;
  final _c = TextEditingController();
  String? _error;
  late bool _manual;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _manual = !MobileScannerPage.cameraAvailable();
    if (!_manual) {
      controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    _c.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _finish(String v) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(v);
  }

  /// 0x7f3b24: the first code that is a url.
  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue ?? '';
      if (v.startsWith('http')) return _finish(v);
    }
  }

  /// 0x10902ec: pick a photo and analyse it.
  Future<void> _pickImage() async {
    String? path;
    try {
      path = await MobileScannerPage.pickImagePath();
    } catch (e) {
      return _snack('选择图片失败: $e');
    }
    if (path == null) return;
    try {
      final codes = await (MobileScannerPage.analyzeImage ?? _analyze)(controller, path);
      if (codes.isEmpty) return _snack('二维码解析失败: 未识别到二维码');
      final v = codes.first;
      if (!v.startsWith('http')) return _snack('检测到的二维码不是有效的URL: $v');
      _finish(v);
    } catch (e) {
      _snack('二维码解析失败: $e');
    }
  }

  static Future<List<String>> _analyze(MobileScannerController? controller, String path) async {
    final c = controller ?? MobileScannerController(autoStart: false);
    try {
      final r = await c.analyzeImage(path, formats: const [BarcodeFormat.qrCode]);
      return [for (final b in r?.barcodes ?? const <Barcode>[]) if ((b.rawValue ?? '').isNotEmpty) b.rawValue!];
    } finally {
      if (controller == null) await c.dispose();
    }
  }

  /// Manual input: only urls are accepted (same rule as the detection).
  void _submit() {
    final v = _c.text.trim();
    if (!v.startsWith('http')) {
      setState(() => _error = '检测到的二维码不是有效的URL: $v');
      return;
    }
    _finish(v);
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _c.text = d!.text!.trim());
  }

  Widget _manualForm(BuildContext context, {String? note}) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Icon(Icons.qr_code_scanner, size: 72, color: cs.outline),
      const SizedBox(height: 12),
      if (note != null)
        Text(note, key: const Key('scanner_note'), textAlign: TextAlign.center, style: TextStyle(color: cs.outline, height: 1.5)),
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
    ]);
  }

  Widget _camera(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final side = box.maxWidth * 0.7;
      return Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: controller,
          fit: BoxFit.cover,
          onDetect: _onDetect,
          errorBuilder: (context, error) => ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: _manualForm(context, note: '无法打开相机（${error.errorCode.name}），请手动输入二维码中的网址。'),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              key: const Key('scanner_frame'),
              width: side,
              height: side,
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2), shape: BoxShape.rectangle),
            ),
          ),
        ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('扫码', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(key: const Key('scanner_pick'), tooltip: '相册', icon: const Icon(Icons.image_outlined), onPressed: _pickImage),
          if (controller != null)
            IconButton(
              key: const Key('scanner_manual'),
              tooltip: _manual ? '扫码' : '手动输入',
              icon: Icon(_manual ? Icons.qr_code_scanner : Icons.keyboard_outlined),
              onPressed: () => setState(() => _manual = !_manual),
            ),
        ],
      ),
      body: SafeArea(
        child: _manual || controller == null
            ? _manualForm(context, note: controller == null ? scannerUnavailableNote : null)
            : _camera(context),
      ),
    );
  }
}
