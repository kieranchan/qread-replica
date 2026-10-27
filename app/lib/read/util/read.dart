// read/util/read.dart — small helpers of the reader that the original keeps in `read/util/read.dart`: loading the user's imported fonts
// into the engine before a page uses them, and the font list the menus offer (built-in 阿里黑体 `boldface`, 阿里圆体 `circle`, then the
// fonts of `FontsData`; "谷歌汉字" needs the google_fonts download in the original and is not offered: TODO(asm 0x673384)).
import 'dart:io';

import 'package:flutter/services.dart';

import '../../data/fonts.dart';

class ReaderFont {
  final String family;
  final String label;
  const ReaderFont(this.family, this.label);
}

abstract class ReaderFonts {
  static final Set<String> _loaded = {};

  static const List<ReaderFont> builtin = [
    ReaderFont('', '默认字体'),
    ReaderFont('boldface', '阿里黑体'),
    ReaderFont('circle', '阿里圆体'),
  ];

  /// Built-in fonts followed by the imported ones.
  static Future<List<ReaderFont>> all() async {
    try {
      await FontsData.load();
    } catch (_) {}
    return [...builtin, for (final f in FontsData.fonts) ReaderFont(f.family, f.family)];
  }

  /// Registers an imported font family with the engine (once per run). Built-in families are no-ops.
  static Future<bool> ensure(String family) async {
    if (family.isEmpty || builtin.any((f) => f.family == family) || _loaded.contains(family)) return true;
    try {
      await FontsData.load();
    } catch (_) {}
    for (final f in FontsData.fonts) {
      if (f.family != family) continue;
      final file = File(FontsData.filePath(f));
      if (!file.existsSync()) return false;
      final loader = FontLoader(family)..addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
      _loaded.add(family);
      return true;
    }
    return false;
  }
}
