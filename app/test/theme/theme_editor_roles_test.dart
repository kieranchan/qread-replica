// The theme editor's colour roles (pages/theme/new_theme_page.dart): grouped and named as the original (0x6b324c), every role of
// the colour scheme exactly once.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/theme/new_theme_page.dart';

void main() {
  test('colour groups cover every role once, with the original names', () {
    final keys = themeColorRoles.map((r) => r.$1).toList();
    expect(keys.toSet().length, keys.length, reason: 'no role twice');
    expect(keys.toSet(), {
      'seedColor', 'primary', 'onPrimary', 'secondary', 'onSecondary', 'primaryContainer', 'onPrimaryContainer', 'secondaryContainer',
      'onSecondaryContainer', 'tertiary', 'onTertiary', 'tertiaryContainer', 'onTertiaryContainer', 'surface', 'onSurface',
      'onSurfaceVariant', 'surfaceContainerLow', 'surfaceContainerHighest', 'outline', 'outlineVariant', 'error', 'onError',
      'errorContainer', 'onErrorContainer', 'shadow', 'dialogBackground', 'popupMenuBackground', 'tagBackground', 'tagText',
    });
    expect(themeColorGroups.map((g) => g.$1).toList(), ['主要颜色', '表面和容器颜色', '边框和轮廓', '功能颜色', '弹窗和菜单背景', '详情页标签和按钮颜色', '补充颜色（可选）']);
    final labels = {for (final r in themeColorRoles) r.$1: r.$2};
    expect(labels['primaryContainer'], '主容器 (PrimaryContainer)');
    expect(labels['tagText'], '标签文字 (TagText)');
    expect(labels['onTertiary'], '第三色调文本 (OnTertiary)');
    expect(themeSeedRole.$2, '主题默认颜色');
  });
}
