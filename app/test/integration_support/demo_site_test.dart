// The integration test's demo site + book source must work with the engine (here with the pure-Dart JS interpreter; the simulator
// run uses the device engine).
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/api/sourceapi.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/webbook/model/book_source.dart';

import '../../integration_test/demo_site.dart';

void main() {
  late DemoSite site;

  setUpAll(() async {
    JsEngines.useDart();
    site = await DemoSite.start();
  });
  tearDownAll(() => site.close());

  test('demo source: search -> info -> toc -> content (with the @js: rule)', () async {
    final source = BookSource.fromJsonString(site.sourceJson().substring(1, site.sourceJson().length - 1));
    final results = await SourceApi.search(source, '星河');
    expect(results.map((b) => b.name), ['星河旅人']);
    expect(results.first.author, '林间');

    final book = results.first.toBook();
    await SourceApi.bookInfo(source, book);
    expect(book.intro, contains('货船'));
    expect(book.tocUrl, '${site.base}/book/1/toc');

    final chapters = await SourceApi.chapters(source, book);
    expect(chapters, hasLength(DemoSite.chapterCount));
    expect(chapters.first.title, '第1章 启程');

    final text = await SourceApi.content(source, book, chapters.first);
    expect(text, isNot(contains('广告')));
    expect(text.split('\n').where((l) => l.trim().isNotEmpty), hasLength(18));

    final kinds = await SourceApi.exploreKinds(source);
    expect(kinds.map((k) => k.title), ['热门']);
    final hot = await SourceApi.explore(source, kinds.first.url!);
    expect(hot.map((b) => b.name), ['星河旅人', '山城旧事']);
  });
}
