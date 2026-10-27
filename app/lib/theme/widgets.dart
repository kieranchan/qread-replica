// theme/widgets.dart — small UI helpers shared by the extras pages (settings, themes, TTS, WebDAV): confirm / input dialogs, a colour
// picker, section cards and the device hooks (file picker, share) behind replaceable functions so widget tests run on the host.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'theme_provider.dart';

/// Device hooks. Tests replace them; the defaults call file_picker / share_plus.
abstract class DeviceIo {
  /// Picks one file; [extensions] without dots (e.g. `['ttf','otf']`), null = any file. Returns null when cancelled.
  static Future<File?> Function({List<String>? extensions, bool image}) pickFile = _pickFile;

  /// Shares / saves a file (system share sheet).
  static Future<void> Function(File file, {String? text}) shareFile = _shareFile;

  static Future<File?> _pickFile({List<String>? extensions, bool image = false}) async {
    final List<PlatformFile> r;
    if (image) {
      r = await FilePicker.pickFiles(type: FileType.image);
    } else if (extensions != null && extensions.isNotEmpty) {
      r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensions);
    } else {
      r = await FilePicker.pickFiles();
    }
    if (r.isEmpty) return null;
    final path = r.first.path;
    return path == null ? null : File(path);
  }

  static Future<void> _shareFile(File file, {String? text}) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: text));
  }
}

abstract class Dialogs {
  /// A yes / no dialog; true when confirmed.
  static Future<bool> confirm(BuildContext context, String title, String content,
      {String confirmText = '确定', String cancelText = '取消', bool danger = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(cancelText)),
          TextButton(
            key: const Key('dialog_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText, style: danger ? const TextStyle(color: Colors.red) : null),
          ),
        ],
      ),
    );
    return r == true;
  }

  /// A one-line text input; null when cancelled.
  static Future<String?> input(BuildContext context, String title,
      {String hint = '', String initial = '', TextInputType? keyboardType, int maxLines = 1}) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('dialog_input'),
          controller: c,
          autofocus: true,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(key: const Key('dialog_confirm'), onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('确定')),
        ],
      ),
    );
    return r;
  }

  /// A list of choices; returns the chosen index or null.
  static Future<int?> choose(BuildContext context, String title, List<String> options, {int? selected}) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (var i = 0; i < options.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(i),
              child: Row(children: [
                Expanded(child: Text(options[i])),
                if (selected == i) Icon(Icons.check, size: 18, color: Theme.of(ctx).colorScheme.primary),
              ]),
            ),
        ],
      ),
    );
  }
}

/// The swatches the colour dialogs offer (plus a hex field).
const List<int> kPalette = [
  0xFFFFFFFF, 0xFFF5F5F5, 0xFFFAF3E0, 0xFFE8F5E9, 0xFFE3F2FD, 0xFFFCE4EC, 0xFFFFF8E1, 0xFF212121,
  0xFF000000, 0xFF424242, 0xFF795548, 0xFFF44336, 0xFFE91E63, 0xFF9C27B0, 0xFF673AB7, 0xFF3F51B5,
  0xFF2196F3, 0xFF03A9F4, 0xFF00BCD4, 0xFF009688, 0xFF4CAF50, 0xFF8BC34A, 0xFFCDDC39, 0xFFFFEB3B,
  0xFFFFC107, 0xFFFF9800, 0xFFFF5722, 0xFF607D8B, 0xFF1B1B1F, 0xFF2C2C2E, 0xFF3A3A3C, 0xFFB0BEC5,
];

/// Result of [pickColor]: [color] null with [cleared] true = 清除颜色.
class ColorChoice {
  final Color? color;
  final bool cleared;
  const ColorChoice(this.color, {this.cleared = false});
}

/// 选择颜色 dialog. Returns null when cancelled.
Future<ColorChoice?> pickColor(BuildContext context, {Color? initial, String title = '选择颜色', bool allowClear = true}) {
  final hex = TextEditingController(text: initial == null ? '' : ThemeColors.hex(initial));
  Color? current = initial;
  return showDialog<ColorChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in kPalette)
                GestureDetector(
                  onTap: () => setS(() {
                    current = Color(v);
                    hex.text = ThemeColors.hex(Color(v));
                  }),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(v),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: current?.toARGB32() == v ? Theme.of(ctx).colorScheme.primary : Colors.grey.shade400,
                          width: current?.toARGB32() == v ? 3 : 1),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Container(width: 32, height: 32, color: current ?? Colors.transparent),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: hex,
                  decoration: const InputDecoration(hintText: '#FF000000'),
                  onChanged: (s) => setS(() => current = ThemeColors.of(s) ?? current),
                ),
              ),
            ]),
          ]),
        ),
        actions: [
          if (allowClear) TextButton(onPressed: () => Navigator.of(ctx).pop(const ColorChoice(null, cleared: true)), child: const Text('清除颜色')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(ColorChoice(current)), child: const Text('确定')),
        ],
      ),
    ),
  );
}

/// A rounded card section with an optional title, used by the 「我的」 and settings pages (`tablecolor` + `shadow` of the page style).
class SectionCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final String page;
  final EdgeInsetsGeometry margin;
  const SectionCard({super.key, this.title, required this.children, this.page = '', this.margin = const EdgeInsets.fromLTRB(12, 6, 12, 6)});

  @override
  Widget build(BuildContext context) {
    final tp = ThemeProvider.instance;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: tp.tableColor(page, context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: tp.shadow(page),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(title!, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
        ...children,
      ]),
    );
  }
}

/// A page with the theme's page style (background colour / image) behind the body — the original's `MyScaffold(needshow:)`.
class StyledScaffold extends StatelessWidget {
  final String page;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  const StyledScaffold({super.key, required this.page, this.appBar, required this.body, this.floatingActionButton});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeProvider.instance,
      builder: (context, _) {
        final tp = ThemeProvider.instance;
        final img = tp.pageImage(page);
        return Scaffold(
          appBar: appBar,
          backgroundColor: tp.pageBackground(page),
          floatingActionButton: floatingActionButton,
          body: img == null
              ? body
              : DecoratedBox(decoration: BoxDecoration(image: DecorationImage(image: img, fit: BoxFit.cover)), child: body),
        );
      },
    );
  }
}

/// Human readable size (`1.2 MB`).
String formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  if (n < 1024 * 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// Total size of a directory (0 when missing).
int dirSize(Directory d) {
  if (!d.existsSync()) return 0;
  var n = 0;
  try {
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          n += e.lengthSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return n;
}
