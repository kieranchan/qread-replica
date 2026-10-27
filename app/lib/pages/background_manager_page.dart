// pages/background_manager_page.dart — 阅读背景 (`BackgroundManagerPage`, 8 functions): the reading background images. The 14 built-in
// images (`lib/assets/bg/1..14.jpg`) come first, then the user's images in `<root>/images` (listed from the directory, 0x639180).
// Import (`_importBackground` 0x639228): pick an image, copy it in → `背景图片导入成功` / `导入失败: …`. Tap copies the address
// (`file://<path>` → `已复制地址`, 0x638f60). Deleting a user image is refused while a reading layout (`Ground`) uses it
// (`该背景图片正在被排版使用，无法删除`), otherwise `背景图片已删除` / `删除失败: …`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../common/app_dirs.dart';
import '../common/common.dart';
import '../data/ground.dart';
import '../theme/widgets.dart';
import '../util/toast.dart';

class BackgroundManagerPage extends StatefulWidget {
  const BackgroundManagerPage({super.key});

  /// The built-in backgrounds (also published as `Common.background`).
  static List<String> builtin() {
    final list = [for (var i = 1; i <= 14; i++) 'lib/assets/bg/$i.jpg'];
    if (Common.background.isEmpty) Common.background = list;
    return list;
  }

  static Directory get directory => AppDirs.dir('images');

  /// User images, newest first.
  static List<File> userImages() {
    final d = directory;
    if (!d.existsSync()) return [];
    const exts = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
    final files = d.listSync().whereType<File>().where((f) => exts.contains(p.extension(f.path).toLowerCase())).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  /// Whether a reading layout references [path] (by full path or file name).
  static bool inUse(String path) {
    final name = p.basename(path);
    for (final g in Ground.grounds) {
      for (final s in [g.backgroundimage, g.backgroundimage2, g.backgroundimage3]) {
        if (s.isEmpty) continue;
        if (s == path || p.basename(s.replaceFirst('file://', '')) == name) return true;
      }
    }
    return false;
  }

  @override
  State<BackgroundManagerPage> createState() => _BackgroundManagerPageState();
}

class _BackgroundManagerPageState extends State<BackgroundManagerPage> {
  @override
  void initState() {
    super.initState();
    Ground.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _importBackground() async {
    try {
      final f = await DeviceIo.pickFile(image: true);
      if (f == null) return;
      final d = await AppDirs.ensure('images');
      await f.copy(p.join(d.path, '${DateTime.now().millisecondsSinceEpoch}${p.extension(f.path).toLowerCase()}'));
      Toast.show('背景图片导入成功');
      if (mounted) setState(() {});
    } catch (e) {
      Toast.show('导入失败: $e', iserror: true);
    }
  }

  Future<void> _delete(File f) async {
    if (BackgroundManagerPage.inUse(f.path)) return Toast.show('该背景图片正在被排版使用，无法删除', iserror: true);
    if (!await Dialogs.confirm(context, '删除确认', '确定要删除这张背景图片吗？', danger: true)) return;
    try {
      await f.delete();
      Toast.show('背景图片已删除');
      if (mounted) setState(() {});
    } catch (e) {
      Toast.show('删除失败: $e', iserror: true);
    }
  }

  void _copy(String path) {
    Clipboard.setData(ClipboardData(text: path.startsWith('lib/') ? path : 'file://$path'));
    Toast.show('已复制地址');
  }

  Widget _tile(ImageProvider img, {required VoidCallback onTap, VoidCallback? onDelete, Key? key}) => InkWell(
        key: key,
        onTap: onTap,
        onLongPress: onDelete,
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image(image: img, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image))),
          if (onDelete != null)
            Positioned(
              right: 2,
              top: 2,
              child: IconButton.filledTonal(iconSize: 16, visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline), onPressed: onDelete),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final builtin = BackgroundManagerPage.builtin();
    final user = BackgroundManagerPage.userImages();
    const grid = SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, childAspectRatio: 0.6, mainAxisSpacing: 8, crossAxisSpacing: 8);
    return Scaffold(
      appBar: AppBar(title: const Text('阅读背景'), actions: [
        IconButton(key: const Key('bg_import'), tooltip: '导入', icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: _importBackground),
      ]),
      body: CustomScrollView(slivers: [
        if (user.isNotEmpty) ...[
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Text('自定义'))),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate: grid,
              itemCount: user.length,
              itemBuilder: (_, i) => _tile(FileImage(user[i]), onTap: () => _copy(user[i].path), onDelete: () => _delete(user[i])),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Text('内置'))),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverGrid.builder(
            gridDelegate: grid,
            itemCount: builtin.length,
            itemBuilder: (_, i) => _tile(AssetImage(builtin[i]), key: Key('bg_builtin_$i'), onTap: () => _copy(builtin[i])),
          ),
        ),
      ]),
    );
  }
}
