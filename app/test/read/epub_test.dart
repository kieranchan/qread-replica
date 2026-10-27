// EPUB: package/TOC parsing (nav + ncx), chapter splitting by TOC fragments, HTML -> blocks, images, cover, layout round trip.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/read/api/calculate/calculate_hapter.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/epub/epub_file.dart';
import 'package:newread/read/epub/epub_html.dart';
import 'package:newread/read/setting/read_layout_style.dart';
import 'package:newread/util/image/image_size.dart';

/// A PNG header with the given size (enough for [ImageSizeReader]; not a decodable image).
Uint8List _png(int w, int h) {
  final b = BytesBuilder();
  b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  b.add([w >> 24, (w >> 16) & 255, (w >> 8) & 255, w & 255, h >> 24, (h >> 16) & 255, (h >> 8) & 255, h & 255]);
  b.add([8, 6, 0, 0, 0, 0, 0, 0, 0]);
  return b.toBytes();
}

void _add(Archive a, String name, List<int> data) => a.addFile(ArchiveFile(name, data.length, data));

String _xhtml(String body, {String title = 'T'}) =>
    '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title></head><body>$body</body></html>';

File _buildEpub3(Directory dir) {
  final a = Archive();
  _add(a, 'mimetype', utf8.encode('application/epub+zip'));
  _add(a, 'META-INF/container.xml', utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''));
  _add(a, 'OEBPS/content.opf', utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:uuid:1</dc:identifier>
    <dc:title>测试 EPUB</dc:title>
    <dc:creator>张三</dc:creator>
    <dc:creator>李四</dc:creator>
    <dc:language>zh</dc:language>
    <dc:description>&lt;p&gt;一本&lt;b&gt;测试&lt;/b&gt;书&lt;/p&gt;</dc:description>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover-img" href="images/cover.png" media-type="image/png"/>
    <item id="pic" href="images/pic.png" media-type="image/png"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="c3" href="text/ch%203.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/></spine>
</package>'''));
  _add(a, 'OEBPS/nav.xhtml', utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="toc"><ol>
  <li><a href="text/ch1.xhtml">第一章 开始</a></li>
  <li><span>第二卷</span><ol>
    <li><a href="text/ch2.xhtml#s1">第二章 前半</a></li>
    <li><a href="text/ch2.xhtml#s2">第三章 后半</a></li>
  </ol></li>
</ol></nav></body></html>'''));
  _add(a, 'OEBPS/images/cover.png', _png(300, 400));
  _add(a, 'OEBPS/images/pic.png', _png(120, 80));
  _add(a, 'OEBPS/text/ch1.xhtml', utf8.encode(_xhtml('''
<h1>第一章 开始</h1>
<p>第一段内容，包含<b>粗体</b>和一个<a id="x1"/>锚点。</p>
<p><img src="../images/pic.png" alt="x"/></p>
<p>图片之后的一段。</p>''')));
  _add(a, 'OEBPS/text/ch2.xhtml', utf8.encode(_xhtml('''
<h2 id="s1">第二章 前半</h2><p>前半的正文一。</p><p>前半的正文二。</p>
<h2 id="s2">第三章 后半</h2><p>后半的正文。</p>''')));
  _add(a, 'OEBPS/text/ch 3.xhtml', utf8.encode(_xhtml('<h1>附录</h1><p>没有目录项的附录页。</p>', title: '附录页')));
  final f = File('${dir.path}/book3.epub');
  f.writeAsBytesSync(ZipEncoder().encode(a));
  return f;
}

File _buildEpub2(Directory dir) {
  final a = Archive();
  _add(a, 'META-INF/container.xml', utf8.encode('''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>
<rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''));
  _add(a, 'content.opf', utf8.encode('''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>Old Book</dc:title><dc:creator>Someone</dc:creator></metadata>
<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="a" href="a.html" media-type="application/xhtml+xml"/><item id="b" href="b.html" media-type="application/xhtml+xml"/></manifest>
<spine toc="ncx"><itemref idref="a"/><itemref idref="b"/></spine></package>'''));
  _add(a, 'toc.ncx', utf8.encode('''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
<navPoint id="n1"><navLabel><text>Chapter One</text></navLabel><content src="a.html"/></navPoint>
<navPoint id="n2"><navLabel><text>Chapter Two</text></navLabel><content src="b.html"/></navPoint>
</navMap></ncx>'''));
  _add(a, 'a.html', utf8.encode('<html><body><p>Alpha paragraph.</p></body></html>'));
  _add(a, 'b.html', utf8.encode('<html><body><p>Beta paragraph.</p></body></html>'));
  final f = File('${dir.path}/book2.epub');
  f.writeAsBytesSync(ZipEncoder().encode(a));
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_epub_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('EPUB 3: metadata, nav TOC, fragment chapters, unlisted spine items, cover', () async {
    final f = _buildEpub3(tmp);
    final coverDir = Directory('${tmp.path}/covers');
    final res = await EpubFile.parse(f, bookUrl: 'books/book3.epub', coverDir: coverDir);
    expect(res.name, '测试 EPUB');
    expect(res.author, '张三, 李四');
    expect(res.language, 'zh');
    expect(res.intro, '一本测试书');
    expect(res.coverFile, endsWith('.png'));
    expect(ImageSizeReader.fromFile(File(res.coverFile)), const Size(300, 400));

    expect(res.chapters.map((c) => c.name).toList(), ['第一章 开始', '第二章 前半', '第三章 后半', '附录']);
    expect(res.chapters.map((c) => c.index).toList(), [0, 1, 2, 3]);
    // ch2 is split at the TOC anchors
    expect(res.chapters[1].chapterId, 'OEBPS/text/ch2.xhtml');
    expect(res.chapters[1].tag, '');
    expect(res.chapters[1].baseUrl, 's2');
    expect(res.chapters[2].tag, 's2');
    expect(res.chapters[2].baseUrl, '');
    // percent-encoded href resolved to the real entry name
    expect(res.chapters[3].chapterId, 'OEBPS/text/ch 3.xhtml');
  });

  test('EPUB 3: chapter content, title heading dropped, images extracted, fragments cut', () async {
    final f = _buildEpub3(tmp);
    final res = await EpubFile.parse(f, bookUrl: 'b');
    final imgDir = Directory('${tmp.path}/img');

    final c1 = await EpubFile.getChapterContent(f, res.chapters[0], imageDir: imgDir);
    expect(c1.text, '第一段内容，包含粗体和一个锚点。\n图片之后的一段。'); // heading removed, image takes no characters
    expect(c1.blocks.length, 3);
    expect(c1.blocks[1].isImage, isTrue);
    final imgPath = c1.blocks[1].runs.first.href;
    expect(File(imgPath).existsSync(), isTrue);
    expect(ImageSizeReader.fromFile(File(imgPath)), const Size(120, 80));
    expect(c1.blocks[1].runs.first.start, '第一段内容，包含粗体和一个锚点。'.length);
    // offsets of every text run match the text
    for (final b in c1.blocks.where((b) => !b.isImage)) {
      for (final r in b.runs) {
        expect(c1.text.substring(r.start, r.end), r.str);
      }
    }
    // bold run + anchor id
    final para = c1.blocks.first.runs;
    expect(para.any((r) => r.style.contains('bold') && r.str == '粗体'), isTrue);
    expect(para.any((r) => r.id == 'x1'), isTrue);

    final c2a = await EpubFile.getChapterContent(f, res.chapters[1]);
    expect(c2a.text, '前半的正文一。\n前半的正文二。');
    final c2b = await EpubFile.getChapterContent(f, res.chapters[2]);
    expect(c2b.text, '后半的正文。');
    final c3 = await EpubFile.getChapterContent(f, res.chapters[3]);
    expect(c3.text, '没有目录项的附录页。');
  });

  test('EPUB 3 chapter goes through the layout engine without losing text', () async {
    final f = _buildEpub3(tmp);
    final res = await EpubFile.parse(f, bookUrl: 'b');
    final content = await EpubFile.getChapterContent(f, res.chapters[0], imageDir: Directory('${tmp.path}/img'));
    const engine = CalculateChapter(
      style: ReadLayoutStyle(fontSize: 16, padding: EdgeInsets.all(10)),
      imageSizeOf: ImageSizeReader.resolve,
    );
    final pages = await engine.calculate(size: const Size(200, 150), blocks: content.blocks, title: res.chapters[0].name);
    final sb = StringBuffer();
    var imageSeen = false;
    for (final p in pages) {
      for (final c in p.contents) {
        if (c.isImage) imageSeen = true;
        for (final l in c.lines) {
          for (final cl in l.clines) {
            if (cl.start >= 0 && !cl.isImage) sb.write(cl.str);
          }
        }
      }
    }
    expect(sb.toString(), content.text.replaceAll('\n', ''));
    expect(imageSeen, isTrue);
    // the anchor "x1" is on a page
    expect(CalculateChapter.pageIndexForAnchor(pages, 'x1'), greaterThanOrEqualTo(0));
  });

  test('EPUB 2 with toc.ncx and a relative OPF at the archive root', () async {
    final f = _buildEpub2(tmp);
    final res = await EpubFile.parse(f);
    expect(res.name, 'Old Book');
    expect(res.chapters.map((c) => c.name).toList(), ['Chapter One', 'Chapter Two']);
    final c = await EpubFile.getChapterContent(f, res.chapters[1]);
    expect(c.text, 'Beta paragraph.');
  });

  test('garbage is rejected with a readable error', () async {
    final f = File('${tmp.path}/bad.epub')..writeAsStringSync('not a zip at all');
    expect(EpubFile.parse(f), throwsA(anything));
  });

  group('EpubHtml', () {
    final xhtml = File('test/fixtures/read/chapter.xhtml').readAsStringSync();

    test('paragraphs, inline styles, hard-wrapped CJK, hidden/script content, <br>, <pre>', () {
      final c = EpubHtml.toContent(xhtml, archiveDir: 'OEBPS/text', resolveImage: (p) => '/cache/$p');
      final texts = c.blocks.where((b) => !b.isImage).map((b) => b.runs.map((r) => r.str).join()).toList();
      expect(texts[0], '第一章 开始');
      expect(texts[1], '这是第一段，源码里被硬换行拆开，中间不应出现空格。加粗与斜体以及[1]脚注。');
      expect(texts[2], '居中的一行');
      expect(texts[3], 'Hello world, English text keeps single spaces.');
      expect(texts[4], '换行后的新段落。');
      expect(texts.contains('隐藏内容不应出现'), isFalse);
      expect(c.text.contains('var x'), isFalse);
      expect(texts.sublist(5), ['第一行代码', '第二行代码', '脚注内容。']);

      final heading = c.blocks.first.runs.first;
      expect(heading.ish, isTrue);
      expect(heading.styles, contains('h1'));
      expect(heading.id, 'top'); // the id of the empty <a id="top"/> in front of the heading moves to the next run
      final p1 = c.blocks[1].runs;
      expect(p1.firstWhere((r) => r.str == '加粗').styles, contains('bold'));
      expect(p1.firstWhere((r) => r.str == '斜体').styles, contains('italic'));
      final note = p1.firstWhere((r) => r.str == '[1]');
      expect(note.noteref, isTrue);
      expect(note.href, '#n1');
      expect(c.blocks[2].runs.first.styles, contains('center'));
      // anchors
      expect(c.blocks[4].runs.first.id, 'mid');
      // images: <img> and svg <image>, resolved against the document directory
      final images = c.blocks.where((b) => b.isImage).map((b) => b.runs.first.href).toList();
      expect(images, ['/cache/OEBPS/images/pic.png', '/cache/OEBPS/images/pic2.png']);
      // every run's offsets index the text
      for (final b in c.blocks.where((b) => !b.isImage)) {
        for (final r in b.runs) {
          expect(c.text.substring(r.start, r.end), r.str);
        }
        expect(b.runs.first.isfirst, isTrue);
      }
    });

    test('images without a resolver result are dropped; data URIs are kept', () {
      final c = EpubHtml.toContent('<p>a</p><img src="x.png"/><img src="data:image/png;base64,AAAA"/>', resolveImage: (p) => null);
      expect(c.blocks.where((b) => b.isImage), isEmpty);
      final d = EpubHtml.toContent('<p>a</p><img src="data:image/png;base64,AAAA"/>', resolveImage: (p) => p);
      expect(d.blocks.where((b) => b.isImage).single.runs.first.href, startsWith('data:image/png'));
    });

    test('guessTitle prefers headings, then <title>', () {
      expect(EpubHtml.guessTitle('<html><head><title>Doc</title></head><body><h1>Real <i>Title</i></h1></body></html>'), 'Real Title');
      expect(EpubHtml.guessTitle('<html><head><title>Doc &amp; Co</title></head><body><p>x</p></body></html>'), 'Doc & Co');
      expect(EpubHtml.guessTitle('<p>nothing</p>'), isNull);
    });

    test('normalizeArchivePath', () {
      expect(normalizeArchivePath('OEBPS/text/../images/./a.png'), 'OEBPS/images/a.png');
      expect(normalizeArchivePath('../a.png'), 'a.png');
    });
  });

  group('ImageSizeReader', () {
    test('PNG, GIF, JPEG, WebP(VP8X), BMP, SVG, data URI', () {
      expect(ImageSizeReader.fromBytes(_png(7, 9)), const Size(7, 9));
      expect(ImageSizeReader.fromBytes(Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 10, 0, 20, 0, 0, 0])), const Size(10, 20));
      // JPEG: SOI, APP0 (len 16), SOF0 (h=64, w=128)
      final jpg = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, //
        0xFF, 0xC0, 0, 17, 8, 0, 64, 0, 128, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1,
      ]);
      expect(ImageSizeReader.fromBytes(jpg), const Size(128, 64));
      final webp = Uint8List(32)
        ..setAll(0, [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x58, 0, 0, 0, 0, 0, 0, 0, 0, 99, 0, 0, 49, 0, 0]);
      expect(ImageSizeReader.fromBytes(webp), const Size(100, 50));
      final bmp = Uint8List(30)
        ..setAll(0, [0x42, 0x4D])
        ..buffer.asByteData().setInt32(18, 33, Endian.little)
        ..buffer.asByteData().setInt32(22, -44, Endian.little);
      expect(ImageSizeReader.fromBytes(bmp), const Size(33, 44));
      expect(ImageSizeReader.fromBytes(Uint8List.fromList(utf8.encode('<svg xmlns="x" width="64" height="32"></svg>'))), const Size(64, 32));
      expect(ImageSizeReader.fromDataUri('data:image/png;base64,${base64Encode(_png(5, 6))}'), const Size(5, 6));
      expect(ImageSizeReader.fromBytes(Uint8List.fromList(List.filled(20, 1))), isNull);
    });
  });
}
