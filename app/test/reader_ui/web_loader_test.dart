// The default web-book loader (WebBookLoader) against the engine's local fake site: table of contents (with Book.reverseCatalog),
// chapter text with <img> blocks, a missing source. No TestWidgetsFlutterBinding here: it would replace HttpClient.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/read/web_book_loader.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/util/legado/cookie_jar.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/webbook/util/cache_manager.dart';

import '../support/env.dart';
import '../util/fake_site.dart';

void main() {
  group('web-book loader (local fake site)', () {
    late FakeSite site;
    setUpAll(() async {
      JsEngines.useDart();
      site = await FakeSite.start();
    });
    tearDownAll(() => site.close());

    test('parseContent splits <img> tags into image blocks', () {
      final c = WebBookLoader.parseContent('　　第一段。\n　　<img src="http://h/a.png">\n尾<img src=\'b.jpg\'>巴');
      expect(c.blocks.length, 5);
      expect(c.blocks[1].isImage, isTrue);
      expect(c.blocks[1].runs.first.href, 'http://h/a.png');
      expect(c.text, '第一段。\n尾\n巴');
      expect(WebBookLoader.parseContent('甲\n乙').isPlainText, isTrue);
    });

    test('chapters and content through the book-source engine', () async {
      await newDevice();
      CookieStore.resetForTests();
      CacheManager.resetForTests();
      final raw = Map<String, dynamic>.from(jsonDecode(site.sourceJson('source_html.json')) as Map);
      Sourcedata.store
        ..items = [raw]
        ..loaded = true;
      final book = Book(
        bookUrl: '${site.base}/book/1',
        tocUrl: '${site.base}/book/1/toc',
        origin: site.base,
        name: '斗破苍穹',
      );
      final chapters = await WebBookLoader.chapters(book);
      expect(chapters.map((c) => c.name), ['第一卷 起源', '第一章 陨落的天才', '第二章 斗气大陆', '第二卷 成长', '第三章 归来']);
      expect(chapters.map((c) => c.index), [0, 1, 2, 3, 4]);
      expect(book.totalChapterNum, 5);

      final content = await WebBookLoader.loaderFor(book)(chapters[1]);
      expect(content.text, startsWith('天才一落千丈。'));
      expect(content.blocks.where((b) => b.isImage).single.runs.first.href, '${site.base}/img/inline.png');

      book.reverseCatalog = true;
      final reversed = await WebBookLoader.chapters(book);
      expect(reversed.first.name, '第三章 归来');
      expect(reversed.first.index, 0);

      final missing = Book(bookUrl: 'u', origin: 'http://nowhere.invalid');
      await expectLater(WebBookLoader.chapters(missing), throwsA(isA<WebBookException>()));
      expect(ReadApi.isLocalBook(book), isFalse);
    });
  });
}
