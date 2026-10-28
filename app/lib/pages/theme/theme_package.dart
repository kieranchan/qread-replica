// pages/theme/theme_package.dart — theme files (`.qtheme` / `.zip`): import (0xff5eb8, the 导入主题 closure of the theme manager) and
// export (theme item 导出). A package is a zip with `theme.json` (a [ThemeModel]) next to the files it references, sorted into
// `themes/` (backgrounds, icon, cover), `tab_icons/` and `fonts/`.
//
// Import as in the original: unpack into `<root>/importtheme/`, require `theme.json` (`主题文件格式错误：缺少theme.json`), copy every
// referenced image into `<root>/themes` or `<root>/tab_icons` under its md5 name, register bundled fonts (data/fonts.dart), refuse a
// package of the wrong mode when the caller asks for one (`当前主题不是日间模式` / `…夜间模式`), give it a fresh uuid and install it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../../common/app_dirs.dart';
import '../../data/fonts.dart';
import '../../data/ground.dart';
import '../../data/list_store.dart';
import '../../data/theme.dart';
import '../../models/back_ground.dart';
import '../../models/font.dart';
import '../../models/theme.dart';
import '../../theme/theme_provider.dart';

class ThemePackageException implements Exception {
  final String message;
  const ThemePackageException(this.message);
  @override
  String toString() => message;
}

abstract class ThemePackage {
  static const String themeJson = 'theme.json';
  static const List<String> extensions = ['qtheme', 'zip'];

  static String _norm(String name) => name.replaceAll('\\', '/');

  /// Imports a package. [expectLight] (null = any) is the mode of the manager tab the import was started from. Returns the
  /// installed theme (fresh id unless [id] is given: plaza downloads keep `plaza_<id>` so 更新主题 replaces them in place).
  static Future<ThemeModel> importBytes(List<int> bytes, {bool? expectLight, String? id, String? version}) async {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw ThemePackageException('导入主题失败: $e');
    }
    final files = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (f.isFile) files[_norm(f.name)] = f;
    }
    final jsonEntry = files.entries.where((e) => p.posix.basename(e.key) == themeJson).firstOrNull;
    if (jsonEntry == null) throw const ThemePackageException('主题文件格式错误：缺少theme.json');
    final prefix = p.posix.dirname(jsonEntry.key) == '.' ? '' : '${p.posix.dirname(jsonEntry.key)}/';
    Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(jsonDecode(utf8.decode(jsonEntry.value.content)) as Map);
    } catch (_) {
      throw const ThemePackageException('主题文件格式错误：缺少theme.json');
    }
    final theme = ThemeModel.fromJson(map);
    if (expectLight != null && theme.isLightMode != expectLight) {
      throw ThemePackageException('当前主题不是${expectLight ? '日间' : '夜间'}模式');
    }

    ArchiveFile? find(String ref) {
      if (ref.isEmpty) return null;
      final n = _norm(ref);
      return files['$prefix$n'] ?? files[n] ?? files.entries.where((e) => p.posix.basename(e.key) == p.posix.basename(n)).firstOrNull?.value;
    }

    Future<String> store(String ref, String dir) async {
      if (ref.isEmpty || ThemeFiles.isAsset(ref) || ref.startsWith('http')) return ref;
      final f = find(ref);
      if (f == null) return '';
      final data = f.content;
      final name = '${crypto.md5.convert(data)}${p.extension(f.name)}';
      final d = await AppDirs.ensure(dir);
      final out = File(p.join(d.path, name));
      if (!out.existsSync()) await out.writeAsBytes(data, flush: true);
      return '$dir/$name';
    }

    theme.icon = await store(theme.icon, 'themes');
    theme.defaultCover = await store(theme.defaultCover, 'themes');
    theme.startupScreen = await store(theme.startupScreen, 'themes');
    final regular = theme.regular;
    regular.backgroundImage = await store(regular.backgroundImage, 'themes');
    theme.regularStyle = regular.toJson();
    final styles = theme.styleList;
    for (final s in styles) {
      s.backgroundImage = await store(s.backgroundImage, 'themes');
    }
    theme.styles = [for (final s in styles) s.toJson()];
    theme.selectedTabIcons = [for (final i in theme.selectedIcons) await store(i, 'tab_icons')];
    theme.unselectedTabIcons = [for (final i in theme.unselectedIcons) await store(i, 'tab_icons')];

    // fonts shipped in the package: registered under their file name unless a font of that name exists
    await FontsData.load();
    for (final e in files.entries) {
      final ext = p.extension(e.key).toLowerCase();
      if (ext != '.ttf' && ext != '.otf') continue;
      final family = p.posix.basenameWithoutExtension(e.key);
      if (Fonts.byFamily(family) != null || AppFonts.builtin.contains(family)) continue;
      final d = await AppDirs.ensure('fonts');
      final name = '${DateTime.now().microsecondsSinceEpoch}_${p.posix.basename(e.key)}';
      await File(p.join(d.path, name)).writeAsBytes(e.value.content, flush: true);
      await Fonts.add(Font(family: family, path: name));
    }

    theme.id = id ?? newId();
    if (version != null && version.isNotEmpty) theme.version = version;
    final now = DateTime.now().millisecondsSinceEpoch;
    theme.createdAt ??= now;
    theme.updatedAt = now;
    await ThemeManager.install(ThemeModel.fromJson(theme.normalizedJson()));
    return ThemeManager.byId(theme.id)!;
  }

  static Future<ThemeModel> importFile(File file, {bool? expectLight}) async => importBytes(await file.readAsBytes(), expectLight: expectLight);

  /// Builds the package bytes of an installed theme.
  static Future<Uint8List> exportBytes(ThemeModel source) async {
    final theme = source.copy();
    final archive = Archive();
    final added = <String>{};

    Future<String> put(String ref, String dir) async {
      if (ref.isEmpty || ThemeFiles.isAsset(ref) || ref.startsWith('http')) return ref;
      final f = File(ThemeFiles.resolve(ref));
      if (!f.existsSync()) return '';
      final name = '$dir/${p.basename(f.path)}';
      if (added.add(name)) archive.addFile(ArchiveFile.bytes(name, await f.readAsBytes()));
      return name;
    }

    theme.icon = await put(theme.icon, 'themes');
    theme.defaultCover = await put(theme.defaultCover, 'themes');
    theme.startupScreen = await put(theme.startupScreen, 'themes');
    final regular = theme.regular..backgroundImage = await put(theme.regular.backgroundImage, 'themes');
    theme.regularStyle = regular.toJson();
    final styles = theme.styleList;
    for (final s in styles) {
      s.backgroundImage = await put(s.backgroundImage, 'themes');
    }
    theme.styles = [for (final s in styles) s.toJson()];
    theme.selectedTabIcons = [for (final i in theme.selectedIcons) await put(i, 'tab_icons')];
    theme.unselectedTabIcons = [for (final i in theme.unselectedIcons) await put(i, 'tab_icons')];
    for (final name in {theme.navFont, theme.titleFont, theme.regularFont}) {
      final f = Fonts.byFamily(name);
      if (f == null) continue;
      final file = File(FontsData.filePath(f));
      if (!file.existsSync()) continue;
      final entry = 'fonts/$name${p.extension(file.path)}';
      if (added.add(entry)) archive.addFile(ArchiveFile.bytes(entry, await file.readAsBytes()));
    }
    archive.addFile(ArchiveFile.string(themeJson, const JsonEncoder.withIndent('  ').convert(theme.normalizedJson())));
    return ZipEncoder().encodeBytes(archive);
  }

  /// Writes the package to `<root>/cache/<title>.qtheme` and returns the file (for share / save).
  static Future<File> exportFile(ThemeModel theme) async {
    final d = await AppDirs.ensure('cache');
    final safe = theme.title.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    final f = File(p.join(d.path, '${safe.isEmpty ? '主题' : safe}.qtheme'));
    await f.writeAsBytes(await exportBytes(theme), flush: true);
    return f;
  }

  /// 内置排版方案 of a plaza theme (layout file, 0x103e31c): a JSON list of reading layouts ([BackGround] maps, or `{data:[...]}`).
  /// Background images embedded as data urls (`…base64;…` / `…base64,…`) are written to `<root>/images` (`正在上传背景图`); layouts
  /// are added to `Ground` with fresh numbers. A layout may carry its font as base64 under `f` (0x103e31c: `尝试导入字体`): the file is
  /// written to `<root>/fonts/<fontFamily>` and registered under the layout's `fontFamily` unless that family exists. Returns the
  /// number imported.
  static Future<int> importLayouts(String text) async {
    Object? v;
    try {
      v = jsonDecode(text);
    } catch (_) {
      throw const ThemePackageException('排版文件格式错误');
    }
    if (v is Map && v['data'] is List) v = v['data'];
    if (v is Map) v = [v];
    if (v is! List) throw const ThemePackageException('排版文件格式错误');
    var n = 0;
    for (final e in v) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      for (final k in ['backgroundimage', 'backgroundimage2', 'backgroundimage3']) {
        final s = '${m[k] ?? ''}';
        final i = s.indexOf('base64');
        if (i < 0) continue;
        try {
          final data = base64Decode(s.substring(i + 7).trim());
          final name = '${crypto.md5.convert(data)}.jpg';
          final d = await AppDirs.ensure('images');
          final out = File(p.join(d.path, name));
          if (!out.existsSync()) await out.writeAsBytes(data, flush: true);
          m[k] = out.path;
        } catch (_) {
          m[k] = '';
        }
      }
      final f = m.remove('f');
      final family = '${m['fontFamily'] ?? ''}'.trim();
      if (f is String && f.isNotEmpty && family.isNotEmpty && Fonts.byFamily(family) == null) {
        try {
          final data = base64Decode(f.contains('base64') ? f.substring(f.indexOf('base64') + 7).trim() : f.trim());
          debugPrint('尝试导入字体');
          final d = await AppDirs.ensure('fonts');
          final name = family.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          await File(p.join(d.path, name)).writeAsBytes(data, flush: true);
          await Fonts.add(Font(family: family, path: name));
        } catch (e) {
          debugPrint('字体导入失败 $e');
        }
      }
      m['name'] = 0;
      await Ground.add(BackGround.fromJson(m));
      n++;
    }
    return n;
  }

  /// Copies an image the user picked into `<root>/<dir>` under its md5 name; returns the stored relative path.
  static Future<String> storeImage(File source, String dir) async {
    final data = await source.readAsBytes();
    final name = '${crypto.md5.convert(data)}${p.extension(source.path).toLowerCase()}';
    final d = await AppDirs.ensure(dir);
    final out = File(p.join(d.path, name));
    if (!out.existsSync()) await out.writeAsBytes(data, flush: true);
    return '$dir/$name';
  }
}
