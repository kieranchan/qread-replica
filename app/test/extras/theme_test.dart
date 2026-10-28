// Theme layer: ThemeProvider (mode, applied themes, fonts, page styles, ThemeData), theme packages (zip import / export, layouts) and
// the plaza client against a local HttpServer.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/system.dart';
import 'package:newread/data/fonts.dart';
import 'package:newread/data/ground.dart';
import 'package:newread/data/theme.dart';
import 'package:newread/models/theme.dart';
import 'package:newread/pages/theme/theme_api.dart';
import 'package:newread/pages/theme/theme_detail_page.dart';
import 'package:newread/pages/theme/theme_package.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/theme/theme_provider.dart';

import '../support/env.dart';

ThemeModel sampleTheme({bool light = true, String id = 't1'}) => ThemeModel(
      id: id,
      title: light ? '晨光' : '夜色',
      author: 'me',
      icon: 'themes/icon.png',
      isLightMode: light,
      textColor: 0xFF112233,
      tabBarColor: 0xFFEEEEEE,
      colorScheme: jsonEncode({'seedColor': 0xFF3F51B5, 'primary': 0xFFAA0000, 'dialogBackground': 0xFF101010}),
      regularStyle: {'backgroundImage': 'themes/bg.jpg', 'backgroundColor': 0xFFFAFAFA, 'tableOpacity': 20, 'showboxShadow': true},
      styles: [
        {'name': '我的页', 'backgroundImage': '', 'backgroundColor': 0xFF00FF00, 'tableOpacity': 50, 'showboxShadow': false, 'types': ['me']},
      ],
      selectedTabIcons: ['tab_icons/a.png', '', '', '', ''],
      unselectedTabIcons: ['tab_icons/b.png', '', '', '', ''],
      navFont: '阿里黑体',
      regularFont: '阿里圆体',
    );

void main() {
  late TestDevice dev;
  setUp(() async {
    dev = await newDevice();
    await ThemeManager.load();
    await FontsData.load();
  });
  tearDown(() => dev.delete());

  group('ThemeColors', () {
    test('parses ints, hex text and builds a scheme whose set roles win over the seed', () {
      expect(ThemeColors.of(0), isNull);
      expect(ThemeColors.of(0xFF123456), const Color(0xFF123456));
      expect(ThemeColors.of('#FF0000'), const Color(0xFFFF0000));
      expect(ThemeColors.of('#80FF0000'), const Color(0x80FF0000));
      final cfg = ThemeColors.config(jsonEncode({'seedColor': 0xFF3F51B5, 'primary': 0xFFAA0000}));
      final s = ThemeColors.scheme(cfg, Brightness.dark);
      expect(s.primary, const Color(0xFFAA0000));
      expect(s.brightness, Brightness.dark);
      expect(ThemeColors.config('not json').primary, isNull);
    });
  });

  group('ThemeProvider', () {
    final tp = ThemeProvider.instance;

    test('mode is stored as prefs text under `dark` and cycles 0→1→2→0', () async {
      await tp.setThemeMode(2);
      expect(Storage.getString('dark'), '2');
      expect(tp.themeMode, ThemeMode.dark);
      expect(tp.isDark, isTrue);
      await tp.cycleMode();
      expect(tp.mode, 0);
      await tp.setThemeMode(1);
      expect(tp.isDark, isFalse);
    });

    test('applying a day theme writes dayTheme, cancelling clears it; ThemeData follows the theme', () async {
      await tp.setThemeMode(1);
      await ThemeManager.install(sampleTheme());
      final t = ThemeManager.byId('t1')!;
      await tp.applyTheme(t);
      expect(Storage.getString('dayTheme'), 't1');
      expect(tp.isApplied(t), isTrue);
      expect(tp.current?.title, '晨光');
      final data = tp.lightTheme;
      expect(data.colorScheme.primary, const Color(0xFFAA0000));
      expect(data.textTheme.bodyMedium?.color, const Color(0xFF112233));
      expect(data.dialogTheme.backgroundColor, const Color(0xFF101010));
      expect(tp.navFont, '阿里黑体');
      expect(AppFonts.family(tp.regularFont), 'circle');
      expect(tp.tabIcon(0, selected: true), 'tab_icons/a.png');
      expect(tp.tabBarColor, const Color(0xFFEEEEEE));
      // the dark theme is untouched by a day theme
      expect(tp.darkTheme.colorScheme.primary, isNot(const Color(0xFFAA0000)));
      await tp.cancelTheme(true);
      expect(Storage.getString('dayTheme'), '');
      expect(tp.current, isNull);
    });

    test('page styles: a style bound to the page wins, others fall back to regularStyle; own fonts override the theme', () async {
      await tp.setThemeMode(1);
      await ThemeManager.install(sampleTheme());
      await tp.applyTheme(ThemeManager.byId('t1')!);
      expect(tp.pageStyle('me').tableOpacity, 50);
      expect(ThemeColors.of(tp.pageStyle('me').backgroundColor), const Color(0xFF00FF00));
      expect(tp.pageStyle('wifi').tableOpacity, 20);
      expect(tp.pageStyle('wifi').showboxShadow, isTrue);
      await tp.setOwnFont(ThemeProvider.navFontKey, '谷歌汉字');
      expect(tp.navFont, '谷歌汉字');
      await tp.setOwnFont(ThemeProvider.navFontKey, '');
      expect(tp.navFont, '阿里黑体');
      expect(tp.defaultCovers, ['lib/assets/images/no_cover.jpeg']);
      await tp.setOwnCovers(['covers/x.jpg']);
      expect(tp.defaultCovers, ['covers/x.jpg']);
      // appearanceFollowTheme: following the theme ignores the own choice until the flag is cleared
      expect(jsonDecode(Storage.getString(ThemeProvider.followThemeKey)), containsPair('defaultCover', false));
      await tp.setFollows(ThemeProvider.navFontKey, true);
      await tp.setOwnFont(ThemeProvider.navFontKey, '阿里圆体');
      expect(tp.follows(ThemeProvider.navFontKey), isFalse);
      expect(tp.navFont, '阿里圆体');
      await tp.setFollows(ThemeProvider.navFontKey, true);
      expect(tp.navFont, '阿里黑体', reason: 'the theme font wins while following');
      await tp.setFollows('defaultCover', true);
      expect(tp.defaultCovers, ['covers/x.jpg'], reason: 'a theme without cover falls back to the own list');
      expect(AppFonts.family('谷歌汉字'), 'googlefont');
    });

    test('System.pagenames: the 69 name -> id pairs of the original, reverse lookup for the editor', () {
      expect(System.pagenames.length, 69);
      expect(System.pagenames['书架'], 'book');
      expect(System.pagenames['阅读统计'], 'readtj');
      expect(System.pageTitles['fontsetting'], '字体设置');
      expect(System.pageTitles['me'], '我的');
    });
  });

  group('ThemePackage', () {
    Future<List<int>> buildZip(Map<String, dynamic> theme, {Map<String, List<int>> files = const {}}) async {
      final a = Archive()..addFile(ArchiveFile.string('pkg/theme.json', jsonEncode(theme)));
      files.forEach((k, v) => a.addFile(ArchiveFile.bytes('pkg/$k', v)));
      return ZipEncoder().encodeBytes(a);
    }

    test('import copies referenced images under md5 names, registers bundled fonts and installs with a fresh id', () async {
      final zip = await buildZip(sampleTheme().toJson(), files: {
        'themes/icon.png': [1, 2, 3],
        'themes/bg.jpg': [4, 5, 6],
        'tab_icons/a.png': [7],
        'tab_icons/b.png': [8],
        'fonts/我的字体.ttf': [0, 1, 0, 0],
      });
      final t = await ThemePackage.importBytes(zip, expectLight: true);
      expect(t.id, isNot('t1'));
      expect(ThemeManager.themes.length, 1);
      expect(t.icon, startsWith('themes/'));
      expect(File(ThemeFiles.resolve(t.icon)).readAsBytesSync(), [1, 2, 3]);
      expect(File(ThemeFiles.resolve(t.regular.backgroundImage)).readAsBytesSync(), [4, 5, 6]);
      expect(File(ThemeFiles.resolve(t.selectedIcons.first)).readAsBytesSync(), [7]);
      expect(t.selectedIcons.length, 5);
      expect(Fonts.byFamily('我的字体'), isNotNull);
    });

    test('a package without theme.json or of the wrong mode is refused with the original messages', () async {
      final noJson = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.string('a.txt', 'x')));
      await expectLater(ThemePackage.importBytes(noJson), throwsA(predicate((e) => '$e' == '主题文件格式错误：缺少theme.json')));
      final night = await buildZip(sampleTheme(light: false).toJson());
      await expectLater(ThemePackage.importBytes(night, expectLight: true), throwsA(predicate((e) => '$e' == '当前主题不是日间模式')));
    });

    test('export → import round trip keeps fields and files', () async {
      for (final f in ['themes/icon.png', 'themes/bg.jpg', 'tab_icons/a.png', 'tab_icons/b.png']) {
        File(ThemeFiles.resolve(f))
          ..createSync(recursive: true)
          ..writeAsBytesSync(utf8.encode(f));
      }
      await ThemeManager.install(sampleTheme());
      final bytes = await ThemePackage.exportBytes(ThemeManager.byId('t1')!);
      final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toSet();
      expect(names, containsAll(['theme.json', 'themes/icon.png', 'themes/bg.jpg', 'tab_icons/a.png']));
      final back = await ThemePackage.importBytes(bytes, id: 'copy');
      expect(back.title, '晨光');
      expect(back.styleList.single.types, ['me']);
      expect(utf8.decode(File(ThemeFiles.resolve(back.regular.backgroundImage)).readAsBytesSync()), 'themes/bg.jpg');
    });

    test('layouts of a plaza theme become reading layouts; data-url images are written out', () async {
      await Ground.load();
      final n = await ThemePackage.importLayouts(jsonEncode([
        {'name': 3, 'themeName': '护眼', 'backgroundColor': '#C7EDCC', 'backgroundimage': 'data:image/jpeg;base64,${base64Encode([9, 9, 9])}'},
        {'themeName': '夜读', 'backgroundColor': '#000000'},
      ]));
      expect(n, 2);
      expect(Ground.grounds.map((g) => g.themeName), ['护眼', '夜读']);
      expect(File(Ground.grounds.first.backgroundimage).readAsBytesSync(), [9, 9, 9]);
    });

    test('a layout may carry its font as base64 under f: written to fonts/ and registered once', () async {
      await Ground.load();
      await FontsData.load();
      final n = await ThemePackage.importLayouts(jsonEncode([
        {'themeName': '宋体版', 'fontFamily': '方正书宋', 'f': base64Encode([1, 2, 3, 4])},
        {'themeName': '同字体', 'fontFamily': '方正书宋', 'f': base64Encode([7])},
      ]));
      expect(n, 2);
      final font = Fonts.byFamily('方正书宋')!;
      expect(File(FontsData.filePath(font)).readAsBytesSync(), [1, 2, 3, 4]);
      expect(FontsData.fonts.length, 1);
      expect(Ground.grounds.map((g) => g.fontFamily), ['方正书宋', '方正书宋']);
    });
  });

  group('ThemePlazaApi', () {
    late HttpServer server;
    late ThemePlazaApi api;
    final seen = <String>[];

    setUp(() async {
      seen.clear();
      final zip = ZipEncoder().encodeBytes(Archive()
        ..addFile(ArchiveFile.string('theme.json', jsonEncode(sampleTheme(light: false).toJson()..['icon'] = 'themes/i.png')))
        ..addFile(ArchiveFile.bytes('themes/i.png', [1])));
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seen.add(req.uri.toString());
        final res = req.response..headers.contentType = ContentType.json;
        switch (req.uri.path) {
          case '/public/themes':
            final page = int.parse(req.uri.queryParameters['page'] ?? '1');
            res.write(jsonEncode({
              'code': 200,
              'data': {
                'items': [
                  {'id': page * 10, 'name': '主题$page', 'theme_mode': page == 1 ? 'day' : 'night', 'zip_path': 'public/files/t.zip', 'author': '', 'category': {'id': 2, 'name': '清新'}},
                ],
                'total': 2,
                'page': page,
                'limit': 1,
                'max_page': 2,
              },
            }));
          case '/public/categories':
            res.write(jsonEncode({'code': 200, 'data': [{'id': 2, 'name': '清新'}]}));
          case '/public/themes/10':
            res.write(jsonEncode({'code': 200, 'data': {'id': 10, 'name': '主题1', 'version': '1.1', 'zip_path': '/public/files/t.zip', 'theme_mode': 'night'}}));
          case '/public/themes/404':
            res.write(jsonEncode({'code': 404, 'message': 'not found'}));
          case '/public/files/t.zip':
            res.headers.contentType = ContentType.binary;
            res.add(zip);
          default:
            res.statusCode = 404;
        }
        await res.close();
      });
      api = ThemePlazaApi(base: 'http://127.0.0.1:${server.port}');
    });
    tearDown(() => server.close(force: true));

    test('lists, pages, categories and detail follow the documented reply shape', () async {
      final p1 = await api.themes(page: 1, limit: 1, categoryId: 2);
      expect(seen.last, contains('category_id=2'));
      expect(p1.items.single.name, '主题1');
      expect(p1.items.single.category?.name, '清新');
      expect(p1.hasMore, isTrue);
      final p2 = await api.themes(page: 2, limit: 1);
      expect(p2.items.single.isNight, isTrue);
      expect(p2.hasMore, isFalse);
      expect(seen.last, isNot(contains('category_id')));
      expect((await api.categories()).single.name, '清新');
      final d = await api.theme(10);
      expect(d.version, '1.1');
      await expectLater(api.theme(404), throwsA(predicate((e) => '$e' == 'Failed to get themes: not found')));
      expect(api.fileUrl('/public/files/t.zip'), 'http://127.0.0.1:${server.port}/public/files/t.zip');
    });

    test('a downloaded theme installs as plaza_<id> with the plaza version (so 更新主题 can replace it)', () async {
      final d = await api.theme(10);
      final progress = <double>[];
      final bytes = await api.download(d.zipPath, onProgress: progress.add);
      final t = await ThemePackage.importBytes(bytes, id: ThemeDetailPage.localId(d), version: d.version);
      expect(t.id, 'plaza_10');
      expect(t.version, '1.1');
      expect(t.isLightMode, isFalse);
      expect(ThemeManager.byId('plaza_10'), isNotNull);
      // the same download again replaces in place
      await ThemePackage.importBytes(bytes, id: 'plaza_10', version: '1.2');
      expect(ThemeManager.themes.where((x) => x.id == 'plaza_10').single.version, '1.2');
    });
  });
}
