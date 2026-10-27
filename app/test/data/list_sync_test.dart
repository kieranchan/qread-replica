import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/userapi.dart' show CloudKind;
import 'package:newread/data/bookself.dart';
import 'package:newread/data/note_data_n.dart';
import 'package:newread/data/rss.dart';
import 'package:newread/data/source.dart';
import 'package:newread/data/theme.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/note.dart';
import 'package:newread/models/theme.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';
import '../support/fake_cloud.dart';

Map<String, dynamic> src(String url, String name, {int stamp = 1, String group = ''}) =>
    {'bookSourceUrl': url, 'bookSourceName': name, 'bookSourceGroup': group, 'lastUpdateTime': stamp, 'ruleSearch': {'bookList': '.x'}};

void main() {
  late FakeCloud cloud;
  late TestDevice a;
  late TestDevice b;

  Future<void> use(TestDevice d) async {
    await d.activate();
    Bookdata.autoSync = false;
    UserSession.isLoggedIn = true;
    UserSession.cloudsource = true;
    UserSession.cloudmark = true;
  }

  setUp(() async {
    cloud = FakeCloud();
    a = await newDevice();
    b = await newDevice();
    await use(a);
  });
  tearDown(() {
    a.delete();
    b.delete();
    UserSession.isLoggedIn = false;
    UserSession.cloudsource = false;
    UserSession.cloudmark = false;
    Bookdata.autoSync = true;
  });

  test('switches off: nothing happens', () async {
    UserSession.cloudsource = false;
    UserSession.cloudmark = false;
    expect(await Sources.syncCloud(api: cloud), isNull);
    expect(await RssSources.syncCloud(api: cloud), isNull);
    expect(await NoteDataN.syncCloud(api: cloud), isNull);
    expect(cloud.updateCalls, 0);
  });

  test('book sources: full raw maps travel, newer lastUpdateTime wins, deletions propagate', () async {
    await Sources.addAll([src('https://a', 'A', stamp: 10), src('https://b', 'B', stamp: 10)]);
    final r = await Sources.syncCloud(api: cloud);
    expect(r!.pushed, isTrue);
    expect(Storage.getString(PrefKeys.sourcetag), md5Of(cloud.lists[CloudKind.sources]!));
    expect(((jsonDecode(cloud.lists[CloudKind.sources]!) as List).first as Map)['ruleSearch'], {'bookList': '.x'});
    b.prefs.clear();
    a.capture();

    await use(b);
    final r2 = await Sources.syncCloud(api: cloud);
    expect((r2!.pulled, r2.pushed), (true, false));
    expect(Sourcedata.raw.map((m) => m['bookSourceName']), ['A', 'B']);
    // b edits A (newer stamp) and deletes B, adds C
    await Sources.update('https://a', src('https://a', 'A-edited', stamp: 99));
    await Sources.delete(['https://b']);
    await Sources.add(src('https://c', 'C', stamp: 50));
    await Sources.syncCloud(api: cloud);
    expect((jsonDecode(cloud.lists[CloudKind.sources]!) as List).map((m) => (m as Map)['bookSourceName']), ['A-edited', 'C']);
    b.capture();

    await use(a);
    await Sources.syncCloud(api: cloud);
    expect(Sourcedata.raw.map((m) => m['bookSourceName']), ['A-edited', 'C']);
    expect(Sourcedata.byUrl('https://b'), isNull);
  });

  test('rss sources use the same flow with their own etag key', () async {
    await RssSources.add({'sourceUrl': 'https://r', 'sourceName': 'R', 'ruleArticles': '.a', 'lastUpdateTime': 5});
    expect((await RssSources.syncCloud(api: cloud))!.pushed, isTrue);
    expect(Storage.getString(PrefKeys.rsstag), md5Of(cloud.lists[CloudKind.rss]!));
    a.capture();
    await use(b);
    await RssSources.syncCloud(api: cloud);
    expect(Rssdata.byUrl('https://r')!['ruleArticles'], '.a');
  });

  test('notes: merged by id, later updateTime wins, deletion on the other device is honoured', () async {
    final n1 = await NoteDataN.add(BookNote(bookUrl: 'b', selectedText: '一', chapterIndex: 1));
    final n2 = await NoteDataN.add(BookNote(bookUrl: 'b', selectedText: '二', chapterIndex: 2));
    expect((await NoteDataN.syncCloud(api: cloud))!.pushed, isTrue);
    expect(Storage.getString(PrefKeys.bjetag), md5Of(cloud.lists[CloudKind.notes]!));
    a.capture();

    await use(b);
    await NoteDataN.syncCloud(api: cloud);
    expect(NoteDataN.notes.map((n) => n.selectedText), ['一', '二']);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await NoteDataN.update(BookNote.fromJson({...n1.toJson(), 'noteContent': '改过'}));
    await NoteDataN.delete(n2.id);
    await NoteDataN.syncCloud(api: cloud);
    b.capture();

    await use(a);
    await NoteDataN.syncCloud(api: cloud);
    expect(NoteDataN.notes.map((n) => (n.selectedText, n.noteContent)), [('一', '改过')]);
  });

  test('themes: install replaces by id and persists', () async {
    await ThemeManager.install(ThemeModel(id: 't1', title: '深海', version: '1.0'));
    await ThemeManager.install(ThemeModel(id: 't2', title: '浅滩'));
    await ThemeManager.install(ThemeModel(id: 't1', title: '深海2', version: '1.1'));
    expect(ThemeManager.themes.map((t) => t.title), ['深海2', '浅滩']);
    ThemeManager.store.reset();
    await ThemeManager.load();
    expect(ThemeManager.byId('t1')?.version, '1.1');
    await ThemeManager.remove('t2');
    expect(ThemeManager.themes.length, 1);
    expect(ThemeManager.byId('t2'), isNull);
  });
}
