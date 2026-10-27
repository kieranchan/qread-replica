// Fixture builders shared by the reader tests: PNG headers, a PalmDOC MOBI writer, a minimal EPUB.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A PNG header with the given size (enough for the size reader; not a decodable image).
Uint8List pngHeader(int w, int h) {
  final b = BytesBuilder();
  b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  b.add([w >> 24, (w >> 16) & 255, (w >> 8) & 255, w & 255, h >> 24, (h >> 16) & 255, (h >> 8) & 255, h & 255]);
  b.add([8, 6, 0, 0, 0, 0, 0, 0, 0]);
  return b.toBytes();
}

/// PalmDOC encoder that only emits literals (valid stream, no back references).
Uint8List palmEncodeLiterals(Uint8List data) {
  final out = <int>[];
  bool lit(int b) => b == 0 || (b >= 9 && b <= 0x7F);
  var i = 0;
  while (i < data.length) {
    if (lit(data[i])) {
      out.add(data[i++]);
    } else {
      var j = i;
      while (j < data.length && j - i < 8 && !lit(data[j])) {
        j++;
      }
      out.add(j - i);
      out.addAll(data.sublist(i, j));
      i = j;
    }
  }
  return Uint8List.fromList(out);
}

/// A MOBI 6 file with [text] (already in the target encoding), compression 1 or 2, optional image records.
Uint8List buildMobi({
  required Uint8List text,
  int compression = 2,
  List<Uint8List> images = const [],
  String title = 'MOBI Title',
  String author = 'MOBI Author',
  int version = 6,
  int encryption = 0,
  int encoding = 65001,
}) {
  const recSize = 4096;
  final chunks = <Uint8List>[];
  for (var i = 0; i < text.length; i += recSize) {
    chunks.add(Uint8List.sublistView(text, i, i + recSize > text.length ? text.length : i + recSize));
  }
  final textRecs = [for (final c in chunks) compression == 2 ? palmEncodeLiterals(c) : Uint8List.fromList(c)];

  final exth = BytesBuilder();
  void rec(int type, List<int> data) {
    final h = ByteData(8)
      ..setUint32(0, type)
      ..setUint32(4, 8 + data.length);
    exth.add(h.buffer.asUint8List());
    exth.add(data);
  }

  rec(100, utf8.encode(author));
  rec(503, utf8.encode(title));
  rec(103, utf8.encode('<p>简介</p>'));
  rec(201, [0, 0, 0, 0]);
  final exthBody = exth.toBytes();
  var exthLen = 12 + exthBody.length;
  exthLen += (4 - exthLen % 4) % 4;
  final exthBytes = Uint8List(exthLen);
  exthBytes.setAll(0, ascii.encode('EXTH'));
  ByteData.sublistView(exthBytes)
    ..setUint32(4, exthLen)
    ..setUint32(8, 4);
  exthBytes.setAll(12, exthBody);

  const hlen = 232;
  final nameBytes = utf8.encode(title);
  final r0 = Uint8List(16 + hlen + exthLen + nameBytes.length + 2);
  final d = ByteData.sublistView(r0)
    ..setUint16(0, compression)
    ..setUint32(4, text.length)
    ..setUint16(8, textRecs.length)
    ..setUint16(10, recSize)
    ..setUint16(12, encryption);
  r0.setAll(16, ascii.encode('MOBI'));
  d
    ..setUint32(20, hlen)
    ..setUint32(24, 2)
    ..setUint32(28, encoding)
    ..setUint32(36, version)
    ..setUint32(84, 16 + hlen + exthLen)
    ..setUint32(88, nameBytes.length)
    ..setUint32(108, images.isEmpty ? 0xFFFFFFFF : 1 + textRecs.length)
    ..setUint32(128, 0x40)
    ..setUint16(0xF2, 0);
  r0.setAll(16 + hlen, exthBytes);
  r0.setAll(16 + hlen + exthLen, nameBytes);

  final records = <Uint8List>[r0, ...textRecs, ...images];
  final headerLen = 78 + 8 * records.length + 2;
  final out = BytesBuilder();
  final pdb = Uint8List(headerLen);
  pdb.setAll(0, ascii.encode('MobiTest'));
  pdb.setAll(60, ascii.encode('BOOKMOBI'));
  final pd = ByteData.sublistView(pdb)..setUint16(76, records.length);
  var offset = headerLen;
  for (var i = 0; i < records.length; i++) {
    pd.setUint32(78 + 8 * i, offset);
    offset += records[i].length;
  }
  out.add(pdb);
  for (final r in records) {
    out.add(r);
  }
  return out.toBytes();
}

/// Standard MOBI test book: cover page, TOC page with `filepos` links, two chapters (the first has an image).
({Uint8List bytes, String html}) mobiBook({int compression = 2}) {
  String html(int toc, int c1, int c2) => '<html><head><guide><reference type="toc" title="目录" filepos=${toc.toString().padLeft(10, '0')} /></guide></head><body>'
      '<p>封面简介文字</p><mbp:pagebreak/>'
      '<h2>目录</h2><p><a filepos=${c1.toString().padLeft(10, '0')}>第一章 起</a></p><p><a filepos=${c2.toString().padLeft(10, '0')}>第二章 承</a></p><mbp:pagebreak/>'
      '<h2>第一章 起</h2><p>起的正文。</p><img recindex="00001"/><mbp:pagebreak/>'
      '<h2>第二章 承</h2><p>承的正文。</p></body></html>';
  int at(String s, String marker) => utf8.encode(s.substring(0, s.indexOf(marker))).length;
  var s = html(0, 0, 0);
  final toc = at(s, '<h2>目录</h2>');
  final c1 = at(s, '<h2>第一章 起</h2>');
  final c2 = at(s, '<h2>第二章 承</h2>');
  s = html(toc, c1, c2);
  final bytes = buildMobi(text: Uint8List.fromList(utf8.encode(s)), compression: compression, images: [pngHeader(64, 32)]);
  return (bytes: bytes, html: s);
}

/// A minimal EPUB 3 with two chapters.
File buildSimpleEpub(Directory dir, {String name = 'simple.epub', String title = '简单 EPUB'}) {
  final a = Archive();
  void add(String n, List<int> data) => a.addFile(ArchiveFile(n, data.length, data));
  add('mimetype', utf8.encode('application/epub+zip'));
  add('META-INF/container.xml', utf8.encode('<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
      '<rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'));
  add('content.opf', utf8.encode('<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>$title</dc:title><dc:creator>作者甲</dc:creator></metadata><manifest>'
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
      '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="a"/><itemref idref="b"/></spine></package>'));
  add('nav.xhtml', utf8.encode('<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol>'
      '<li><a href="a.xhtml">甲章</a></li><li><a href="b.xhtml">乙章</a></li></ol></nav></body></html>'));
  add('a.xhtml', utf8.encode('<html><body><h1>甲章</h1><p>甲章的正文。</p></body></html>'));
  add('b.xhtml', utf8.encode('<html><body><h1>乙章</h1><p>乙章的正文。</p></body></html>'));
  final f = File('${dir.path}/$name');
  f.writeAsBytesSync(ZipEncoder().encode(a));
  return f;
}
