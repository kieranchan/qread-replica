import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/rssapi.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_rule.dart';
import 'package:newread/util/webbook/debug.dart';
import 'package:newread/util/webbook/model/book.dart';
import 'package:newread/util/webbook/model/book_source.dart';
import 'package:newread/util/webbook/model/rss_source.dart';
import 'package:newread/util/webbook/util/cache_manager.dart';

import 'fake_site.dart';

void main() {
  late FakeSite site;

  setUpAll(() async {
    JsEngines.useDart();
    site = await FakeSite.start();
  });
  tearDownAll(() => site.close());
  setUp(() {
    CookieStore.resetForTests();
    CacheManager.resetForTests();
    SourceApi.cache.clear();
    site.requests.clear();
    site.hits.clear();
  });

  BookSource load(String name) => BookSource.fromJsonString(site.sourceJson(name));

  test('HTML source: search -> info -> toc (paged, volumes) -> content (paged, replaceRegex)', () async {
    final source = load('source_html.json');
    final debug = DebugLog();
    final results = await SourceApi.search(source, '斗破', debug: debug);
    expect(results.map((b) => b.name), ['斗破苍穹', '武动乾坤']); // the duplicate /book/1 entry is removed
    final first = results.first;
    expect(first.author, '天蚕土豆');
    expect(first.bookUrl, '${site.base}/book/1');
    expect(first.coverUrl, '${site.base}/img/1.jpg');
    expect(first.kind, '玄幻,热血');
    expect(first.intro, '少年萧炎的故事');
    expect(first.origin, site.base);
    expect(first.originName, 'HTML站');
    expect(first.getVariable('bid'), '1'); // @put in the bookUrl rule
    expect(site.requests.first, contains('q=%E6%96%97%E7%A0%B4&page=1'));
    expect(debug.lines.any((l) => l.contains('获取书名')), isTrue);

    final book = first.toBook();
    await SourceApi.bookInfo(source, book);
    expect(book.name, '斗破苍穹');
    expect(book.author, '天蚕土豆');
    expect(book.kind, '玄幻');
    expect(book.wordCount, '123.5万字');
    expect(book.latestChapterTitle, '第三章 归来');
    expect(book.coverUrl, '${site.base}/img/1.jpg');
    expect(book.intro, startsWith('　　这里是斗气大陆\n　　没有魔法\n　　只有斗气'));
    expect(book.tocUrl, '${site.base}/book/1/toc'); // built from @get:{bid}

    final chapters = await SourceApi.chapters(source, book);
    expect(chapters.map((c) => c.title), ['第一卷 起源', '第一章 陨落的天才', '第二章 斗气大陆', '第二卷 成长', '第三章 归来']);
    expect(chapters.map((c) => c.isVolume), [true, false, false, true, false]);
    expect(chapters.map((c) => c.index), [0, 1, 2, 3, 4]);
    expect(chapters[1].getAbsoluteURL(), '${site.base}/chapter/1');
    expect(chapters[1].tag, '2020-01-01');
    expect(book.totalChapterNum, 5);
    expect(book.latestChapterTitle, '第三章 归来');
    expect(site.hits['/book/1/toc2'], 1);

    final text = await SourceApi.content(source, book, chapters[1], nextChapterUrl: chapters[2].getAbsoluteURL());
    expect(text.split('\n'), ['　　天才一落千丈。', '　　斗之气，三段！', '　　第二页内容。', '　　<img src="${site.base}/img/inline.png">']);
    expect(site.hits['/chapter/2'], isNull); // paging stops at the next chapter
    expect(chapters[1].title, '第一章 陨落的天才');
    expect(await SourceApi.content(source, book, chapters[0]), ''); // volume entries have no text
    final model = book.toModel();
    expect(model.name, '斗破苍穹');
    expect(chapters[2].toModel().name, '第二章 斗气大陆');
  });

  test('JSON source: JSONPath rules, {{(page-1)*20}}, {{\$.id}} urls, JS with java.getString replay', () async {
    final source = load('source_json.json');
    final results = await SourceApi.search(source, '斗破');
    expect(site.requests.first, contains('page=0'));
    expect(results.length, 2);
    final b = results.first;
    expect(b.bookUrl, '${site.base}/json/book/1');
    expect(b.kind, '玄幻,热血');
    expect(b.wordCount, '123.5万字');
    expect(b.coverUrl, '${site.base}/img/1.jpg');
    final book = b.toBook();
    await SourceApi.bookInfo(source, book);
    expect(book.tocUrl, '${site.base}/json/toc/1');
    expect(book.intro, '少年萧炎的故事'); // a single line gets no indent (HtmlFormatter.format)
    final chapters = await SourceApi.chapters(source, book);
    expect(chapters.map((c) => c.title), ['第一章 陨落的天才', '第二章 斗气大陆', '第三章 归来']);
    expect(chapters.first.getAbsoluteURL(), '${site.base}/json/chapter/11');
    expect(chapters.first.tag, matches(RegExp(r'^\d{4}/\d{2}/\d{2} \d{2}:\d{2}$')));
    final text = await SourceApi.content(source, book, chapters.first);
    expect(text, '天才一落千丈。\n　　斗之力，三段！'); // plain text: only lines after a newline get the indent
  });

  test('XPath source with POST search', () async {
    final source = load('source_xpath_post.json');
    final results = await SourceApi.search(source, '斗破');
    expect(site.requests.first, startsWith('POST /html/search_post'));
    expect(results.map((b) => b.name), ['斗破苍穹', '武动乾坤']);
    expect(results.first.author, '天蚕土豆');
    expect(results.first.kind, '玄幻,热血');
    expect(results.first.intro, '少年萧炎的故事');
    final book = results.first.toBook();
    await SourceApi.bookInfo(source, book);
    expect(book.tocUrl, '${site.base}/book/1/toc');
    final chapters = await SourceApi.chapters(source, book);
    expect(chapters.map((c) => c.title), ['第一章 陨落的天才', '第二章 斗气大陆', '第三章 归来']);
    final text = await SourceApi.content(source, book, chapters.first, nextChapterUrl: chapters[1].getAbsoluteURL());
    expect(text, '天才一落千丈。\n　　斗之力，三段！\n第二页内容。');
    // without the next chapter's url the pages are followed until there is no next link
    final all = await SourceApi.content(source, book, chapters.first);
    expect(all, endsWith('斗气大陆的第二章。'));
  });

  test('GBK source: keyword encoded in GBK, GBK page decoded through its meta tag', () async {
    final source = load('source_gbk.json');
    final results = await SourceApi.search(source, '斗破');
    expect(site.requests.first, contains('wd=%B6%B7%C6%C6'));
    expect(results.map((b) => b.name), ['斗破苍穹', '武动乾坤']);
    expect(results.first.author, '天蚕土豆');
  });

  test('explore: title::url lists, JSON arrays with flex styles, JS exploreUrl', () async {
    final source = load('source_html.json');
    final kinds = await SourceApi.exploreKinds(source);
    expect(kinds.map((k) => k.title), ['热门', '完结']);
    final hot = await SourceApi.explore(source, kinds.first.url!, page: 2);
    expect(hot.map((b) => b.name), ['斗破苍穹', '武动乾坤']);
    expect(site.requests.last, contains('q=hot&page=2'));

    final js = BookSource(
      bookSourceUrl: site.base,
      exploreUrl: '@js:JSON.stringify([{"title":"A","url":"/a","style":{"layout_flexGrow":1,"layout_flexBasisPercent":0.5}},{"title":"B","url":"/b","type":1}])',
    );
    final k2 = await SourceApi.exploreKinds(js);
    expect(k2.map((k) => k.title), ['A', 'B']);
    expect(k2.first.style!.layoutFlexBasisPercent, 0.5);
    expect(k2.first.style!.layoutFlexGrow, 1);
    expect(k2[1].toExplore().type_, 1);
    // cached: a second call does not run the script again
    js.exploreUrl = '@js:throw new Error("not cached")';
    expect((await SourceApi.exploreKinds(js)).length, 2);
    expect((await SourceApi.exploreKinds(js, refresh: true)).first.title, 'ERROR');
  });

  test('searchAll streams per-source results and reports failures', () async {
    final sources = [load('source_html.json'), load('source_json.json'), load('source_gbk.json'), BookSource(bookSourceUrl: 'http://broken.invalid', bookSourceName: 'broken')];
    final results = await SourceApi.searchAll(sources, '斗破', concurrency: 2).toList();
    expect(results.length, 4);
    expect(results.where((r) => r.ok).length, 3);
    expect(results.firstWhere((r) => !r.ok).source.bookSourceName, 'broken');
    expect(results.where((r) => r.ok).every((r) => r.books.length == 2), isTrue);
  });

  test('RSS: default feed parser and rule-based lists with paging and content', () async {
    final feed = RssSource(sourceUrl: site.base, sourceName: 'feed', sortUrl: '最新::/rss');
    final sorts = await RssRunapi.sorts(feed);
    expect(sorts, [('最新', '/rss')]);
    final (articles, next) = await RssRunapi.articles(feed, sorts.first.$1, sorts.first.$2);
    expect(next, isNull);
    expect(articles.map((a) => a.title), ['First post', 'Second post']);
    expect(articles.first.link, '${site.base}/post/1');
    expect(articles.first.image, '${site.base}/i/1.png');
    expect(articles[1].image, '${site.base}/i/2.png');
    expect(articles[1].link, 'http://other.example/post/2');
    expect(articles.first.pubDate, 'Mon, 01 Jan 2024 10:00:00 GMT');

    final ruled = RssSource(
      sourceUrl: site.base,
      ruleArticles: 'class.book',
      ruleTitle: 'class.name@text',
      ruleLink: 'class.name@href',
      ruleImage: 'class.cover@src',
      ruleDescription: 'class.desc@text',
      ruleNextPage: 'PAGE',
      ruleContent: 'id.content@html',
    );
    final (list, nextUrl) = await RssRunapi.articles(ruled, '', '/html/search?q=rss&page={{page}}', page: 3);
    expect(list.length, 3);
    expect(list.first.title, '斗破苍穹');
    expect(list.first.link, '${site.base}/book/1');
    expect(list.first.image, '${site.base}/img/1.jpg');
    expect(nextUrl, '${site.base}/html/search?q=rss&page={{page}}');
    list.first.link = '${site.base}/chapter/1';
    final html = await RssRunapi.content(ruled, list.first);
    expect(html, contains('天才一落千丈'));
    expect(list.first.toModel().title, '斗破苍穹');
  });

  test('source jsLib, imageDecode and cover decode hooks', () async {
    final source = BookSource(bookSourceUrl: site.base, jsLib: 'function up(s){ return String(s).toUpperCase() }');
    final r = AnalyzeRule(Book(), source)..setContent('<p>abc</p>', site.base);
    expect(await r.getString('tag.p@text@js:up(result)'), 'ABC');
    source.ruleContent = null;
    source.getContentRule().imageDecode = '@js:result.map(function(b){ return b ^ 1 })';
    final out = await SourceApi.decodeImage(source, Book(), null, '${site.base}/x.png', Uint8List.fromList([1, 2, 3]));
    expect(out, [0, 3, 2]);
    source.coverDecodeJs = '<js>java.base64Encode("cover")</js>';
    final cover = await SourceApi.decodeCover(source, '${site.base}/c.jpg', Uint8List.fromList([9]));
    expect(String.fromCharCodes(cover), 'cover');
  });

  test('errors surface as readable exceptions', () async {
    final noSearch = BookSource(bookSourceUrl: site.base);
    expect(() => SourceApi.search(noSearch, 'x'), throwsA(isA<WebBookException>()));
    final source = load('source_html.json');
    final book = Book(bookUrl: '${site.base}/book/1', origin: site.base)..tocUrl = '${site.base}/missing';
    expect(() => SourceApi.chapters(source, book), throwsA(isA<WebBookException>()));
  });
}
