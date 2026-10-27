// read/util/read.dart — small helpers of the reader that the original keeps in `read/util/read.dart`: loading the user's imported fonts
// into the engine before a page uses them, and the font list the menus offer (built-in 阿里黑体 `boldface`, 阿里圆体 `circle`, then the
// fonts of `FontsData`; "谷歌汉字" needs the google_fonts download in the original and is not offered: TODO(asm 0x673384)).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/fonts.dart';
import '../setting/read_setting.dart';

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

/// 屏幕常亮 (`read/util/read.dart` 0x2b4e64 + timer closure 0x2b50f0, statics 0x1e70 on / 0x24f0 timer / 0x24f4 last activity / 0x1e04
/// keep-awake while audio plays). [start] with the `wakelockTimeout` option: 0 leaves the screen to the system, -1 keeps it on, 1 / 2 / 5
/// / 10 keep it on until that many minutes passed since the last [touch] (checked every second).
abstract class ReaderWakelock {
  /// The device call (wakelock_plus; tests replace it).
  static Future<void> Function(bool on) toggle = (on) => WakelockPlus.toggle(enable: on);

  /// Whether the wakelock is held (static 0x1e70).
  static bool enabled = false;

  /// Audio is playing (listening / audio books): the timer keeps renewing [lastActive] (static 0x1e04).
  static bool keepAwake = false;

  static DateTime? lastActive;
  static Timer? _timer;
  static int _seconds = 0;

  static Duration tick = const Duration(seconds: 1);

  static bool get timerRunning => _timer != null;

  static Future<void> _set(bool on) async {
    enabled = on;
    try {
      await toggle(on);
    } catch (_) {}
  }

  static Future<void> start(int option) async {
    debugPrint('开启常亮，选项: $option');
    _timer?.cancel();
    _timer = null;
    if (enabled) await _set(false);
    if (option == WakeMode.system) return;
    lastActive = DateTime.now();
    if (option == WakeMode.always) {
      debugPrint('开启常量');
      await _set(true);
      return;
    }
    _seconds = WakeMode.seconds(option);
    _timer = Timer.periodic(tick, (_) => check());
  }

  /// One tick of the timer (public for tests).
  static Future<void> check([DateTime? now]) async {
    final t = now ?? DateTime.now();
    if (keepAwake) {
      lastActive = t;
      return;
    }
    final last = lastActive;
    if (last == null) return;
    final idle = t.difference(last).inSeconds;
    if (idle >= _seconds) {
      if (enabled) await _set(false);
    } else if (!enabled) {
      await _set(true);
    }
  }

  /// User activity (a tap, a page turn).
  static void touch() => lastActive = DateTime.now();

  /// Leaving the reader.
  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (enabled) await _set(false);
  }
}
