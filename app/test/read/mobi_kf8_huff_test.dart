// MOBI additions: HUFF/CDIC compression, KF8 (AZW3) assembly from the skeleton / fragment indexes + NCX table of contents, and the
// original's chapter split (0x254e84 headings, 0x254c18 第N部分 pieces).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/local_book_importer.dart';
import 'package:newread/read/mobi/huffcdic.dart';
import 'package:newread/read/mobi/kf8.dart';
import 'package:newread/read/mobi/mobi_file.dart';
import 'package:newread/read/mobi/mobi_index.dart';
import 'package:newread/read/util/chapter_content.dart';

import 'support/fixtures.dart';
import 'support/mobi_builders.dart';

void main() {
  late Directory tmp;
  setUp(() {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_mobi2_');
    ReadStorageRoot.dir = Directory('${tmp.path}/root')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('HUFF/CDIC', () {
    test('decoder: 8- and 12-bit codes, a phrase that is itself Huffman coded, several CDIC records', () {
      final enc = HuffEncoder(['<p>', '</p>', '的'], recursive: '第一章 ');
      final src = Uint8List.fromList(utf8.encode('<p>第一章 开始的故事</p><p>第一章 again ü</p>'));
      final r = HuffCdicReader(enc.huffRecord(), enc.cdicRecords());
      expect(r.phraseCount, HuffEncoder.total);
      expect(utf8.decode(r.unpack(enc.encode(src))), utf8.decode(src));
      // the expanded phrase is cached: a second record decodes the same
      expect(utf8.decode(r.unpack(enc.encode(src))), utf8.decode(src));
    });

    test('bad tables are reported', () {
      expect(() => HuffCdicReader(Uint8List(30), const []), throwsA(isA<MobiException>()));
    });

    test('a Huffman MOBI book opens: text, chapters from the original heading split', () async {
      final sb = StringBuffer('<html><head></head><body><p>扉页文字</p>');
      for (var i = 1; i <= 3; i++) {
        sb.write('<mbp:pagebreak/><p height="1em" width="0pt" align="center"><font size="5"><b>第$i章 标题$i</b></font></p>');
        sb.write('<p>第$i章的正文，内容${'很长' * 300}。</p>');
      }
      sb.write('</body></html>');
      final html = sb.toString();
      final f = File('${tmp.path}/huff.mobi')..writeAsBytesSync(buildHuffMobi(html, common: ['<p>', '</p>', '很长'], recursive: '的正文'));
      final res = await MobiFile.parse(f, workDir: Directory('${tmp.path}/w'));
      expect(File('${tmp.path}/w/text.html').readAsStringSync(), html);
      expect(res.chapters.map((c) => c.name), ['第1章 标题1', '第2章 标题2', '第3章 标题3']);
      final c2 = await MobiFile.getChapterContent(res.chapters[1], res.charset);
      expect(c2.text, startsWith('第2章的正文'));
      expect(c2.text, isNot(contains('第3章')));
    });
  });

  group('original chapter split', () {
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

    test('0x254e84: headings after page breaks; skipped titles, punctuation, volumes, text before the first heading', () {
      final html = '<html><body><p>前面的文字不进入任何章节</p>'
          '<mbp:pagebreak/><p height="1em">目录</p><p>x</p>' // a skipped title
          '<mbp:pagebreak/><p height="2em"><b>第一卷 风起</b></p><p>卷首</p>'
          '<mbp:pagebreak/><p height="1em"><font size="4">第一章 起</font></p><p>一。</p>'
          '<mbp:pagebreak/><p height="1em">他说：走吧</p><p>不是标题</p>' // punctuation -> not a heading
          '<MBP:PAGEBREAK/><P HEIGHT="1em">第二章 承</P><p>二。</p>'
          '<mbp:pagebreak/><p height="1em">${'长' * 41}</p>'
          '</body></html>';
      final text = bytes(html);
      final ch = MobiFile.headingChapters(text, 65001);
      expect(ch.map((c) => c.$3), ['第一卷 风起', '第一章 起', '第二章 承']);
      expect(ch.map((c) => c.$4), [false, false, false]);
      int at(String marker) => utf8.encode(html.substring(0, html.indexOf(marker))).length;
      expect(ch[0].$1, at('<mbp:pagebreak/><p height="2em">'));
      expect(ch[0].$2, ch[1].$1);
      expect(ch[2].$1, at('<MBP:PAGEBREAK/>'));
      expect(ch[2].$2, text.length);
      final vol = MobiFile.headingChapters(bytes('<x><mbp:pagebreak/><p height="12em">上卷</p><mbp:pagebreak/><p height="1em">第一回</p></x>'), 65001);
      expect(vol.map((c) => c.$4), [true, false]);
    });

    test('0x254c18: 20000-byte pieces cut after a line break in their second half, 第N部分', () {
      final line = '${'字' * 33}\n'; // 100 bytes
      final text = bytes(line * 450); // 45000 bytes
      final ch = MobiFile.pieceChapters(text);
      expect(ch.map((c) => c.$3), ['第1部分', '第2部分', '第3部分']);
      expect(ch[0].$1, 0);
      expect(ch[0].$2, 20000); // the byte at 20000 starts a line; the last '\n' before is at 19999
      expect(ch[1].$1, 20000);
      expect(ch.last.$2, text.length);
      // no line break in the second half: a plain 20000-byte cut
      final flat = bytes('a' * 25000);
      expect(MobiFile.pieceChapters(flat).map((c) => (c.$1, c.$2)), [(0, 20000), (20000, 25000)]);
    });

    test('without headings and TOC the book is cut into pieces', () async {
      final html = '<html><body><h1>甲</h1><p>一一。</p><mbp:pagebreak/><h1>乙</h1><p>二二。</p></body></html>';
      final f = File('${tmp.path}/pb.mobi')..writeAsBytesSync(buildMobi(text: bytes(html)));
      final res = await MobiFile.parse(f, workDir: Directory('${tmp.path}/wpb'));
      expect(res.chapters.map((c) => c.name), ['第1部分']);
      expect((await MobiFile.getChapterContent(res.chapters[0], res.charset)).text, contains('二二。'));
    });
  });

  group('KF8', () {
    test('index reader: TAGX control bytes, multi-value tags, CNCX strings', () {
      final recs = indexRecords(
        [(1, 1, 0x01, 0), (6, 2, 0x02, 0), (0, 0, 0, 1)],
        1,
        [IndexEntrySpec('A', [0x03], [300, 7, 70000]), IndexEntrySpec('B', [0x01], [5])],
        cncx: ['甲', 'bb'],
      );
      final idx = MobiIndex.read((i) => i >= 10 && i < 10 + recs.length ? recs[i - 10] : null, 10);
      expect(idx.entries.map((e) => e.label), ['A', 'B']);
      expect(idx.entries[0].tags, {1: [300], 6: [7, 70000]});
      expect(idx.entries[1].tags, {1: [5]});
      expect(idx.cncx, {0: '甲', 4: 'bb'});
      expect(MobiIndex.vwi(Uint8List.fromList(vwi(70000)), 0), (70000, 3));
    });

    test('assembly from skeleton + fragments, NCX positions, a broken insert position', () {
      for (final bad in [false, true]) {
        final book = buildKf8(badInsert: bad, compression: 1);
        final f = File('${tmp.path}/a$bad.azw3')..writeAsBytesSync(book.bytes);
        final b = f.readAsBytesSync();
        final offs = MobiFile.recordOffsets(b);
        final h = MobiFile.readHeader(b, offs);
        expect(h.isKf8, isTrue);
        final raw = MobiFile.readText(b, offs, h);
        final kf8 = Kf8.assemble(
          raw: raw,
          record: (i) => Uint8List.sublistView(b, offs[i], offs[i + 1]),
          fdst: h.fdst,
          skeleton: h.skeleton,
          fragment: h.fragment,
          ncx: h.ncx,
        );
        expect(utf8.decode(kf8.html), book.html, reason: 'bad=$bad');
        final html = book.html;
        int at(String m) => utf8.encode(html.substring(0, html.indexOf(m))).length;
        expect(kf8.toc, [(at('<h1>第一章'), '第一章 起', 0), (at('<h1>第二章'), '第二章 承', 0)]);
      }
      expect(Kf8.embedIndex('kindle:embed:000A?mime=image/jpeg'), 10);
      expect(Kf8.embedIndex('x.jpg'), isNull);
    });

    test('an AZW3 book imports: metadata, cover, NCX chapters, image, text', () async {
      final book = buildKf8();
      final f = File('${tmp.path}/book.azw3')..writeAsBytesSync(book.bytes);
      final local = await const LocalBookImporter().import(f);
      expect(local.format, 'mobi');
      expect(local.book.name, 'KF8 Title');
      expect(local.book.author, 'KF8 Author');
      expect(local.book.charset, 'UTF-8');
      expect(local.book.coverUrl, endsWith('.png'));
      expect(local.chapters.map((c) => c.name), ['第一章 起', '第二章 承']);
      final c1 = await const LocalBookImporter().loadChapterContent(local.book, local.chapters[0]);
      expect(c1.text, '起的正文。');
      expect(c1.blocks.last.isImage, isTrue);
      expect(c1.blocks.last.runs.first.href, endsWith('img_1.png'));
      final c2 = await const LocalBookImporter().loadChapterContent(local.book, local.chapters[1]);
      expect(c2.text, '承的正文。\n承的第二段。');
      expect(c2, isA<ChapterContent>());
    });
  });
}
