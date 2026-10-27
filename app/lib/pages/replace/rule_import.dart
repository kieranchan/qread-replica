// pages/replace/rule_import.dart — shared steps of the three rule pages (替换规则 / 目录规则 / 高亮规则): "本地导入" (file picker),
// "网络导入" (URL), "扫码导入" (scanner page via Nav), confirmation dialogs, and the batch bar of the selection mode (全选 (n) · 反选).
// Strings: 请选择您想要导入的规则文件 · 导入失败: · 选择文件失败: · 操作确认 · 确定要 … 这些规则吗？ · 删除确认 · 确定要删除这些规则吗？.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../common/nav.dart';
import '../../util/toast.dart';

abstract class RuleImport {
  /// Picks a JSON / TXT file and returns its text (null when cancelled).
  static Future<String?> pickFile() async {
    try {
      final r = await FilePicker.pickFiles(
        dialogTitle: '请选择您想要导入的规则文件',
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
      );
      final f = r.firstOrNull;
      if (f == null) return null;
      final bytes = await f.xFile.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      Toast.show('选择文件失败:$e');
      return null;
    }
  }

  /// Asks for a URL and downloads it.
  static Future<String?> fromNetwork(BuildContext context) async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('网络导入'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'http(s)://')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    c.dispose();
    if (url == null || url.isEmpty) return null;
    return download(url);
  }

  static Future<String?> download(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return await res.transform(utf8.decoder).join();
    } catch (e) {
      Toast.show('导入失败:$e');
      return null;
    } finally {
      client.close();
    }
  }

  /// "扫码导入": the scanner page belongs to another area; it returns the scanned text (a URL or JSON).
  static Future<String?> fromScanner(BuildContext context) async {
    await Nav.openNamed(context, 'mobile_scanner');
    return null;
  }

  static Future<bool> confirm(BuildContext context, String title, String content) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    return ok == true;
  }
}

/// The bar of the selection mode.
class RuleBatchBar extends StatelessWidget {
  final int selected;
  final int total;
  final VoidCallback onSelectAll;
  final VoidCallback onInvert;
  final List<Widget> actions;

  const RuleBatchBar({super.key, required this.selected, required this.total, required this.onSelectAll, required this.onInvert, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            TextButton(onPressed: onSelectAll, child: Text('全选 ($selected/$total)')),
            TextButton(onPressed: onInvert, child: const Text('反选')),
            const Spacer(),
            ...actions,
          ]),
        ),
      ),
    );
  }
}
