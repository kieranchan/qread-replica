// The colour themes published on the owner's plaza (server/deploy/themes/gen_themes.py) import like plaza downloads and give the app
// their colours. Skipped when the generated packages are not present (they are built locally into artifacts/themes).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/theme.dart';
import 'package:newread/init/appinit.dart';
import 'package:newread/pages/theme/theme_package.dart';
import 'package:newread/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final dir = Directory('../artifacts/themes');
  test('plaza colour themes import and set the colours', () async {
    final root = Directory.systemTemp.createTempSync('qread_plaza_');
    addTearDown(() => root.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});
    await AppInit.init(prefs: await SharedPreferences.getInstance(), root: root);
    final zips = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList()..sort((a, b) => a.path.compareTo(b.path));
    expect(zips, hasLength(10));
    for (final z in zips) {
      final id = z.uri.pathSegments.last.replaceAll('.zip', '');
      final t = await ThemePackage.importBytes(await z.readAsBytes(), id: 'plaza_$id');
      expect(t.title, isNotEmpty);
      expect(t.isLightMode, id.startsWith('rep-day'));
      expect(ThemeColors.of(t.tabBarSelectedColor), isNotNull);
      final scheme = ThemeColors.scheme(ThemeColors.config(t.colorScheme), t.isLightMode ? Brightness.light : Brightness.dark);
      expect(scheme.primary, ThemeColors.of(t.tabBarSelectedColor));
    }
    expect(ThemeManager.themes, hasLength(10));
  }, skip: Directory('../artifacts/themes').existsSync() ? false : 'theme packages not generated');
}
