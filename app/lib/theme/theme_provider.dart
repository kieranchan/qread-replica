// theme/theme_provider.dart — the app theme: light / dark / follow-system (prefs `dark`), the installed UI theme applied to day and
// night (prefs `dayTheme` / `nightTheme` = ThemeModel ids, read by 0x818504 / 0x817b58 and loaded with the theme list in 0x1129644),
// the fonts (`navFont` / `titleFont` / `regularFont`; user overrides win over the theme), tab icons and colours, page styles
// (`styles` bound to page ids, else `regularStyle`; helpers `tablecolor` / `shadow` 0x51d744 / 0x51bf9c) and the default cover.
//
// Original: `ThemeProvider` (ChangeNotifier + WidgetsBindingObserver, one field; `setThemeMode(int)` 0xf63298 stores prefs `dark`
// through 0xf63358), held in the static `User.themeProvider` (0x3f50). Pages rebuild through `Consumer<ThemeProvider>`; the replica
// exposes [ThemeProvider.instance] as a [Listenable].
//
// Wiring (lead): `await ThemeProvider.instance.init()` after AppInit, then wrap GetMaterialApp in a ListenableBuilder and pass
// `theme: tp.lightTheme, darkTheme: tp.darkTheme, themeMode: tp.themeMode` (see [ThemeProvider.buildTheme]).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../common/app_dirs.dart';
import '../common/common.dart';
import '../data/fonts.dart';
import '../data/theme.dart';
import '../models/theme.dart';
import '../storage/storage.dart';

/// Fonts the theme pages offer. `默认字体` = the platform font; the three built-in names map to the families declared in pubspec
/// (`boldface`, `circle`); `谷歌汉字` is family `googlefont`, loaded at run time from the asset
/// `lib/util/epub/assets/dist/NotoSansSC-Regular.ttf` (0xefa450: `导入谷歌字体 …`, the same file the epub view serves).
abstract class AppFonts {
  static const String defaultName = '默认字体';
  static const String google = '谷歌汉字';
  static const String boldface = '阿里黑体';
  static const String circle = '阿里圆体';

  static const List<String> builtin = [defaultName, google, boldface, circle];

  /// Family registered for a font name ('' = platform default). User fonts are registered under their own family name.
  static String? family(String name) {
    switch (name) {
      case '':
      case defaultName:
        return null;
      case boldface:
        return 'boldface';
      case circle:
        return 'circle';
      case google:
        return googleFamily;
      default:
        return name;
    }
  }

  static const String googleFamily = 'googlefont';
  static const String googleAsset = 'lib/util/epub/assets/dist/NotoSansSC-Regular.ttf';

  static final Set<String> _loaded = <String>{};

  /// Registers a user font file with the engine (FontLoader) so `fontFamily: name` resolves. `谷歌汉字` loads its asset once
  /// (false when the asset is not bundled: the platform font is used); the pubspec families need nothing.
  static Future<bool> ensureLoaded(String name) async {
    if (name == google) {
      if (_loaded.contains(google)) return true;
      try {
        final data = await rootBundle.load(googleAsset);
        await (FontLoader(googleFamily)..addFont(Future.value(data))).load();
        _loaded.add(google);
        debugPrint('导入谷歌字体 $googleAsset');
        return true;
      } catch (_) {
        return false;
      }
    }
    if (name.isEmpty || builtin.contains(name) || _loaded.contains(name)) return true;
    final f = Fonts.byFamily(name);
    if (f == null) return false;
    try {
      final file = File(FontsData.filePath(f));
      if (!file.existsSync()) return false;
      final bytes = await file.readAsBytes();
      final loader = FontLoader(name)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      _loaded.add(name);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// All names a picker shows: the built-ins plus the imported fonts.
  static List<String> all() => [...builtin, for (final f in FontsData.fonts) f.family];
}

/// Colour helpers: the original stores colours as ARGB ints (0 = unset) and the scheme as JSON of [ColorSchemeConfig].
abstract class ThemeColors {
  static Color? of(Object? v) {
    if (v == null) return null;
    if (v is int) return v == 0 ? null : Color(v);
    if (v is num) return v == 0 ? null : Color(v.toInt());
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final hex = s.startsWith('#') ? s.substring(1) : (s.startsWith('0x') ? s.substring(2) : null);
    if (hex != null) {
      final n = int.tryParse(hex.length == 6 ? 'ff$hex' : hex, radix: 16);
      return n == null ? null : Color(n);
    }
    final n = int.tryParse(s);
    return n == null || n == 0 ? null : Color(n);
  }

  static int toInt(Color c) => c.toARGB32();

  static String hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  /// Parses a `colorScheme` text into the config (empty config for invalid text).
  static ColorSchemeConfig config(String text) {
    if (text.trim().isEmpty) return ColorSchemeConfig();
    try {
      final v = jsonDecode(text);
      if (v is Map) return ColorSchemeConfig.fromJson(Map<String, dynamic>.from(v));
    } catch (_) {}
    return ColorSchemeConfig();
  }

  /// Builds a [ColorScheme]: seeded from `seedColor` (or [fallbackSeed]), then every set role overrides the seeded value.
  static ColorScheme scheme(ColorSchemeConfig c, Brightness b, {Color fallbackSeed = const Color(0xFF4CAF50)}) {
    final seed = of(c.seedColor) ?? of(c.primary) ?? fallbackSeed;
    final s = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    return s.copyWith(
      primary: of(c.primary),
      onPrimary: of(c.onPrimary),
      primaryContainer: of(c.primaryContainer),
      onPrimaryContainer: of(c.onPrimaryContainer),
      secondary: of(c.secondary),
      onSecondary: of(c.onSecondary),
      secondaryContainer: of(c.secondaryContainer),
      onSecondaryContainer: of(c.onSecondaryContainer),
      tertiary: of(c.tertiary),
      onTertiary: of(c.onTertiary),
      tertiaryContainer: of(c.tertiaryContainer),
      onTertiaryContainer: of(c.onTertiaryContainer),
      surface: of(c.surface),
      onSurface: of(c.onSurface),
      onSurfaceVariant: of(c.onSurfaceVariant),
      surfaceContainerLow: of(c.surfaceContainerLow),
      surfaceContainerHighest: of(c.surfaceContainerHighest),
      outline: of(c.outline),
      outlineVariant: of(c.outlineVariant),
      error: of(c.error),
      onError: of(c.onError),
      errorContainer: of(c.errorContainer),
      onErrorContainer: of(c.onErrorContainer),
      shadow: of(c.shadow),
    );
  }
}

/// Typed views of the loosely typed [ThemeModel] fields (`styles`, `regularStyle`, tab icon lists).
extension ThemeModelX on ThemeModel {
  PageStyle get regular {
    final r = regularStyle;
    if (r is PageStyle) return r;
    if (r is Map) return PageStyle.fromJson(Map<String, dynamic>.from(r));
    if (r is String && r.isNotEmpty) {
      try {
        final v = jsonDecode(r);
        if (v is Map) return PageStyle.fromJson(Map<String, dynamic>.from(v));
      } catch (_) {}
    }
    return PageStyle();
  }

  List<PageStyle2> get styleList {
    final s = styles;
    final raw = s is String && s.isNotEmpty ? _tryDecode(s) : s;
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if (e is PageStyle2) e else if (e is Map) PageStyle2.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  List<String> get selectedIcons => _strings(selectedTabIcons);
  List<String> get unselectedIcons => _strings(unselectedTabIcons);

  ColorSchemeConfig get schemeConfig => ThemeColors.config(colorScheme);

  static Object? _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static List<String> _strings(Object? v) {
    final raw = v is String && v.isNotEmpty ? _tryDecode(v) : v;
    if (raw is! List) return [];
    return [for (final e in raw) e == null ? '' : '$e'];
  }

  /// A deep copy (through JSON) with the typed fields normalised to plain JSON.
  ThemeModel copy() => ThemeModel.fromJson(jsonDecode(jsonEncode(normalizedJson())) as Map<String, dynamic>);

  Map<String, dynamic> normalizedJson() {
    final j = toJson();
    j['regularStyle'] = regular.toJson();
    j['styles'] = [for (final s in styleList) s.toJson()];
    j['selectedTabIcons'] = selectedIcons;
    j['unselectedTabIcons'] = unselectedIcons;
    return j;
  }
}

/// Files referenced by a theme (backgrounds, icons, cover) are stored relative to the storage root (`themes/x.jpg`,
/// `tab_icons/y.png`) so that a reinstall that moves the documents folder keeps them valid; absolute paths are accepted as well.
abstract class ThemeFiles {
  static String resolve(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('lib/assets/')) return path;
    if (p.isAbsolute(path)) return path;
    if (!AppDirs.hasRoot) return path;
    return p.join(AppDirs.root.path, path);
  }

  static bool isAsset(String path) => path.startsWith('lib/assets/');

  /// An [ImageProvider] for a stored path (asset, file or http url); null for empty.
  static ImageProvider? image(String path) {
    if (path.isEmpty) return null;
    if (isAsset(path)) return AssetImage(path);
    if (path.startsWith('http://') || path.startsWith('https://')) return NetworkImage(path);
    final f = File(resolve(path));
    return f.existsSync() ? FileImage(f) : null;
  }
}

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  ThemeProvider._();

  /// `User.themeProvider` (static 0x3f50).
  static final ThemeProvider instance = ThemeProvider._();

  static const String darkKey = 'dark';
  static const String dayThemeKey = 'dayTheme';
  static const String nightThemeKey = 'nightTheme';
  static const String navFontKey = 'navFont';
  static const String titleFontKey = 'titleFont';
  static const String regularFontKey = 'regularFont';
  static const String useDefaultCoverForAllKey = 'useDefaultCoverForAll';

  /// The user's own default covers (JSON list of paths): the 主题设置 page keeps them as `_bookImages` and writes them under
  /// `bookimages2` (0x1098448 / 0x1098c74).
  static const String defaultCoverKey = 'bookimages2';

  /// Prefs `appearanceFollowTheme` (0xf60710): JSON map {navFont, titleFont, regularFont, defaultCover} → bool, each true (follow
  /// the applied theme) unless stored otherwise. The cover resolver 0xf60c88 uses the theme's `defaultCover` when following,
  /// else the own list; empty → `lib/assets/images/no_cover.jpeg`; a value starting with `[` is a JSON list.
  static const String followThemeKey = 'appearanceFollowTheme';
  static const List<String> followItems = ['navFont', 'titleFont', 'regularFont', 'defaultCover'];

  /// Tab ids in the default bottom-bar order (`bottomBarTabs` default, 0xf62c0c), the index of the tab icon lists.
  static const List<String> tabNames = ['书架', '发现', '探索', '订阅', '我的'];

  /// 0 = follow system, 1 = light, 2 = dark [infer from the three icons of the me page action].
  int mode = 0;

  bool _observing = false;

  /// Loads the theme list and the selection; safe to call again.
  Future<void> init() async {
    mode = Storage.getInt(darkKey, 0).clamp(0, 2);
    await ThemeManager.load();
    for (final n in [navFont, titleFont, regularFont]) {
      await AppFonts.ensureLoaded(n);
    }
    if (!_observing) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      } catch (_) {}
    }
    _refreshAppbar();
    notifyListeners();
  }

  /// 0xf63298.
  Future<void> setThemeMode(int value) async {
    mode = value.clamp(0, 2);
    await Storage.setInt(darkKey, mode);
    _refreshAppbar();
    notifyListeners();
  }

  /// Cycles follow-system → light → dark (the me page's app bar button).
  Future<void> cycleMode() => setThemeMode((mode + 1) % 3);

  ThemeMode get themeMode => switch (mode) { 1 => ThemeMode.light, 2 => ThemeMode.dark, _ => ThemeMode.system };

  IconData get modeIcon => switch (mode) { 1 => Icons.light_mode_outlined, 2 => Icons.dark_mode_outlined, _ => Icons.brightness_auto_outlined };

  /// The effective brightness (follow-system uses the platform brightness).
  bool get isDark {
    if (mode == 1) return false;
    if (mode == 2) return true;
    try {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    } catch (_) {
      return ui.PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    }
  }

  @override
  void didChangePlatformBrightness() {
    _refreshAppbar();
    notifyListeners();
  }

  // ------------------------------------------------------------------------------------------------ applied themes

  String get dayThemeId => Storage.getString(dayThemeKey);
  String get nightThemeId => Storage.getString(nightThemeKey);

  ThemeModel? get dayTheme => ThemeManager.byId(dayThemeId);
  ThemeModel? get nightTheme => ThemeManager.byId(nightThemeId);

  /// The theme for the current brightness.
  ThemeModel? get current => isDark ? nightTheme : dayTheme;

  ThemeModel? themeFor(Brightness b) => b == Brightness.dark ? nightTheme : dayTheme;

  bool isApplied(ThemeModel t) => t.id.isNotEmpty && (t.isLightMode ? dayThemeId == t.id : nightThemeId == t.id);

  /// Applies an installed theme to its mode (day themes to light, night themes to dark).
  Future<void> applyTheme(ThemeModel t) async {
    await Storage.setString(t.isLightMode ? dayThemeKey : nightThemeKey, t.id);
    for (final n in [t.navFont, t.titleFont, t.regularFont]) {
      await AppFonts.ensureLoaded(n);
    }
    _refreshAppbar();
    notifyListeners();
  }

  /// 取消应用: the mode falls back to the built-in look.
  Future<void> cancelTheme(bool isLight) async {
    await Storage.setString(isLight ? dayThemeKey : nightThemeKey, '');
    _refreshAppbar();
    notifyListeners();
  }

  /// Call after the theme list changed (edit / delete) so listeners repaint.
  void refresh() {
    _refreshAppbar();
    notifyListeners();
  }

  // ------------------------------------------------------------------------------------------------ fonts

  Map<String, bool> get followTheme {
    // unset items follow the theme unless an own value exists (consistent with the original, where picking an own value is what
    // turns following off; keeps choices made by earlier replica builds)
    final out = {for (final k in followItems) k: k == 'defaultCover' ? ownCovers.isEmpty : Storage.getString(k).isEmpty};
    try {
      final v = jsonDecode(Storage.getString(followThemeKey));
      if (v is Map) {
        v.forEach((k, b) {
          if (b is bool) out['$k'] = b;
        });
      }
    } catch (_) {}
    return out;
  }

  /// Whether [item] (`navFont` / `titleFont` / `regularFont` / `defaultCover`) follows the applied theme.
  bool follows(String item) => followTheme[item] ?? true;

  Future<void> setFollows(String item, bool v) async {
    final m = followTheme..[item] = v;
    await Storage.setString(followThemeKey, jsonEncode(m));
    notifyListeners();
  }

  String _font(String key, String Function(ThemeModel) fromTheme) => _resolveFont(current, key, fromTheme);

  /// Following: the theme's font (the own one when the theme has none); not following: the own font.
  String _resolveFont(ThemeModel? t, String key, String Function(ThemeModel) fromTheme) {
    final own = Storage.getString(key);
    final theirs = t == null ? '' : fromTheme(t);
    if (follows(key)) return theirs.isNotEmpty ? theirs : own;
    return own;
  }

  String get navFont => _font(navFontKey, (t) => t.navFont);
  String get titleFont => _font(titleFontKey, (t) => t.titleFont);
  String get regularFont => _font(regularFontKey, (t) => t.regularFont);

  /// The user's own choice ('' = 跟随主题).
  String ownFont(String key) => Storage.getString(key);

  /// Picking a font stops following the theme for that item; picking '' (跟随主题) follows it again.
  Future<void> setOwnFont(String key, String name) async {
    await Storage.setString(key, name);
    await setFollows(key, name.isEmpty);
    await AppFonts.ensureLoaded(name);
    notifyListeners();
  }

  // ------------------------------------------------------------------------------------------------ covers

  List<String> get ownCovers {
    final s = Storage.getString(defaultCoverKey);
    if (s.isEmpty) return [];
    try {
      final v = jsonDecode(s);
      if (v is List) return [for (final e in v) '$e'];
    } catch (_) {}
    return [];
  }

  Future<void> setOwnCovers(List<String> paths) async {
    await Storage.setString(defaultCoverKey, paths.isEmpty ? '' : jsonEncode(paths));
    await setFollows('defaultCover', paths.isEmpty);
  }

  /// 0xf60c88: the covers used when a book has none — the theme's when following it, else the own list; the bundled
  /// `no_cover.jpeg` when that is empty.
  List<String> get defaultCovers {
    final t = current;
    final theirs = t == null ? '' : t.defaultCover.trim();
    List<String> list;
    if (follows('defaultCover')) {
      list = theirs.startsWith('[') ? _list(theirs) : (theirs.isEmpty ? <String>[] : [theirs]);
      if (list.isEmpty) list = ownCovers;
    } else {
      list = ownCovers;
    }
    return list.isEmpty ? const ['lib/assets/images/no_cover.jpeg'] : list;
  }

  static List<String> _list(String s) {
    try {
      final v = jsonDecode(s);
      if (v is List) return [for (final e in v) '$e'];
    } catch (_) {}
    return [];
  }

  /// true = every book shows the default cover; false = only when loading the cover failed (仅加载失败).
  bool get useDefaultCoverForAll {
    if (Storage.containsKey(useDefaultCoverForAllKey)) return Storage.getBool(useDefaultCoverForAllKey);
    return current?.useDefaultCoverForAll ?? false;
  }

  Future<void> setUseDefaultCoverForAll(bool v) async {
    await Storage.setBool(useDefaultCoverForAllKey, v);
    notifyListeners();
  }

  // ------------------------------------------------------------------------------------------------ tab bar

  /// The icon file of tab [index] (`selected` or not) of the current theme, '' when the theme has none.
  String tabIcon(int index, {required bool selected}) {
    final t = current;
    if (t == null) return '';
    final list = selected ? t.selectedIcons : t.unselectedIcons;
    return index >= 0 && index < list.length ? list[index] : '';
  }

  Color? get tabBarColor => ThemeColors.of(current?.tabBarColor);
  Color? get tabBarSelectedColor => ThemeColors.of(current?.tabBarSelectedColor);
  bool get showTitleWhenSelected => current?.showTitleWhenSelected ?? true;
  bool get showTitleWhenUnselected => current?.showTitleWhenUnselected ?? true;

  // ------------------------------------------------------------------------------------------------ page styles

  /// The style for a page id (`me`, `fontsetting`, `wifi`, ...): the first entry of `styles` bound to it, else `regularStyle`.
  PageStyle pageStyle(String page) {
    final t = current;
    if (t == null) return PageStyle();
    for (final s in t.styleList) {
      if (s.types.map((e) => '$e').contains(page)) {
        return PageStyle(
            backgroundImage: s.backgroundImage, backgroundColor: s.backgroundColor, tableOpacity: s.tableOpacity, showboxShadow: s.showboxShadow);
      }
    }
    return t.regular;
  }

  /// `tablecolor(page)` 0x51d744: the card colour with the page's table opacity (0 = opaque).
  Color tableColor(String page, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = pageStyle(page);
    final base = cs.surfaceContainerLow;
    if (s.tableOpacity <= 0) return base;
    return base.withValues(alpha: (100 - s.tableOpacity.clamp(0, 100)) / 100);
  }

  /// `shadow(page)` 0x51bf9c.
  List<BoxShadow> shadow(String page) {
    final t = current;
    if (t == null) return [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))];
    return pageStyle(page).showboxShadow
        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))]
        : const [];
  }

  /// Background colour and image of a page (null = scaffold default).
  Color? pageBackground(String page) => ThemeColors.of(pageStyle(page).backgroundColor);
  ImageProvider? pageImage(String page) => ThemeFiles.image(pageStyle(page).backgroundImage);

  // ------------------------------------------------------------------------------------------------ ThemeData

  ThemeData get lightTheme => buildTheme(Brightness.light);
  ThemeData get darkTheme => buildTheme(Brightness.dark);

  /// The ThemeData for one brightness: colour scheme of the theme applied to that mode, its text colour and fonts.
  ThemeData buildTheme(Brightness b) {
    final t = themeFor(b);
    final scheme = t == null
        ? ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50), brightness: b)
        : ThemeColors.scheme(t.schemeConfig, b);
    final regular = AppFonts.family(_fontFor(b, regularFontKey, (x) => x.regularFont));
    final title = AppFonts.family(_fontFor(b, titleFontKey, (x) => x.titleFont));
    final nav = AppFonts.family(_fontFor(b, navFontKey, (x) => x.navFont));
    final textColor = ThemeColors.of(t?.textColor);
    var base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: regular, brightness: b);
    var text = base.textTheme;
    if (textColor != null) text = text.apply(bodyColor: textColor, displayColor: textColor);
    if (title != null) {
      text = text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontFamily: title),
        titleMedium: text.titleMedium?.copyWith(fontFamily: title),
        headlineSmall: text.headlineSmall?.copyWith(fontFamily: title),
      );
    }
    final cfg = t?.schemeConfig;
    final dialogBg = ThemeColors.of(cfg?.dialogBackground);
    final popupBg = ThemeColors.of(cfg?.popupMenuBackground);
    final tagBg = ThemeColors.of(cfg?.tagBackground);
    final tagText = ThemeColors.of(cfg?.tagText);
    final barColor = ThemeColors.of(t?.tabBarColor);
    final barSelected = ThemeColors.of(t?.tabBarSelectedColor);
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontFamily: title, fontSize: 18, fontWeight: FontWeight.w600, color: textColor ?? scheme.onSurface),
      ),
      dialogTheme: dialogBg == null ? null : DialogThemeData(backgroundColor: dialogBg),
      popupMenuTheme: popupBg == null ? null : PopupMenuThemeData(color: popupBg),
      chipTheme: tagBg == null && tagText == null
          ? null
          : ChipThemeData(backgroundColor: tagBg, labelStyle: TextStyle(color: tagText)),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: barColor,
        indicatorColor: barSelected?.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontFamily: nav, fontSize: 12)),
      ),
    );
  }

  String _fontFor(Brightness b, String key, String Function(ThemeModel) fromTheme) => _resolveFont(themeFor(b), key, fromTheme);

  void _refreshAppbar() {
    final c = ThemeColors.of(current?.schemeConfig.surface);
    Common.appbarcolor = c ?? (isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF));
  }

  @override
  void dispose() {
    // the singleton lives for the whole app; only tests dispose copies
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
