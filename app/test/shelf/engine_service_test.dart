// EngineBookSearchService against the engine's fake book site (127.0.0.1, test/util/fake_site.dart): search → info → toc →
// content and explore, all through the shelf-area interface.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/source.dart';
import 'package:newread/pages/search/engine_book_search_service.dart';

import '../support/env.dart';
import '../util/fake_site.dart';

void main() {
  late FakeSite site;
  late TestDevice device;
  late EngineBookSearchService engine;
  late Source source;

  setUp(() async {
    site = await FakeSite.start();
    device = await newDevice();
    await Sources.add(Map<String, dynamic>.from(jsonDecode(site.sourceJson('source_html.json')) as Map));
    source = Sourcedata.sources.single;
    engine = EngineBookSearchService();
  });

  tearDown(() async {
    await site.close();
    device.delete();
  });

  test('search emits one list per source; info, toc and content follow the search result', () async {
    final events = await engine.search('斗破').toList();
    expect(events, hasLength(1));
    final books = events.single;
    expect(books.map((b) => b.name), ['斗破苍穹', '武动乾坤']);
    final first = books.first;
    expect(first.origin, site.base);
    expect(first.bookgroup, '');

    final info = await engine.bookInfo(first..bookgroup = '玄幻组');
    expect(info.wordCount, '123.5万字');
    expect(info.latestChapterTitle, '第三章 归来');
    expect(info.tocUrl, '${site.base}/book/1/toc'); // the @put variable from the search survived the model round trip
    expect(info.bookgroup, '玄幻组'); // shelf fields are kept

    final toc = await engine.chapters(info);
    expect(toc.map((c) => c.name), ['第一卷 起源', '第一章 陨落的天才', '第二章 斗气大陆', '第二卷 成长', '第三章 归来']);
    expect(toc.first.isVolume, isTrue);

    final text = await engine.content(info, toc[1]);
    expect(text, contains('天才一落千丈。'));
  });

  test('explore kinds and pages; change-source candidates exclude the book itself', () async {
    final kinds = await engine.exploreKinds(source);
    expect(kinds.map((k) => k.title), ['热门', '完结']);
    final page1 = await engine.explore(source, kinds.first.url, 1);
    expect(page1, isNotEmpty);
    expect(page1.first.origin, site.base);

    final found = (await engine.search('斗破').toList()).single.first;
    final candidates = await engine.changeSourceCandidates(found).toList();
    expect(candidates.single, isEmpty); // the only source holds the same book
  });
}
