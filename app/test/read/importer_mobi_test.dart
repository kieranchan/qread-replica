// MOBI (PalmDOC) parsing and the LocalBookImporter (txt / epub / mobi): book fields, chapter cache, lazy chapter text, delete.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/txt_toc_rule.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/local_book_importer.dart';
import 'package:newread/read/mobi/mobi_file.dart';
import 'package:newread/read/util/chapter_content.dart';

import 'support/fixtures.dart';

void main() {
  late Directory tmp;
  setUp(() {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_imp_');
    ReadStorageRoot.dir = Directory('${tmp.path}/root')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('PalmDOC', () {
    test('decompressor: literals, count-prefixed bytes, space pairs and back references', () {
      // "abc" + (dist 3, len 6) + 0xC1 (space + 'A') + count-prefixed 0x01 0xE4 0xB8 (3 raw bytes)
      final data = Uint8List.fromList([0x61, 0x62, 0x63, 0x80, 0x1B, 0xC1, 3, 0xE4, 0xB8, 0xAD]);
      final out = MobiFile.palmDocDecompress(data);
      expect(utf8.decode(out), 'abcabcabc A中');
    });

    test('literal encoder round-trips arbitrary bytes', () {
      final src = Uint8List.fromList(utf8.encode('中文 text\u0001\u0002 with \u0000 nul and 1..8 bytes'));
      expect(MobiFile.palmDocDecompress(palmEncodeLiterals(src)), src);
    });

    test('trailing entries: multibyte overlap flag and a size-prefixed entry', () {
      // flags 0b01: last byte & 3 = 2 -> 3 bytes of overlap
      final rec = Uint8List.fromList([1, 2, 3, 4, 5, 0x02]);
      expect(MobiFile.trailingSize(rec, 1), 3);
      // flags 0b10: backward varint size entry; last byte 0x84 (0x80 stop bit | 4) -> 4 bytes including itself
      final rec2 = Uint8List.fromList([9, 9, 9, 9, 9, 0x84]);
      expect(MobiFile.trailingSize(rec2, 2), 4);
      expect(MobiFile.trailingSize(rec, 0), 0);
    });
  });

  group('MOBI file', () {
    for (final compression in [1, 2]) {
      test('compression $compression: metadata, TOC chapters, images, cover, chapter text', () async {
        final book = mobiBook(compression: compression);
        final f = File('${tmp.path}/book.mobi')..writeAsBytesSync(book.bytes);
        final work = Directory('${tmp.path}/work');
        final res = await MobiFile.parse(f, workDir: work, coverDir: Directory('${tmp.path}/covers'), bookUrl: 'b');
        expect(res.name, 'MOBI Title');
        expect(res.author, 'MOBI Author');
        expect(res.intro, '简介');
        expect(res.charset, 'UTF-8');
        expect(res.coverFile, endsWith('.png'));
        expect(File('${work.path}/text.html').readAsStringSync(), book.html);
        expect(res.chapters.map((c) => c.name).toList(), ['前言', '第一章 起', '第二章 承']);

        final c1 = await MobiFile.getChapterContent(res.chapters[1], res.charset);
        expect(c1.text, '起的正文。'); // title heading dropped
        expect(c1.blocks.last.isImage, isTrue);
        expect(c1.blocks.last.runs.first.href, endsWith('img_1.png'));
        final c2 = await MobiFile.getChapterContent(res.chapters[2], res.charset);
        expect(c2.text, '承的正文。');
        final pro = await MobiFile.getChapterContent(res.chapters[0], res.charset);
        expect(pro.text, contains('封面简介文字'));
      });
    }

    test('unsupported variants are reported clearly', () async {
      final text = Uint8List.fromList(utf8.encode('<html><body><p>x</p></body></html>'));
      final cases = <(String, Uint8List)>[
        ('Huffman', buildMobi(text: text, compression: 17480)),
        ('DRM', buildMobi(text: text, encryption: 2)),
        ('KF8', buildMobi(text: text, version: 8)),
      ];
      for (final (name, bytes) in cases) {
        final f = File('${tmp.path}/$name.mobi')..writeAsBytesSync(bytes);
        await expectLater(MobiFile.parse(f, workDir: Directory('${tmp.path}/w$name')), throwsA(isA<MobiException>()), reason: name);
      }
      final junk = File('${tmp.path}/junk.mobi')..writeAsBytesSync(Uint8List(200));
      await expectLater(MobiFile.parse(junk, workDir: Directory('${tmp.path}/wj')), throwsA(isA<MobiException>()));
    });

    test('without a TOC the page breaks split the book', () async {
      final html = '<html><body><h1>甲</h1><p>一一。</p><mbp:pagebreak/><h1>乙</h1><p>二二。</p><mbp:pagebreak/><h1>丙</h1><p>三三。</p></body></html>';
      final f = File('${tmp.path}/pb.mobi')..writeAsBytesSync(buildMobi(text: Uint8List.fromList(utf8.encode(html))));
      final res = await MobiFile.parse(f, workDir: Directory('${tmp.path}/wpb'));
      expect(res.chapters.map((c) => c.name).toList(), ['甲', '乙', '丙']);
    });
  });

  group('LocalBookImporter', () {
    const importer = LocalBookImporter();

    test('format detection', () {
      expect(LocalBookImporter.formatOf('/a/b.TXT'), 'txt');
      expect(LocalBookImporter.formatOf('x.epub'), 'epub');
      expect(LocalBookImporter.formatOf('x.azw3'), 'mobi');
      expect(LocalBookImporter.formatOf('x.pdf'), 'pdf'); // PDF books like the original
      expect(() => LocalBookImporter.formatOf('x.doc'), throwsA(isA<LocalBookException>()));
      expect(LocalBookImporter.isSupported('a.mobi'), isTrue);
      expect(LocalBookImporter.isSupported('a.doc'), isFalse);
    });

    test('TXT (GBK): Book fields, copy into the library, chapter cache, lazy chapter text, delete', () async {
      final sb = StringBuffer('前言一句\n');
      for (var i = 1; i <= 5; i++) {
        sb.write('第$i章 标题$i\n正文$i的第一段。\n正文$i的第二段。\n');
      }
      final src = File('${tmp.path}/《测试书》作者：某人.txt')..writeAsBytesSync(gbk.encode(sb.toString()));
      final rules = [TxtTocRule(name: 'r', rule: r'^第\d+章.*$', isEnabled: true)];
      final local = await importer.import(src, txtRules: rules);

      final book = local.book;
      expect(local.format, 'txt');
      expect(book.name, '测试书');
      expect(book.author, '某人');
      expect(book.origin, 'loc_book');
      expect(book.bookUrl, 'books/《测试书》作者：某人.txt');
      expect(book.charset, 'GBK');
      expect(book.totalChapterNum, 6);
      expect(book.latestChapterTitle, '第5章 标题5');
      expect(book.durChapterTitle, '前言');
      expect(ReadApi.isLocalBook(book), isTrue);
      expect(LocalBookImporter.fileOf(book).path, local.file.path);
      expect(local.file.existsSync(), isTrue);
      expect(local.file.path.replaceAll('\\', '/'), startsWith(ReadStorageRoot.dir.path.replaceAll('\\', '/')));

      // chapter text is read lazily from the copied file
      final c3 = await importer.loadChapterContent(book, local.chapters[3]);
      expect(c3.text.trimRight(), '正文3的第一段。\n正文3的第二段。');
      expect(c3.blocks.length, 2);

      // the cached chapter list is used when present (tamper with the cache to prove it), re-parse otherwise
      final chapters = await importer.loadChapters(book, txtRules: rules);
      expect(chapters.length, 6);
      final cache = File('${ReadStorageRoot.dir.path}/books/${ReadFileStore.md5Hex(book.bookUrl)}.chapters.json');
      expect(cache.existsSync(), isTrue);
      cache.writeAsStringSync(jsonEncode([chapters.first.toJson()]));
      expect((await importer.loadChapters(book)).length, 1);
      expect((await importer.loadChapters(book, txtRules: rules, reparse: true)).length, 6);

      // importing the same file again does not duplicate it
      final again = await importer.import(src, txtRules: rules);
      expect(again.book.bookUrl, book.bookUrl);

      // through ReadApi
      final api = ReadApi(book, chapters: chapters, loader: importer.loaderFor(book));
      final rc = await api.loadChapter(2);
      expect(rc.content.text, startsWith('正文2的第一段'));
      expect(rc.title, '第2章 标题2');

      await importer.delete(book);
      expect(local.file.existsSync(), isFalse);
      expect(cache.existsSync(), isFalse);
    });

    test('TXT without copy keeps the absolute path; empty files are rejected', () async {
      final src = File('${tmp.path}/x.txt')..writeAsStringSync('第一章\n一\n第二章\n二\n');
      final local = await importer.import(src, copy: false, txtRules: [TxtTocRule(name: 'r', rule: r'^第.章$', isEnabled: true)]);
      expect(local.book.bookUrl, src.path);
      expect(local.chapters.length, 2);
      final empty = File('${tmp.path}/empty.txt')..writeAsBytesSync(Uint8List(0));
      await expectLater(importer.import(empty), throwsA(isA<LocalBookException>()));
      await expectLater(importer.import(File('${tmp.path}/missing.txt')), throwsA(isA<LocalBookException>()));
    });

    test('EPUB', () async {
      final epub = buildSimpleEpub(tmp);
      final local = await importer.import(epub);
      expect(local.format, 'epub');
      expect(local.book.name, '简单 EPUB');
      expect(local.book.author, '作者甲');
      expect(local.book.bookUrl, 'books/simple.epub');
      expect(local.chapters.map((c) => c.name), ['甲章', '乙章']);
      final c = await importer.loadChapterContent(local.book, local.chapters[1]);
      expect(c.text, '乙章的正文。');
      await importer.delete(local.book);
      expect(local.file.existsSync(), isFalse);
    });

    test('MOBI', () async {
      final f = File('${tmp.path}/m.mobi')..writeAsBytesSync(mobiBook().bytes);
      final local = await importer.import(f);
      expect(local.format, 'mobi');
      expect(local.book.name, 'MOBI Title');
      expect(local.book.coverUrl, endsWith('.png'));
      expect(File(local.book.coverUrl).existsSync(), isTrue);
      expect(local.chapters.map((c) => c.name), ['前言', '第一章 起', '第二章 承']);
      final c = await importer.loadChapterContent(local.book, local.chapters[2]);
      expect(c.text, '承的正文。');
      expect(c, isA<ChapterContent>());
      await importer.delete(local.book);
      expect(File(local.book.coverUrl).existsSync(), isFalse);
    });
  });

  test('everything also works through real isolates', () async {
    ReadIsolate.enabled = true;
    addTearDown(() => ReadIsolate.enabled = false);
    const importer = LocalBookImporter();
    final txt = File('${tmp.path}/iso.txt')..writeAsStringSync('第1章 甲\n甲的正文\n第2章 乙\n乙的正文\n');
    final t = await importer.import(txt, txtRules: [TxtTocRule(name: 'r', rule: r'^第\d章.*$', isEnabled: true)]);
    expect(t.chapters.length, 2);
    expect((await importer.loadChapterContent(t.book, t.chapters[1])).text, startsWith('乙的正文'));
    final epub = await importer.import(buildSimpleEpub(tmp, name: 'iso.epub'));
    expect((await importer.loadChapterContent(epub.book, epub.chapters[0])).text, '甲章的正文。');
    final mobiFile = File('${tmp.path}/iso.mobi')..writeAsBytesSync(mobiBook().bytes);
    final mobi = await importer.import(mobiFile);
    expect((await importer.loadChapterContent(mobi.book, mobi.chapters[1])).text, '起的正文。');
  });
}
