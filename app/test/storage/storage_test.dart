import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/app_dirs.dart';
import 'package:newread/common/common.dart';
import 'package:newread/common/lock.dart';
import 'package:newread/init/appinit.dart';
import 'package:newread/storage/storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/env.dart';

void main() {
  late TestDevice dev;

  setUp(() async {
    dev = await newDevice();
  });
  tearDown(() => dev.delete());

  group('prefs layer keeps every value as text, like the original', () {
    test('setters write text; getters convert and fall back to defaults', () async {
      await Storage.setBool('flag', true);
      await Storage.setInt('count', 42);
      await Storage.setDouble('rate', 0.5);
      await Storage.setString('name', '轻悦');
      final raw = await SharedPreferences.getInstance();
      expect(raw.get('flag'), 'true');
      expect(raw.get('count'), '42');
      expect(raw.get('rate'), '0.5');
      expect(Storage.getBool('flag'), isTrue);
      expect(Storage.getInt('count'), 42);
      expect(Storage.getDouble('rate'), 0.5);
      expect(Storage.getString('name'), '轻悦');
      expect(Storage.getString('missing'), '');
      expect(Storage.getString('missing', 'x'), 'x');
      expect(Storage.getBool('missing'), isFalse);
      expect(Storage.getBool('missing', true), isTrue);
      expect(Storage.getInt('missing', 7), 7);
      await Storage.remove('flag');
      expect(Storage.getBool('flag'), isFalse);
    });

    test('natively typed values written by other code still read back (toBool "1", toInt "3.0")', () async {
      SharedPreferences.setMockInitialValues({'a': true, 'b': 5, 'c': '1', 'd': '3.0', 'e': 'abc', 'f': 'TRUE'});
      await Storage.init();
      expect(Storage.getBool('a'), isTrue);
      expect(Storage.getInt('b'), 5);
      expect(Storage.getBool('c'), isTrue);
      expect(Storage.getInt('d'), 3);
      expect(Storage.getInt('e', 9), 9);
      expect(Storage.getBool('f'), isTrue);
      expect(Storage.getString('a'), 'true');
    });

    test('dump / restore of the settings map (backup settings.json)', () async {
      await Storage.setBool('x', true);
      await Storage.setString('y', 'v');
      final dump = Storage.dumpPrefs();
      expect(dump, {'x': 'true', 'y': 'v'});
      SharedPreferences.setMockInitialValues({});
      await Storage.init();
      await Storage.restorePrefs({'x': 'true', 'y': 'v', 'z': 3, 'n': null});
      expect(Storage.getBool('x'), isTrue);
      expect(Storage.getString('z'), '3');
      expect(Storage.containsKey('n'), isFalse);
    });
  });

  group('file store', () {
    test('one file per key named md5(utf8(key)).txt inside <root>/item', () async {
      await Storage.write('a', 'hello');
      expect(Storage.md5Of('a'), '0cc175b9c0f1b6a831c399e269772661');
      final f = File(p.join(dev.dir.path, 'item', '0cc175b9c0f1b6a831c399e269772661.txt'));
      expect(f.existsSync(), isTrue);
      expect(f.readAsStringSync(), 'hello');
      expect(Storage.itemPath('a'), f.path);
      // CJK keys hash their UTF-8 bytes
      expect(Storage.md5Of('书架'), crypto.md5.convert(utf8.encode('书架')).toString());
    });

    test('read returns "" for unknown keys, round-trips unicode and big JSON', () async {
      expect(await Storage.read('nothing'), '');
      expect(await Storage.exists('nothing'), isFalse);
      final big = jsonEncode([for (var i = 0; i < 5000; i++) {'id': i, 'name': '书名$i', 'text': '你好 🌏'}]);
      await Storage.write('big', big);
      expect(await Storage.read('big'), big);
      expect(await Storage.exists('big'), isTrue);
      expect(Storage.jsondecode(await Storage.read('big')).length, 5000);
    });

    test('an empty value deletes the file; overwrite replaces the content', () async {
      await Storage.write('k', 'one');
      await Storage.write('k', 'two');
      expect(await Storage.read('k'), 'two');
      await Storage.write('k', '');
      expect(File(Storage.itemPath('k')).existsSync(), isFalse);
      expect(await Storage.read('k'), '');
      await Storage.write('k', 'three');
      await Storage.delete('k');
      expect(await Storage.exists('k'), isFalse);
    });

    test('atomic write leaves no .tmp / .tmp2 files behind', () async {
      await Storage.write('k', 'data');
      await Storage.write('k', 'data2');
      final names = Directory(p.join(dev.dir.path, 'item')).listSync().map((e) => p.basename(e.path)).toList();
      expect(names, ['${Storage.md5Of('k')}.txt']);
    });

    test('crash recovery: marker + tmp means tmp is complete and wins; a partial tmp without marker is ignored', () async {
      await Storage.write('k', 'old');
      final path = Storage.itemPath('k');
      // crash after the commit marker was created but before the move
      File('$path.tmp').writeAsStringSync('new complete');
      File('$path.tmp2').createSync();
      expect(await Storage.read('k'), 'new complete');
      File('$path.tmp').deleteSync();
      File('$path.tmp2').deleteSync();
      // crash in the middle of writing tmp: no marker yet
      File('$path.tmp').writeAsStringSync('half writ');
      expect(await Storage.read('k'), 'old');
      File('$path.tmp').deleteSync();
      // crash after the move but before the marker was deleted: the data is in the file itself
      File('$path.tmp2').createSync();
      expect(await Storage.read('k'), 'old');
    });

    test('writes to one key are serialised: the last started write wins', () async {
      await Future.wait([for (var i = 0; i < 20; i++) Storage.write('k', 'v$i')]);
      expect(await Storage.read('k'), 'v19');
    });

    test('write failures surface as StorageException with the original text', () async {
      // a directory where the file should be makes the move fail
      Directory(Storage.itemPath('boom')).createSync(recursive: true);
      await expectLater(Storage.write('boom', 'x'), throwsA(isA<StorageException>().having((e) => e.message, 'message', startsWith('保存失败: boom'))));
    });

    test('readJson / writeJson', () async {
      expect(await Storage.readJson('j'), isNull);
      await Storage.writeJson('j', {'a': [1, 2]});
      expect(await Storage.readJson('j'), {'a': [1, 2]});
      await Storage.write('bad', '{oops');
      expect(await Storage.readJson('bad'), isNull);
      expect(Storage.jsondecode('{"a":1}'), isEmpty);
      expect(Storage.jsondecode(''), isEmpty);
    });

    test('cleanItems keeps the cleanwhite keys and removes the rest', () async {
      await Storage.write('bookself', '[]x');
      await Storage.write('book_chapter:1,2', 'cache');
      await Storage.write('http://a/b,page', 'cache');
      Storage.keepOnClean('bookself');
      expect(Common.cleanwhite, contains(Storage.md5Of('bookself')));
      expect(await Storage.cleanItems(), 2);
      expect(await Storage.exists('bookself'), isTrue);
      expect(await Storage.exists('book_chapter:1,2'), isFalse);
    });
  });

  group('AppDirs / AppInit', () {
    test('init creates the 19 start-up directories and the extra feature folders under the injected root', () async {
      for (final d in [...AppDirs.startup, ...AppDirs.extra]) {
        expect(Directory(p.join(dev.dir.path, d)).existsSync(), isTrue, reason: d);
      }
      expect(AppDirs.startup.length, 19);
      expect(AppDirs.item.path, p.join(dev.dir.path, 'item'));
      expect(AppDirs.path('covers', 'a.png'), p.join(dev.dir.path, 'covers', 'a.png'));
      final staging = await AppDirs.ensure(AppDirs.backupTemp);
      expect(staging.existsSync(), isTrue);
    });

    test('AppInit.init with an injected root loads every manager and registers the keep-list', () async {
      final other = Directory.systemTemp.createTempSync('qread_init_');
      addTearDown(() => other.deleteSync(recursive: true));
      resetManagers();
      Common.cleanwhite.clear();
      await AppInit.init(prefs: await _freshPrefs(), root: other);
      expect(Common.appid, isNotEmpty);
      expect(Storage.getString('appid'), Common.appid);
      for (final k in ['isLoggedIn', 'tockenid', 'etag', 'avatar_url', 'encrypt_key', 'bookself', 'bookgroup', 'source', 'rss2', 'replaces', 'txt_toc_rule', 'notes', 'tts', 'webdav', 'chromemark']) {
        expect(Common.cleanwhite, contains(Storage.md5Of(k)), reason: k);
      }
      expect(AppDirs.root.path, other.path);
    });
  });

  test('Lock runs bodies one after another and survives a failing body', () async {
    final lock = Lock();
    final log = <String>[];
    final a = lock.synchronized(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      log.add('a');
    });
    final b = lock.synchronized(() async {
      log.add('b');
      throw StateError('boom');
    });
    final c = lock.synchronized(() => log.add('c'));
    await a;
    await expectLater(b, throwsStateError);
    await c;
    expect(log, ['a', 'b', 'c']);
  });
}

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}
