// pages/setting/clean_page.dart — 清理缓存 (`CleanPage`, 65 functions). Header `总缓存大小` (`正在计算缓存大小...`), 缓存清理 rows with
// sizes (图片缓存 / 书本缓存 / 数据备份 / 系统缓存 / 本地朗读引擎 `点击前往「朗读引擎」页面管理`) and 系统工具:
//   清理书本缓存 `只清理不在书架的书本缓存` (`⚠️ 您将清除不在书架的书本缓存！` / `此操作不可撤销，请确保已备份重要数据！`)
//   清理阅读统计 `清理已记录的阅读时间`
//   清除内置WebView `清理内置浏览器的所有数据` (`• 浏览器缓存和Cookie` → `WebView数据已成功清除`)
//   清除源Cache `清理书源缓存和配置` (`确定要清除所有源Cache数据吗？` → `清除完成！` `源Cache已成功清除`)
//   清理旧版本书本缓存 (when `audio` / `bookcache` exist: `检测到旧版本的书本缓存文件夹，是否清理？`)
//   恢复出厂设置 `重置所有应用到初始状态` (account and sync keys survive, `Common.cleanwhite`).
// TODO(asm 0x101e8c0..): the per-book cache folder naming belongs to the reading core; a folder counts as "on the shelf" when its name
// is the book url or its md5.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../common/app_dirs.dart';
import '../../data/bookself.dart';
import '../../init/appinit.dart';
import '../../storage/storage.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';
import '../tts/tts_setting.dart';

class CleanPage extends StatefulWidget {
  const CleanPage({super.key});

  /// Clears the in-app browser data (webview_flutter cookie manager + cache); the web area wires the real call.
  static Future<void> Function() clearWebView = () async {};

  /// Cache folders and what they count as.
  static const List<String> imageDirs = ['images_cache', 'covers_cache', 'cache/images'];
  static const List<String> bookDirs = ['bookcache2', 'epub', 'audio2'];

  static int sizeOf(List<String> names) => names.fold(0, (n, d) => n + dirSize(AppDirs.dir(d)));

  /// Deletes the entries of [dir] that are not books on the shelf; returns how many were removed.
  static int cleanBookCache(String dir) {
    final d = AppDirs.dir(dir);
    if (!d.existsSync()) return 0;
    final keep = <String>{};
    for (final b in Bookdata.books) {
      keep
        ..add(b.bookUrl)
        ..add(Storage.md5Of(b.bookUrl))
        ..add(b.name);
    }
    var n = 0;
    for (final e in d.listSync()) {
      final name = p.basenameWithoutExtension(e.path);
      if (keep.contains(name) || keep.contains(p.basename(e.path))) continue;
      try {
        e.deleteSync(recursive: true);
        n++;
      } catch (_) {}
    }
    return n;
  }

  static void emptyDir(String name) {
    final d = AppDirs.dir(name);
    if (!d.existsSync()) return;
    for (final e in d.listSync()) {
      try {
        e.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// 恢复出厂设置: prefs except the account / sync keys, unprotected item files and every data folder.
  static Future<void> factoryReset() async {
    final keep = AppInit.accountKeys.toSet()..add('appid');
    for (final k in Storage.dumpPrefs().keys) {
      if (!keep.contains(k)) await Storage.remove(k);
    }
    await Storage.cleanItems();
    for (final d in {...AppDirs.startup, ...AppDirs.extra}) {
      if (d == 'item') continue;
      emptyDir(d);
    }
  }

  @override
  State<CleanPage> createState() => _CleanPageState();
}

class _CleanPageState extends State<CleanPage> {
  Map<String, int>? _sizes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    setState(() => _sizes = null);
    final s = <String, int>{
      '图片缓存': CleanPage.sizeOf(CleanPage.imageDirs),
      '书本缓存': CleanPage.sizeOf(CleanPage.bookDirs),
      '数据备份': CleanPage.sizeOf(const ['backup']),
      '系统缓存': CleanPage.sizeOf(const ['cache', 'backup_temp', 'restore_temp', 'tts_analysis']),
      '本地朗读引擎': CleanPage.sizeOf(const ['local_tts']),
    };
    if (mounted) setState(() => _sizes = s);
  }

  int get _total => _sizes?.values.fold<int>(0, (a, b) => a + b) ?? 0;

  Future<void> _clean(String label) async {
    if (label == '本地朗读引擎') {
      await Get.to(() => const TTsSetting());
      return _measure();
    }
    if (!await Dialogs.confirm(context, '清理缓存', '确定要清理$label吗？')) return;
    try {
      switch (label) {
        case '图片缓存':
          for (final d in CleanPage.imageDirs) {
            CleanPage.emptyDir(d);
          }
          PaintingBinding.instance.imageCache.clear();
        case '书本缓存':
          await Bookdata.load();
          for (final d in CleanPage.bookDirs) {
            CleanPage.cleanBookCache(d);
          }
        case '数据备份':
          CleanPage.emptyDir('backup');
          await Storage.write('backup', '');
        case '系统缓存':
          for (final d in const ['cache', 'backup_temp', 'restore_temp', 'tts_analysis']) {
            CleanPage.emptyDir(d);
          }
      }
      Toast.show('清除完成！');
    } catch (e) {
      Toast.show('$label失败 错误: $e', iserror: true);
    }
    await _measure();
  }

  Future<void> _tool(String what) async {
    switch (what) {
      case 'books':
        if (!await Dialogs.confirm(context, '清除书本缓存', '⚠️ 您将清除不在书架的书本缓存！\n此操作不可撤销，请确保已备份重要数据！', confirmText: '确认清除', danger: true)) return;
        await Bookdata.load();
        var n = 0;
        for (final d in CleanPage.bookDirs) {
          n += CleanPage.cleanBookCache(d);
        }
        Toast.show('清除完成！($n)');
      case 'stats':
        if (!await Dialogs.confirm(context, '清理阅读统计', '确定要清理已记录的阅读时间吗？', danger: true)) return;
        CleanPage.emptyDir('reading_time');
        CleanPage.emptyDir('book_reading_time');
        Toast.show('清除完成！');
      case 'webview':
        if (!await Dialogs.confirm(context, '清除内置WebView', '确定要清除内置浏览器的所有数据吗？\n• 浏览器缓存和Cookie', confirmText: '确认清除', danger: true)) return;
        await CleanPage.clearWebView();
        Toast.show('WebView数据已成功清除');
      case 'source':
        if (!await Dialogs.confirm(context, '清除源Cache', '确定要清除所有源Cache数据吗？', confirmText: '确认清除', danger: true)) return;
        CleanPage.emptyDir('cache');
        Toast.show('源Cache已成功清除');
      case 'old':
        final old = [for (final d in const ['audio', 'bookcache']) if (AppDirs.dir(d).existsSync() && AppDirs.dir(d).listSync().isNotEmpty) d];
        if (old.isEmpty) return Toast.show('清除完成！');
        if (!await Dialogs.confirm(context, '清理旧版本书本缓存', '检测到旧版本的书本缓存文件夹，是否清理？\n${old.map((e) => '• $e 文件夹').join('\n')}', confirmText: '确认清理')) return;
        for (final d in old) {
          CleanPage.emptyDir(d);
        }
        Toast.show('清除完成！');
      case 'reset':
        if (!await Dialogs.confirm(context, '恢复出厂设置', '重置所有应用到初始状态？\n此操作不可撤销，请确保已备份重要数据！', confirmText: '确定', danger: true)) return;
        await CleanPage.factoryReset();
        Toast.show('清除完成！');
    }
    await _measure();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _sizes;
    return Scaffold(
      appBar: AppBar(title: const Text('清理缓存')),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text('总缓存大小', style: TextStyle(color: cs.onPrimaryContainer)),
            const SizedBox(height: 6),
            Text(s == null ? '正在计算缓存大小...' : formatBytes(_total),
                key: const Key('clean_total'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
          ]),
        ),
        SectionCard(title: '缓存清理', children: [
          for (final e in (s ?? const <String, int>{}).entries)
            ListTile(
              key: Key('clean_${e.key}'),
              title: Text(e.key),
              subtitle: e.key == '本地朗读引擎' ? const Text('点击前往「朗读引擎」页面管理') : null,
              trailing: Text(formatBytes(e.value)),
              onTap: () => _clean(e.key),
            ),
        ]),
        SectionCard(title: '系统工具', children: [
          ListTile(title: const Text('清理书本缓存'), subtitle: const Text('只清理不在书架的书本缓存'), onTap: () => _tool('books')),
          ListTile(title: const Text('清理旧版本书本缓存'), subtitle: const Text('• audio 文件夹  • bookcache 文件夹'), onTap: () => _tool('old')),
          ListTile(title: const Text('清理阅读统计'), subtitle: const Text('清理已记录的阅读时间'), onTap: () => _tool('stats')),
          ListTile(title: const Text('清除内置WebView'), subtitle: const Text('清理内置浏览器的所有数据'), onTap: () => _tool('webview')),
          ListTile(title: const Text('清除源Cache'), subtitle: const Text('清理书源缓存和配置'), onTap: () => _tool('source')),
          ListTile(
            title: const Text('恢复出厂设置', style: TextStyle(color: Colors.red)),
            subtitle: const Text('重置所有应用到初始状态'),
            onTap: () => _tool('reset'),
          ),
        ]),
      ]),
    );
  }
}
