// pages/theme/icon_plaza_page.dart — 图标广场 (`IconPlazaPage`, 21 functions): the bundled app icons `lib/assets/images/icons/<n>.*`.
// Tap: `更换应用图标` / `确定要将应用图标更换为图标 n 吗？` → the name is written to `<root>/icon.txt` (0x1054d74) and the alternate icon
// is requested from the platform. Long press: `保存图标` / `确定要将图标保存到手机吗？` → the image is handed to the share sheet.
// Errors: `保存失败icon, 错误: …`, `读取失败icon, 错误: …`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../common/app_dirs.dart';
import '../../storage/storage.dart';
import '../../theme/widgets.dart';
import '../../util/toast.dart';

class IconPlazaPage extends StatefulWidget {
  const IconPlazaPage({super.key});

  /// The bundled icons in their asset order (file names of `lib/assets/images/icons/`).
  static const List<String> icons = [
    '1.png', '2.png', '3.png', '4.png', '5.png', '6.jpg', '7.png', '8.jpeg', '9.jpeg', '10.jpeg',
    '11.png', '12.jpg', '13.png', '14.png', '15.png', '16.png', '17.png', '18.jpg', '19.jpeg', '20.png',
  ];

  /// Hook for the platform call that switches the home-screen icon (iOS `setAlternateIconName`). TODO(asm 0x10d0708): the replica's
  /// iOS project defines no alternate icons yet, so the default only records the choice.
  static Future<void> Function(String name) setAppIcon = (_) async {};

  static File get iconFile => File(p.join(AppDirs.root.path, 'icon.txt'));

  /// The chosen icon name (`icon.txt`), '' for the default.
  static Future<String> current() async {
    try {
      return (await Storage.readFile(iconFile.path)).trim();
    } catch (e) {
      Toast.show('读取失败icon, 错误: $e', iserror: true);
      return '';
    }
  }

  @override
  State<IconPlazaPage> createState() => _IconPlazaPageState();
}

class _IconPlazaPageState extends State<IconPlazaPage> {
  String _current = '';

  @override
  void initState() {
    super.initState();
    IconPlazaPage.current().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  Future<void> _apply(int i) async {
    final name = '${i + 1}';
    if (!await Dialogs.confirm(context, '更换应用图标', '确定要将应用图标更换为图标 $name 吗？')) return;
    try {
      await Storage.writeFile(IconPlazaPage.iconFile.path, name);
      await IconPlazaPage.setAppIcon(name);
      setState(() => _current = name);
    } catch (e) {
      Toast.show('保存失败icon, 错误: $e', iserror: true);
    }
  }

  Future<void> _save(int i) async {
    if (!await Dialogs.confirm(context, '保存图标', '确定要将图标保存到手机吗？')) return;
    try {
      final asset = 'lib/assets/images/icons/${IconPlazaPage.icons[i]}';
      final data = await rootBundle.load(asset);
      final d = await AppDirs.ensure('cache');
      final f = File(p.join(d.path, 'icon_${IconPlazaPage.icons[i]}'));
      await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await DeviceIo.shareFile(f);
    } catch (e) {
      Toast.show('保存失败icon, 错误: $e', iserror: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('图标广场')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.8),
        itemCount: IconPlazaPage.icons.length,
        itemBuilder: (_, i) {
          final selected = _current == '${i + 1}';
          return GestureDetector(
            onTap: () => _apply(i),
            onLongPress: () => _save(i),
            child: Column(children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset('lib/assets/images/icons/${IconPlazaPage.icons[i]}', width: 64, height: 64, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 4),
              Text('图标 ${i + 1}', style: TextStyle(fontSize: 12, color: selected ? cs.primary : null)),
            ]),
          );
        },
      ),
    );
  }
}
