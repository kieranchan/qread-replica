import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/background_music_manager.dart';
import 'package:newread/data/chromemark.dart';
import 'package:newread/data/cloud_api.dart';
import 'package:newread/data/exploration.dart';
import 'package:newread/data/fonts.dart';
import 'package:newread/data/ground.dart';
import 'package:newread/data/note_data_n.dart';
import 'package:newread/data/svg.dart';
import 'package:newread/data/tts.dart';
import 'package:newread/data/webdav.dart';
import 'package:newread/models/back_ground.dart';
import 'package:newread/models/exploration_template.dart';
import 'package:newread/models/font.dart';
import 'package:newread/models/httptts.dart';
import 'package:newread/models/note.dart';
import 'package:newread/models/svgimage.dart';
import 'package:newread/models/webdavserver.dart';
import 'package:newread/storage/storage.dart';
import 'package:path/path.dart' as p;

import '../support/env.dart';
import '../support/fake_cloud.dart';

void main() {
  late TestDevice dev;

  setUp(() async {
    dev = await newDevice();
  });
  tearDown(() => dev.delete());

  group('chrome bookmarks', () {
    test('first load gives the four default bookmarks; changes persist; an empty list falls back to the defaults', () async {
      final list = await Chromemarks.load();
      expect(list.map((c) => c.title), ['源仓库', '源论坛', '百度', 'bing']);
      expect(list.map((c) => c.id), ['0', '11', '2', '3']);
      expect(list.map((c) => c.url), ['https://yckceo.vip/', 'https://ycoo.net', 'https://m.baidu.com', 'https://www.bing.com/']);
      expect(list.every((c) => c.createdAt > 0), isTrue);
      expect(await Storage.exists('chromemark'), isFalse);

      final added = await Chromemarks.add('必应词典', 'https://cn.bing.com/dict');
      expect(Chromemarks.contains('https://cn.bing.com/dict'), isTrue);
      final again = await Chromemarks.add('改名', 'https://cn.bing.com/dict'); // same url: renamed, not duplicated
      expect(again.id, added.id);
      expect(Chromemarks.bookmarks.length, 5);
      await Chromemarks.move(4, 0);
      await Chromemarks.delete('11');
      Chromemarks.store.reset();
      final back = await Chromemarks.load();
      expect(back.map((c) => c.title), ['改名', '源仓库', '百度', 'bing']);

      await Chromemarks.delete(back.first.id);
      for (final c in List.of(Chromemarks.bookmarks)) {
        await Chromemarks.delete(c.id);
      }
      Chromemarks.store.reset();
      expect((await Chromemarks.load()).length, 4); // nothing stored -> defaults again
    });
  });

  group('exploration templates', () {
    test('create / update / active template / delete, persisted in two keys', () async {
      await ExplorationData.load();
      expect(ExplorationData.active, isNull);
      final t1 = await Exploration.create('默认发现', components: [
        {'id': 'c1', 'config': {'title': '热门'}, 'order': 0},
      ]);
      final t2 = await Exploration.create('第二个');
      expect(t1.createdAt, isNotEmpty);
      expect(DateTime.tryParse(t1.createdAt), isNotNull);
      await Exploration.setActive(t2.id);
      expect(ExplorationData.active?.id, t2.id);
      expect(ExplorationData.templates.map((t) => t.isActive), [false, true]);
      expect((await Storage.read('active_exploration_template_id')).trim(), t2.id);

      await Exploration.update(ExplorationTemplate.fromJson({...t1.toJson(), 'name': '改名'}));
      expect(ExplorationData.templates.first.name, '改名');
      expect(ExplorationData.templates.first.updatedAt, isNotEmpty);

      ExplorationData.store.reset();
      await ExplorationData.load();
      expect(ExplorationData.templates.length, 2);
      expect(ExplorationData.active?.id, t2.id);
      expect(ExplorationData.templates.first.components.length, 1);

      await Exploration.delete(t2.id);
      expect(ExplorationData.active, isNull);
      expect(ExplorationData.activeId, '');
      await Exploration.setActive('unknown-id');
      expect(ExplorationData.active, isNull);

      final json = Exploration.exportJson();
      final other = await newDevice();
      addTearDown(other.delete);
      expect(await Exploration.importJson(json), 1);
      expect(ExplorationData.templates.single.name, '改名');
    });
  });

  group('WebDAV servers', () {
    test('CRUD with ids, the cloud-books selection follows deletion, persistence', () async {
      final s1 = await WebDav.add(WebDavServer(name: '坚果云', url: 'https://dav.jianguoyun.com/dav/', username: 'me', password: 'pw'));
      final s2 = await WebDav.add(WebDavServer(name: 'NAS', url: 'http://nas.local:5005/', username: 'u'));
      expect(s1.id, isNotEmpty);
      expect(s1.id, isNot(s2.id));
      await WebDav.select(s2.id);
      expect(WebDav.selected?.name, 'NAS');
      await WebDav.update(WebDavServer.fromJson({...s1.toJson(), 'name': '坚果云2'}));
      expect(WebDav.byId(s1.id)?.name, '坚果云2');

      WebDav.store.reset();
      await WebDav.load();
      expect(WebDav.servers.length, 2);
      expect(WebDav.byId(s1.id)?.password, 'pw');
      expect(WebDav.selectedId, s2.id);
      await WebDav.delete(s2.id);
      expect(WebDav.selectedId, '');
      expect(WebDav.selected, isNull);
      expect(WebDav.servers.length, 1);
      expect(WebDav.byId('nope'), isNull);
    });
  });

  group('TTS engines', () {
    test('global engines and per-book setups live in one list; protected entries stay; Legado import / export', () async {
      final e = await Tts.add(HttpTts(name: '自建TTS', html: {'url': 'https://tts.example/?t={{speakText}}'}));
      expect(e.candel, isTrue);
      expect(TTSData.byId(e.id)?.name, '自建TTS');
      expect(TTSData.byId('system')?.name, '系统默认');
      expect(await Tts.delete('system'), isFalse);

      await Tts.saveForBook('https://book/1', HttpTts(narrationEngineId: e.id, narrationVoiceId: 'v1', roles: [TtsRole(name: '张三', engineId: e.id, voiceId: 'v2', gender: 1).toJson()]));
      expect(TTSData.forBook('https://book/1')?.narrationVoiceId, 'v1');
      expect(TTSData.engines.length, 1); // the per-book setup is not an engine
      await Tts.saveForBook('https://book/1', HttpTts(narrationEngineId: e.id, narrationVoiceId: 'v9'));
      expect(TTSData.all.length, 2);
      expect(TTSData.forBook('https://book/1')?.narrationVoiceId, 'v9');
      expect(TTSData.forBook(''), isNull);

      final imported = await Tts.importJson(jsonEncode([
        {'name': 'Legado引擎', 'url': 'https://x/tts?text={{speakText}}', 'contentType': 'audio/mpeg', 'concurrentRate': '1000'},
        {'name': 'no url'},
      ]));
      expect(imported, 1);
      expect(TTSData.engines.map((t) => t.name), ['自建TTS', 'Legado引擎']);
      expect(TTSData.engines.last.html['contentType'], 'audio/mpeg');
      expect(await Tts.importJson(jsonEncode({'name': 'Legado引擎', 'url': 'https://y', 'contentType': 'audio/wav'})), 1); // replaced by name
      expect(TTSData.engines.length, 2);
      expect(TTSData.engines.last.html['url'], 'https://y');

      TTSData.store.reset();
      await TTSData.load();
      expect(TTSData.all.length, 3);
      expect(await Tts.delete(e.id), isTrue);
      expect(Tts.exportJson(), isNot(contains('自建TTS')));
      await Tts.deleteForBook('https://book/1');
      expect(TTSData.forBook('https://book/1'), isNull);
    });

    test('cloud item tts_engines: push, pull (merge by id, per-book setups stay local) and the md5 shortcut', () async {
      final cloud = FakeCloud();
      final e = await Tts.add(HttpTts(name: 'A', html: {'url': 'u'}));
      await Tts.saveForBook('book', HttpTts(narrationEngineId: e.id));
      await CloudTts.push(api: cloud);
      final uploaded = jsonDecode(cloud.items['tts_engines']!) as List;
      expect(uploaded.length, 1); // only the global engine
      expect(Storage.getString('ttsmd5'), md5Of(cloud.items['tts_engines']!));
      expect(await CloudTts.pull(api: cloud), isFalse); // 一样不必同步

      final other = await newDevice();
      addTearDown(other.delete);
      expect(await CloudTts.pull(api: cloud), isTrue);
      expect(TTSData.engines.single.name, 'A');
      expect(TTSData.forBook('book'), isNull);
      // the cloud engine changes: pull replaces by id
      final changed = (jsonDecode(cloud.items['tts_engines']!) as List).cast<Map>().single..['name'] = 'A2';
      cloud.items['tts_engines'] = jsonEncode([changed]);
      expect(await CloudTts.pull(api: cloud), isTrue);
      expect(TTSData.engines.single.name, 'A2');
      // nothing in the cloud
      cloud.items.clear();
      await expectLater(CloudTts.pull(api: cloud), throwsA(isA<StateError>().having((e) => e.message, 'm', '云端数据读取失败')));
      expect(defaultCloudApi, isA<UserApiCloud>());
    });
  });

  group('notes and bookmarks', () {
    BookNote note(String book, int chapter, int start, String text) =>
        BookNote(bookUrl: book, bookName: '书', chapterIndex: chapter, chapterName: '第$chapter章', startStableId: start, endStableId: start + 5, selectedText: text, noteContent: '', color: '#FFFF00');

    test('notes get ids and timestamps, bookmarks use the bm_ prefix, queries are per book / chapter and sorted', () async {
      final n1 = await NoteDataN.add(note('b1', 3, 40, '后面的句子'));
      final n2 = await NoteDataN.add(note('b1', 1, 10, '前面的句子'));
      final bm = await NoteDataN.add(note('b1', 2, 0, ''), bookmark: true);
      await NoteDataN.add(note('b2', 1, 1, '别的书'));
      expect(n1.id, isNotEmpty);
      expect(bm.id, startsWith('bm_'));
      expect(NoteDataN.isBookmark(bm), isTrue);
      expect(NoteDataN.isBookmark(n1), isFalse);
      expect(n1.createTime, greaterThan(0));
      expect(n1.updateTime, n1.createTime);

      expect((await NoteDataN.notesOfBook('b1')).map((n) => n.selectedText), ['前面的句子', '后面的句子']);
      expect((await NoteDataN.bookmarksOfBook('b1')).single.id, bm.id);
      expect((await NoteDataN.notesOfChapter('b1', 3)).single.id, n1.id);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await NoteDataN.update(BookNote.fromJson({...n2.toJson(), 'noteContent': '我的想法'}));
      final upd = NoteDataN.notes.firstWhere((n) => n.id == n2.id);
      expect(upd.noteContent, '我的想法');
      expect(upd.updateTime, greaterThan(n2.createTime - 1));

      NoteDataN.store.reset();
      await NoteDataN.load();
      expect(NoteDataN.notes.length, 4);
      await NoteDataN.delete(n1.id);
      await NoteDataN.deleteOfBook('b2');
      expect(NoteDataN.notes.length, 2);
      expect(jsonDecode(NoteDataN.exportJson()), hasLength(2));
    });

    test('mergeRemote: same id -> later updateTime wins, unknown ids are added', () async {
      final a = await NoteDataN.add(note('b1', 1, 1, 'x'));
      final newer = BookNote.fromJson({...a.toJson(), 'noteContent': '云端更新', 'updateTime': a.updateTime + 1000});
      final older = BookNote.fromJson({...a.toJson(), 'noteContent': '旧', 'updateTime': a.updateTime - 1000});
      final fresh = BookNote(id: 'remote-1', bookUrl: 'b1', selectedText: '新的');
      expect(await NoteDataN.mergeRemote([older]), isFalse);
      expect(await NoteDataN.mergeRemote([newer, fresh]), isTrue);
      expect(NoteDataN.notes.firstWhere((n) => n.id == a.id).noteContent, '云端更新');
      expect(NoteDataN.notes.any((n) => n.id == 'remote-1'), isTrue);
    });
  });

  group('fonts', () {
    test('importing copies the file into <root>/fonts; a duplicate family is refused with the original text', () async {
      final src = File(p.join(dev.dir.path, 'src.ttf'))..writeAsBytesSync([1, 2, 3, 4]);
      final f = await Fonts.importFile('我的字体', src);
      expect(File(FontsData.filePath(f)).readAsBytesSync(), [1, 2, 3, 4]);
      expect(p.dirname(FontsData.filePath(f)), p.join(dev.dir.path, 'fonts'));
      await expectLater(Fonts.add(Font(family: '我的字体', path: 'x')), throwsA(isA<StateError>().having((e) => e.message, 'm', '名称重复：我的字体')));
      await expectLater(Fonts.importFile('我的字体', src), throwsStateError);
      expect(Fonts.byFamily('我的字体')?.path, f.path);

      FontsData.store.reset();
      await FontsData.load();
      expect(FontsData.fonts.single.family, '我的字体');
      await Fonts.remove('我的字体');
      expect(FontsData.fonts, isEmpty);
      expect(File(FontsData.filePath(f)).existsSync(), isFalse);
    });
  });

  group('grounds (reader styles) and svg icons', () {
    test('Ground: next free integer name, update, delete, persistence', () async {
      final a = await Ground.add(BackGround(themeName: '护眼', backgroundColor: '#C7EDCC'));
      final b = await Ground.add(BackGround(themeName: '夜间', backgroundColor: '#000000'));
      expect([a.name, b.name], [1, 2]);
      await Ground.update(BackGround.fromJson({...a.toJson(), 'fontSize': 22.0}));
      expect(Ground.byName(1)?.fontSize, 22.0);
      Ground.store.reset();
      await Ground.load();
      expect(Ground.grounds.map((g) => g.themeName), ['护眼', '夜间']);
      await Ground.delete(1);
      expect(Ground.grounds.single.name, 2);
      final c = await Ground.add(BackGround(name: 2, themeName: '重名')); // taken: next free number
      expect(c.name, 3);
    });

    test('Svg: put / replace / delete by id, persistence', () async {
      await Svg.put('menu', '<svg id="1"/>');
      await Svg.put('menu', '<svg id="2"/>');
      await Svg.put('back', '<svg id="3"/>');
      expect(Svg.svgs.length, 2);
      expect(Svg.byId('menu')?.svg, '<svg id="2"/>');
      Svg.store.reset();
      await Svg.load();
      expect(Svg.svgs.map((s) => s.id), ['menu', 'back']);
      await Svg.delete('menu');
      expect(Svg.byId('menu'), isNull);
      await Svg.clear();
      expect(Svg.svgs, isEmpty);
      // defaults are used when nothing is stored
      final saved = Svg.desvgs;
      addTearDown(() => Svg.desvgs = saved);
      Svg.desvgs = [Svgimage(id: 'd', svg: '<svg/>')];
      Svg.store.reset();
      await Storage.write('svg', '');
      expect((await Svg.load()).single.id, 'd');
    });
  });

  group('background music', () {
    test('add copies the file into <root>/background_music, remove deletes it, volume is clamped to 0.1..0.8', () async {
      final src = File(p.join(dev.dir.path, 'rain.mp3'))..writeAsBytesSync([9, 9, 9]);
      final m = await BackgroundMusicManager.add(src);
      expect(m.name, 'rain');
      expect(File(BackgroundMusicManager.filePath(m)).readAsBytesSync(), [9, 9, 9]);
      expect(p.dirname(BackgroundMusicManager.filePath(m)), p.join(dev.dir.path, 'background_music'));
      await BackgroundMusicManager.select(m.id);
      expect(BackgroundMusicManager.selected?.id, m.id);
      await BackgroundMusicManager.rename(m.id, '雨声');

      BackgroundMusicManager.store.reset();
      await BackgroundMusicManager.load();
      expect(BackgroundMusicManager.musics.single.name, '雨声');

      expect(BackgroundMusicManager.volume, 0.1);
      await BackgroundMusicManager.setVolume(0.5);
      expect(BackgroundMusicManager.volume, 0.5);
      await BackgroundMusicManager.setVolume(2);
      expect(BackgroundMusicManager.volume, 0.8);
      await BackgroundMusicManager.setVolume(0);
      expect(BackgroundMusicManager.volume, 0.1);

      await BackgroundMusicManager.remove(m.id);
      expect(BackgroundMusicManager.musics, isEmpty);
      expect(File(BackgroundMusicManager.filePath(m)).existsSync(), isFalse);
      expect(BackgroundMusicManager.selectedId, '');
    });
  });
}
