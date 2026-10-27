import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/qsource.dart';
import 'package:newread/data/rss.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/source.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

/// A Legado-style book source with the rule objects the engine needs.
Map<String, dynamic> legadoSource(String url, String name, {String group = '', bool? enabled}) => {
      'bookSourceUrl': url,
      'bookSourceName': name,
      'bookSourceGroup': group,
      'bookSourceType': 0,
      'enabled': ?enabled,
      'header': '{"User-Agent":"x"}',
      'searchUrl': '/search?q={{key}}&page={{page}}',
      'exploreUrl': '玄幻::/list/1/{{page}}.html\n都市::/list/2/{{page}}.html',
      'ruleSearch': {'bookList': '.list li', 'name': 'a@text', 'bookUrl': 'a@href'},
      'ruleBookInfo': {'intro': '.intro@text', 'tocUrl': '.toc@href'},
      'ruleToc': {'chapterList': '#chapters a', 'chapterName': 'text', 'chapterUrl': 'href'},
      'ruleContent': {'content': '#content@html', 'replaceRegex': '##广告'},
    };

void main() {
  late TestDevice dev;

  setUp(() async {
    dev = await newDevice();
  });
  tearDown(() => dev.delete());

  group('normalizeGroups', () {
    test('trims, drops empties and duplicates, accepts , ， ; separators', () {
      expect(normalizeGroups(' 玄幻 , ,都市,玄幻，女频;完本 '), '玄幻,都市,女频,完本');
      expect(normalizeGroups(''), '');
      expect(normalizeGroups(',,'), '');
    });
  });

  group('book sources', () {
    test('add keeps the full raw map, de-duplicates by bookSourceUrl and keeps the position on replace', () async {
      expect(await Sources.add(legadoSource('https://a.com', 'A', group: '玄幻, ,玄幻')), isTrue);
      expect(await Sources.add(legadoSource('https://b.com', 'B')), isTrue);
      expect(await Sources.add({...legadoSource('https://a.com', 'A2'), 'customOrder': 5}), isFalse);
      expect(Sourcedata.raw.map((m) => m['bookSourceName']), ['A2', 'B']);
      final a = Sourcedata.byUrl('https://a.com')!;
      expect(a['customOrder'], 5);
      expect((a['ruleSearch'] as Map)['bookList'], '.list li'); // the engine sees every rule field
      expect((a['ruleContent'] as Map)['replaceRegex'], '##广告');
      expect(a['enabled'], isTrue); // Legado: missing flag = enabled
      expect(a['lastUpdateTime'], isA<int>());
      // group text was normalised on the first add; the replace used the new (empty) group
      expect(a['bookSourceGroup'], '');
      await Sources.add(legadoSource('https://c.com', 'C', group: '玄幻, ,玄幻'));
      expect(Sourcedata.byUrl('https://c.com')!['bookSourceGroup'], '玄幻');
    });

    test('invalid sources (no url or name) are rejected / skipped', () async {
      await expectLater(Sources.add({'bookSourceUrl': 'https://x', 'bookSourceName': ''}), throwsFormatException);
      final r = await Sources.addAll([
        legadoSource('https://ok.com', 'OK'),
        {'bookSourceName': 'no url'},
        {'bookSourceUrl': 'https://noname.com'},
      ]);
      expect((r.added, r.updated, r.skipped), (1, 0, 2));
    });

    test('persistence: save as JSON list, reload from disk, Source view and lookups', () async {
      await Sources.add(legadoSource('https://a.com', '甲', group: '玄幻'));
      await Sources.add(legadoSource('https://b.com', '乙', enabled: false));
      final stored = jsonDecode(await Storage.read('source')) as List;
      expect(stored.length, 2);
      expect((stored.first as Map)['ruleToc'], isA<Map>());

      Sourcedata.store.reset();
      final back = await Sourcedata.load();
      expect(back.length, 2);
      final views = Sourcedata.sources;
      expect(views.first, isA<Source>());
      expect((views.first.bookSourceName, views.first.bookSourceGroup, views.first.enabled), ('甲', '玄幻', true));
      expect(views.last.enabled, isFalse);
      expect(Sourcedata.sourceByUrl('https://b.com')?.bookSourceName, '乙');
      expect(Sourcedata.sourceByUrl('nope'), isNull);
      expect(Sourcedata.enabledRaw.map((m) => m['bookSourceName']), ['甲']);
    });

    test('enable flags (single, selection, all), explore flag and the explore list', () async {
      await Sources.addAll([legadoSource('https://a.com', 'A'), legadoSource('https://b.com', 'B'), {...legadoSource('https://c.com', 'C'), 'exploreUrl': ''}]);
      expect(Sourcedata.exploreRaw.map((m) => m['bookSourceName']), ['A', 'B']); // C has no exploreUrl
      await Sources.setEnabled(['https://a.com'], false);
      expect(Sourcedata.enabledRaw.map((m) => m['bookSourceName']), ['B', 'C']);
      await Sources.setEnabledExplore(['https://b.com'], false);
      expect(Sourcedata.exploreRaw, isEmpty);
      await Sources.setEnabled(null, true);
      expect(Sourcedata.raw.every((m) => m['enabled'] == true), isTrue);
      await Sources.setField('https://a.com', 'respondTime', 123);
      expect(Sourcedata.byUrl('https://a.com')!['respondTime'], 123);
    });

    test('group operations: add / remove / rename, list of groups, sources of a group', () async {
      await Sources.addAll([legadoSource('https://a.com', 'A', group: '玄幻'), legadoSource('https://b.com', 'B'), legadoSource('https://c.com', 'C', group: '都市,玄幻')]);
      expect(Sourcedata.groups, ['玄幻', '都市']);
      await Sources.addGroup(['https://a.com', 'https://b.com'], ' 精品 ');
      expect(Sourcedata.byUrl('https://a.com')!['bookSourceGroup'], '玄幻,精品');
      expect(Sourcedata.byUrl('https://b.com')!['bookSourceGroup'], '精品');
      await Sources.addGroup(['https://b.com'], '精品'); // no duplicate
      expect(Sourcedata.byUrl('https://b.com')!['bookSourceGroup'], '精品');
      await Sources.removeGroup(['https://a.com', 'https://c.com'], '玄幻');
      expect(Sourcedata.byUrl('https://a.com')!['bookSourceGroup'], '精品');
      expect(Sourcedata.byUrl('https://c.com')!['bookSourceGroup'], '都市');
      await Sources.renameGroup('精品', '推荐');
      expect(Sourcedata.ofGroup('推荐').map((m) => m['bookSourceName']), ['A', 'B']);
      await Sources.removeGroup(['https://b.com'], '推荐');
      expect(Sourcedata.ofGroup('').map((m) => m['bookSourceName']), ['B']); // '' = no group
    });

    test('delete by urls, clear', () async {
      await Sources.addAll([legadoSource('https://a.com', 'A'), legadoSource('https://b.com', 'B'), legadoSource('https://c.com', 'C')]);
      expect(await Sources.delete(['https://a.com', 'https://zzz']), 1);
      expect(Sourcedata.raw.length, 2);
      await Sources.clear();
      expect(Sourcedata.raw, isEmpty);
      expect(await Storage.read('source'), '[]');
    });

    test('Legado import (array and single object) and export round trip keep every rule field', () async {
      final text = jsonEncode([legadoSource('https://a.com', 'A', group: '玄幻'), legadoSource('https://b.com', 'B')]);
      var r = await Sources.importJson(text);
      expect((r.added, r.updated), (2, 0));
      r = await Sources.importJson(jsonEncode(legadoSource('https://a.com', 'A改')));
      expect((r.added, r.updated), (0, 1));
      r = await Sources.importJson(jsonEncode(legadoSource('https://d.com', 'D')));
      expect((r.added, r.updated), (1, 0));
      await expectLater(Sources.importJson('not json'), throwsFormatException);

      final exported = await Sources.exportJson();
      final list = jsonDecode(exported) as List;
      expect(list.length, 3);
      expect((list.first as Map)['bookSourceName'], 'A改');
      expect(((list.first as Map)['ruleBookInfo'] as Map)['tocUrl'], '.toc@href');
      expect(((jsonDecode(await Sources.exportJson(urls: ['https://b.com'])) as List).single as Map)['bookSourceUrl'], 'https://b.com');

      // another device imports the export and ends up with identical rule data
      final other = await newDevice();
      addTearDown(other.delete);
      r = await Sources.importJson(exported);
      expect(r.added, 3);
      expect(Sourcedata.byUrl('https://a.com')!['ruleSearch'], {'bookList': '.list li', 'name': 'a@text', 'bookUrl': 'a@href'});
      expect(Sourcedata.byUrl('https://a.com')!['exploreUrl'], contains('玄幻::'));
    });
  });

  group('rss sources', () {
    Map<String, dynamic> rss(String url, String name, {String group = ''}) =>
        {'sourceUrl': url, 'sourceName': name, 'sourceGroup': group, 'sourceIcon': 'i.png', 'sortUrl': '最新::/new', 'ruleArticles': '.item', 'ruleTitle': 'a@text'};

    test('upsert by sourceUrl, raw map kept, persistence under rss2, RssSource view', () async {
      expect(await RssSources.add(rss('https://r1', '站点一', group: '新闻,新闻, 科技')), isTrue);
      expect(await RssSources.add(rss('https://r2', '站点二')), isTrue);
      expect(await RssSources.add({...rss('https://r1', '站点一改'), 'ruleLink': 'a@href'}), isFalse);
      expect(Rssdata.raw.map((m) => m['sourceName']), ['站点一改', '站点二']);
      expect(Rssdata.byUrl('https://r1')!['ruleLink'], 'a@href');
      expect(Rssdata.byUrl('https://r1')!['enabled'], isTrue);
      await expectLater(RssSources.add({'sourceUrl': 'u'}), throwsFormatException);

      Rssdata.store.reset();
      await Rssdata.load();
      final view = Rssdata.sources.first;
      expect((view.sourceUrl, view.sourceName, view.sourceIcon, view.enabled), ('https://r1', '站点一改', 'i.png', true));
      expect((jsonDecode(await Storage.read('rss2')) as List).length, 2);
    });

    test('enable, groups, delete, import / export', () async {
      await RssSources.addAll([rss('https://r1', 'A', group: '新闻'), rss('https://r2', 'B')]);
      await RssSources.setEnabled(['https://r2'], false);
      expect(Rssdata.enabledRaw.map((m) => m['sourceName']), ['A']);
      await RssSources.setEnabled(null, true);
      await RssSources.addGroup(['https://r2'], '科技');
      expect(Rssdata.groups, ['新闻', '科技']);
      expect(Rssdata.ofGroup('科技').single['sourceName'], 'B');
      await RssSources.removeGroup(['https://r2'], '科技');
      expect(Rssdata.ofGroup('').single['sourceName'], 'B');
      expect(await RssSources.delete(['https://r1']), 1);

      final r = await RssSources.importJson(jsonEncode([rss('https://x', 'X'), {'sourceName': 'no url'}]));
      expect((r.added, r.skipped), (1, 1));
      final exported = await RssSources.exportJson();
      final other = await newDevice();
      addTearDown(other.delete);
      expect((await RssSources.importJson(exported)).added, 2);
      expect(Rssdata.byUrl('https://x')!['ruleArticles'], '.item');
    });
  });

  group('qread source cache (sourcedata)', () {
    test('replace stores the backend list and its md5 and survives a reload', () async {
      expect(await QSources.load(), isEmpty);
      expect(QSources.md5, '');
      await QSources.replace(SourceMsg([Source(bookSourceUrl: 'https://q1', bookSourceName: 'Q1', enabled: true)], 'abc123'));
      expect(QSources.md5, 'abc123');
      QSources.reset();
      final back = await QSources.load();
      expect(back.single.bookSourceName, 'Q1');
      expect(QSources.byUrl('https://q1')?.enabled, isTrue);
      await QSources.clear();
      expect(QSources.md5, '');
      QSources.reset();
      expect(await QSources.load(), isEmpty);
    });
  });
}
