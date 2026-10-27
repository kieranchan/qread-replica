// pages/theme/theme_detail_page.dart — one plaza theme (`ThemeDetailPage`, state 0x6c96a8 / 0x6ca404 / 0x6cb994): preview, name,
// 作者 / 更新 / 分类 / 版本 rows, description (`精心设计，为阅读而生` when empty), the mode (☀ 白天 / 🌙 夜间) and the buttons
//   下载主题 / 更新主题 (installed with another version) — member-only: `仅会员允许下载主题`; progress dialog `正在下载: n%` with
//     cancel (`下载已取消`), failure `下载失败: …`
//   应用主题 (installed) — member-only: `仅会员允许应用主题` (0x103e09c) → `已成功应用白天主题` / `…夜间主题`, `应用主题失败: …`
//   内置排版方案 `一键导入精美阅读排版` (layout_path, 0x103e31c) → `排版下载并导入成功`.
// Installed plaza themes keep the id `plaza_<id>` and the plaza version, so a newer version shows 更新主题.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../data/theme.dart';
import '../../models/theme.dart';
import '../../theme/theme_provider.dart';
import '../../util/toast.dart';
import '../../util/vip.dart';
import 'theme_api.dart';
import 'theme_package.dart';

class ThemeDetailPage extends StatefulWidget {
  final PlazaTheme theme;
  final ThemePlazaApi? api;
  const ThemeDetailPage({super.key, required this.theme, this.api});

  static String localId(PlazaTheme t) => 'plaza_${t.id}';

  @override
  State<ThemeDetailPage> createState() => _ThemeDetailPageState();
}

class _ThemeDetailPageState extends State<ThemeDetailPage> {
  late final ThemePlazaApi _api = widget.api ?? ThemePlazaApi();
  late PlazaTheme _t = widget.theme;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ThemeManager.load().then((_) {
      if (mounted) setState(() {});
    });
    _api.theme(widget.theme.id).then((t) {
      if (mounted) setState(() => _t = t);
    }).catchError((_) {});
  }

  ThemeModel? get _installed => ThemeManager.byId(ThemeDetailPage.localId(_t));

  /// Downloads [path] with the progress dialog; null when cancelled or failed (the message is shown).
  Future<List<int>?> _download(String path) async {
    final progress = ValueNotifier<double>(0);
    final cancel = CancelToken();
    var open = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            Text('正在下载: ${(v * 100).toStringAsFixed(0)}%'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: v),
          ]),
        ),
        actions: [TextButton(onPressed: () => cancel.cancel(), child: const Text('取消'))],
      ),
    ).whenComplete(() => open = false);
    void close() {
      if (open && mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      final data = await _api.download(path, cancelToken: cancel, onProgress: (v) => progress.value = v);
      close();
      return data;
    } on DioException catch (e) {
      close();
      Toast.show(CancelToken.isCancel(e) ? '下载已取消' : '下载失败: ${e.message}', iserror: !CancelToken.isCancel(e));
    } catch (e) {
      close();
      Toast.show('下载失败: $e', iserror: true);
    }
    return null;
  }

  Future<void> _downloadTheme() async {
    if (!Vip.require('仅会员允许下载主题')) return;
    if (_t.zipPath.isEmpty) return Toast.show('主题不存在', iserror: true);
    setState(() => _busy = true);
    try {
      final data = await _download(_t.zipPath);
      if (data == null) return;
      await ThemePackage.importBytes(data, id: ThemeDetailPage.localId(_t), version: _t.version);
      Toast.show(_installed == null ? '下载失败: 主题不存在' : '${_t.name} 下载完成');
      ThemeProvider.instance.refresh();
    } on ThemePackageException catch (e) {
      Toast.show('下载失败: ${e.message}', iserror: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (!Vip.require('仅会员允许应用主题')) return;
    final t = _installed;
    if (t == null) return Toast.show('主题不存在', iserror: true);
    try {
      await ThemeProvider.instance.applyTheme(t);
      Toast.show('已成功应用${t.isLightMode ? '白天' : '夜间'}主题');
      if (mounted) setState(() {});
    } catch (e) {
      Toast.show('应用主题失败: $e', iserror: true);
    }
  }

  Future<void> _importLayouts() async {
    if (!Vip.require('仅会员允许下载主题')) return;
    if (_t.layoutPath.isEmpty) return;
    final data = await _download(_t.layoutPath);
    if (data == null) return;
    try {
      final n = await ThemePackage.importLayouts(utf8.decode(data, allowMalformed: true));
      Toast.show(n > 0 ? '排版下载并导入成功' : '一样不必同步');
    } catch (e) {
      Toast.show('下载失败: $e', iserror: true);
    }
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          SizedBox(width: 48, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final installed = _installed;
    final needUpdate = installed != null && _t.version.isNotEmpty && installed.version != _t.version;
    final applied = installed != null && ThemeProvider.instance.isApplied(installed);
    return Scaffold(
      appBar: AppBar(title: Text(_t.name.isEmpty ? '主题' : _t.name)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SizedBox(
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _t.imagePath.isEmpty
                ? Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.palette_outlined, size: 64))
                : Image.network(_api.fileUrl(_t.imagePath),
                    fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined))),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text(_t.name, style: Theme.of(context).textTheme.titleLarge)),
          Chip(label: Text(_t.isNight ? '🌙 夜间' : '☀ 白天')),
        ]),
        const SizedBox(height: 4),
        Text(_t.description.isEmpty ? '精心设计，为阅读而生' : _t.description, style: TextStyle(color: cs.outline)),
        const Divider(height: 24),
        _row(Icons.person_outline, '作者', _t.author.isEmpty ? '匿名' : _t.author),
        _row(Icons.update, '更新', _t.updatedAt),
        _row(Icons.category_outlined, '分类', _t.category?.name ?? ''),
        _row(Icons.tag, '版本', _t.version),
        if (_t.layoutPath.isNotEmpty) ...[
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('内置排版方案'),
            subtitle: const Text('一键导入精美阅读排版'),
            trailing: const Icon(Icons.download_outlined),
            onTap: _importLayouts,
          ),
        ],
        const SizedBox(height: 24),
        if (installed == null || needUpdate)
          FilledButton.icon(
            key: const Key('theme_download'),
            onPressed: _busy ? null : _downloadTheme,
            icon: const Icon(Icons.download),
            label: Text(_busy ? '下载中...' : (needUpdate ? '更新主题' : '下载主题')),
          ),
        if (installed != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('theme_apply'),
            onPressed: applied ? null : _apply,
            icon: const Icon(Icons.check),
            label: Text(applied ? '已成功应用' : '应用主题'),
          ),
        ],
      ]),
    );
  }
}
