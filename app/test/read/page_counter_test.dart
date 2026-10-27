// EpubPageCounter: counts pages with the layout engine, caches per configuration, whole-book page numbers.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/models/replacerule.dart';
import 'package:newread/read/setting/read_layout_style.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/util/epub/epub_page_counter.dart';
import 'package:newread/util/epub/epub_rule_cache.dart';
import 'package:newread/util/epub/epub_zh_convert.dart';

ChapterContent _text(int paragraphs) => ChapterContent.fromText(List.generate(paragraphs, (i) => '第$i段' * 30).join('\n'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final counter = EpubPageCounter.instance;
  const style = ReadLayoutStyle(fontSize: 16, padding: EdgeInsets.all(10), titleFontSize: 20);

  test('counts, caches per configuration and invalidates on a change', () async {
    counter.updateSharedConfig(size: const Size(200, 300), style: style);
    final book = Book(bookUrl: 'b');
    final ch = BookChapter(name: '一', index: 0);
    final n = await counter.countChapter(book, ch, _text(20));
    expect(n, greaterThan(2));
    expect(counter.cachedCount(book, 0), n);
    // cached: a different (tiny) content is ignored while the configuration is the same
    expect(await counter.countChapter(book, ch, _text(1)), n);
    // new size: counts dropped, recomputed
    counter.updateSharedConfig(size: const Size(200, 600), style: style);
    expect(counter.cachedCount(book, 0), isNull);
    final n2 = await counter.countChapter(book, ch, _text(20));
    expect(n2, lessThan(n));
    // same configuration again keeps the counts
    counter.updateSharedConfig(size: const Size(200, 600), style: style);
    expect(counter.cachedCount(book, 0), n2);
    // different rules change the fingerprint
    counter.updateSharedConfig(size: const Size(200, 600), style: style, rules: RulePack(replace: [ReplaceRule(pattern: 'x', isEnabled: true)]));
    expect(counter.cachedCount(book, 0), isNull);
  });

  test('countBook: progress callback, failing chapters count as one page, book-wide page numbers', () async {
    counter.updateSharedConfig(size: const Size(200, 300), style: style, rules: RulePack.empty);
    counter.clear();
    final book = Book(bookUrl: 'whole');
    final chapters = [for (var i = 0; i < 3; i++) BookChapter(name: '章$i', index: i)];
    final progress = <int>[];
    final counts = await counter.countBook(book, chapters, (c) async {
      if (c.index == 1) throw StateError('broken');
      return _text(c.index == 0 ? 3 : 30);
    }, onProgress: (done, total) => progress.add(done * 10 + total));
    expect(progress, [13, 23, 33]);
    expect(counts[1], 1);
    expect(counts[2], greaterThan(counts[0]));
    final total = EpubPageCounter.total(counts);
    expect(total, counts.reduce((a, b) => a + b));
    expect(EpubPageCounter.globalPage(counts, 2, 3), counts[0] + counts[1] + 3);
    for (var g = 0; g < total; g++) {
      final (c, p) = EpubPageCounter.locate(counts, g);
      expect(EpubPageCounter.globalPage(counts, c, p), g);
    }
    expect(EpubPageCounter.locate(counts, total + 5).$1, 2);
  });

  test('rule pack fingerprint and helpers', () {
    final a = RulePack(replace: [ReplaceRule(pattern: 'a', isEnabled: true)]);
    final b = RulePack(replace: [ReplaceRule(pattern: 'b', isEnabled: true)]);
    final off = RulePack(replace: [ReplaceRule(pattern: 'c', isEnabled: false)]);
    expect(a.signature, isNot(b.signature));
    expect(off.signature, RulePack.empty.signature, reason: 'disabled rules do not count');
    expect(RulePack.esc('a.b*c'), r'a\.b\*c');
    expect(EpubRuleCache.keyOf(Book(bookUrl: 'x'), a), isNot(EpubRuleCache.keyOf(Book(bookUrl: 'x'), b)));
  });

  test('zh converter hook', () {
    expect(EpubZhConvert.convert('简体', toTraditional: true), '简体');
    EpubZhConvert.converter = (t, trad) => trad ? t.replaceAll('简', '簡') : t;
    addTearDown(() => EpubZhConvert.converter = null);
    expect(EpubZhConvert.convert('简体', toTraditional: true), '簡体');
    expect(EpubZhConvert.convert('', toTraditional: true), '');
  });
}
