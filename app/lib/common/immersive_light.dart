// common/immersive_light.dart — the 沉浸光感 level shared by the main page (startup choice), the reading settings (selector) and the
// glass widgets (`widget/ui`, liquid_glass_easy). Prefs `immersiveLight2223`, read by the original as `toInt(getString(...))`
// (0x926f70), written as text (0x10956fc): 2 强 (strongest effect), 1 均衡, 0 弱 (no glass).
import 'package:flutter/foundation.dart';

import '../storage/storage.dart';

abstract class ImmersiveLight {
  static const key = 'immersiveLight2223';
  static const strong = 2;
  static const balanced = 1;
  static const off = 0;

  /// Current level; widgets listen to it.
  static final ValueNotifier<int> level = ValueNotifier<int>(Storage.getInt(key));

  /// True while the user has not chosen yet (the main page asks once).
  static bool get unset => Storage.getString(key).isEmpty;

  static Future<void> set(int value) async {
    final v = value.clamp(off, strong);
    await Storage.setInt(key, v);
    level.value = v;
  }

  /// Re-reads the stored value (after a backup restore).
  static void reload() => level.value = Storage.getInt(key);
}
