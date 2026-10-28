// Writers for synthetic MOBI test books: a HUFF/CDIC encoder (8- and 12-bit codes, a self-referencing phrase, several CDIC records)
// and a KF8-only (AZW3) file with FDST, skeleton / fragment / NCX indexes and an embedded image.
import 'dart:convert';
import 'dart:typed_data';

import 'fixtures.dart';

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();
Uint8List _u16(int v) => (ByteData(2)..setUint16(0, v)).buffer.asUint8List();

/// Forward variable-width integer (high bit marks the last byte).
List<int> vwi(int v) {
  final groups = <int>[v & 0x7F];
  v >>= 7;
  while (v > 0) {
    groups.insert(0, v & 0x7F);
    v >>= 7;
  }
  groups[groups.length - 1] |= 0x80;
  return groups;
}

/// Puts records into a PDB container.
Uint8List pdb(List<Uint8List> records) {
  final headerLen = 78 + 8 * records.length + 2;
  final head = Uint8List(headerLen);
  head.setAll(0, ascii.encode('TestBook'));
  head.setAll(60, ascii.encode('BOOKMOBI'));
  final d = ByteData.sublistView(head)..setUint16(76, records.length);
  var offset = headerLen;
  for (var i = 0; i < records.length; i++) {
    d.setUint32(78 + 8 * i, offset);
    offset += records[i].length;
  }
  final out = BytesBuilder()..add(head);
  for (final r in records) {
    out.add(r);
  }
  return out.toBytes();
}

/// Record 0 with a MOBI header of 0x108 bytes (covers the KF8 fields) and an EXTH block (100 author, 503 title, 201 cover).
Uint8List record0({
  required int compression,
  required int textLength,
  required int textRecords,
  required int version,
  int firstImage = 0xFFFFFFFF,
  int huffRecord = 0,
  int huffCount = 0,
  int extraFlags = 0,
  int fdst = 0xFFFFFFFF,
  int ncx = 0xFFFFFFFF,
  int fragment = 0xFFFFFFFF,
  int skeleton = 0xFFFFFFFF,
  String title = 'Test Title',
  String author = 'Test Author',
  bool cover = true,
}) {
  final exth = BytesBuilder();
  var count = 0;
  void rec(int type, List<int> data) {
    exth
      ..add(_u32(type))
      ..add(_u32(8 + data.length))
      ..add(data);
    count++;
  }

  rec(100, utf8.encode(author));
  rec(503, utf8.encode(title));
  if (cover) rec(201, [0, 0, 0, 0]);
  final body = exth.toBytes();
  var exthLen = 12 + body.length;
  exthLen += (4 - exthLen % 4) % 4;
  final exthBytes = Uint8List(exthLen)..setAll(0, ascii.encode('EXTH'));
  ByteData.sublistView(exthBytes)
    ..setUint32(4, exthLen)
    ..setUint32(8, count);
  exthBytes.setAll(12, body);

  const hlen = 0x108 - 16;
  final name = utf8.encode(title);
  final r0 = Uint8List(16 + hlen + exthLen + name.length + 2);
  final d = ByteData.sublistView(r0)
    ..setUint16(0, compression)
    ..setUint32(4, textLength)
    ..setUint16(8, textRecords)
    ..setUint16(10, 4096);
  r0.setAll(16, ascii.encode('MOBI'));
  d
    ..setUint32(20, hlen)
    ..setUint32(24, 2)
    ..setUint32(28, 65001)
    ..setUint32(36, version)
    ..setUint32(84, 16 + hlen + exthLen)
    ..setUint32(88, name.length)
    ..setUint32(108, firstImage)
    ..setUint32(0x70, huffRecord)
    ..setUint32(0x74, huffCount)
    ..setUint32(128, 0x40)
    ..setUint32(0xC0, fdst)
    ..setUint16(0xF2, extraFlags)
    ..setUint32(0xF4, ncx)
    ..setUint32(0xF8, fragment)
    ..setUint32(0xFC, skeleton);
  r0.setAll(16 + hlen, exthBytes);
  r0.setAll(16 + hlen + exthLen, name);
  return r0;
}

// ------------------------------------------------------------------ HUFF / CDIC

/// Code book: indexes 0..2047 use 12-bit codes `0x7FF - r`, 2048..2175 use 8-bit codes `2303 - r` (top byte 0x80..0xFF).
class HuffEncoder {
  static const int short = 2048;
  static const int total = 2176;

  final List<Uint8List> phrases = List.filled(total, Uint8List(0));
  final List<bool> literal = List.filled(total, true);

  /// Multi-byte phrases (longest first) used by the greedy encoder.
  final List<(Uint8List, int)> _multi = [];

  HuffEncoder(List<String> common, {String? recursive}) {
    for (var b = 0; b < 256; b++) {
      phrases[b] = Uint8List.fromList([b]);
    }
    var next = short;
    for (final c in common) {
      final bytes = Uint8List.fromList(utf8.encode(c));
      phrases[next] = bytes;
      _multi.add((bytes, next));
      next++;
    }
    if (recursive != null) {
      // phrase 256 is stored Huffman coded (flag bit clear) and expands to [recursive]
      final bytes = Uint8List.fromList(utf8.encode(recursive));
      phrases[256] = encode(bytes, multi: false);
      literal[256] = false;
      _multi.add((bytes, 256));
    }
    _multi.sort((a, b) => b.$1.length.compareTo(a.$1.length));
  }

  (int, int) _code(int r) => r < short ? (0x7FF - r, 12) : (2303 - r, 8);

  Uint8List encode(Uint8List data, {bool multi = true}) {
    final bits = <int>[];
    void emit(int r) {
      final (c, n) = _code(r);
      for (var i = n - 1; i >= 0; i--) {
        bits.add((c >> i) & 1);
      }
    }

    var i = 0;
    outer:
    while (i < data.length) {
      if (multi) {
        for (final (p, r) in _multi) {
          if (i + p.length <= data.length) {
            var ok = true;
            for (var k = 0; k < p.length; k++) {
              if (data[i + k] != p[k]) {
                ok = false;
                break;
              }
            }
            if (ok) {
              emit(r);
              i += p.length;
              continue outer;
            }
          }
        }
      }
      emit(data[i]);
      i++;
    }
    while (bits.length % 8 != 0) {
      bits.add(0);
    }
    final out = Uint8List(bits.length ~/ 8);
    for (var k = 0; k < bits.length; k++) {
      if (bits[k] == 1) out[k >> 3] |= 0x80 >> (k & 7);
    }
    return out;
  }

  Uint8List huffRecord() {
    final dict1 = BytesBuilder();
    for (var i = 0; i < 256; i++) {
      // top byte < 0x80: 12-bit codes (not terminal, length from the min/max tables); else 8-bit terminal codes
      dict1.add(_u32(i < 0x80 ? 12 : ((2303 << 8) | 0x80 | 8)));
    }
    final dict2 = BytesBuilder();
    for (var len = 1; len <= 32; len++) {
      dict2
        ..add(_u32(0))
        ..add(_u32(len == 12 ? 0x7FF : 0));
    }
    return Uint8List.fromList([...ascii.encode('HUFF'), ..._u32(24), ..._u32(24), ..._u32(24 + 1024), ..._u32(0), ..._u32(0), ...dict1.toBytes(), ...dict2.toBytes()]);
  }

  /// CDIC records of up to 1 << [bits] phrases each.
  List<Uint8List> cdicRecords({int bits = 10}) {
    final out = <Uint8List>[];
    for (var start = 0; start < total; start += 1 << bits) {
      final n = (start + (1 << bits) > total ? total : start + (1 << bits)) - start;
      final offsets = BytesBuilder();
      final data = BytesBuilder();
      for (var k = 0; k < n; k++) {
        final p = phrases[start + k];
        offsets.add(_u16(2 * n + data.length));
        data
          ..add(_u16(p.length | (literal[start + k] ? 0x8000 : 0)))
          ..add(p);
      }
      out.add(Uint8List.fromList([...ascii.encode('CDIC'), ..._u32(16), ..._u32(total), ..._u32(bits), ...offsets.toBytes(), ...data.toBytes()]));
    }
    return out;
  }
}

/// A Huffman-compressed MOBI 6 book of [html] (UTF-8) with a one-byte multibyte-overlap trailing entry on every text record.
Uint8List buildHuffMobi(String html, {List<String> common = const [], String? recursive}) {
  final enc = HuffEncoder(common, recursive: recursive);
  final text = Uint8List.fromList(utf8.encode(html));
  final recs = <Uint8List>[];
  for (var i = 0; i < text.length; i += 1000) {
    final chunk = Uint8List.sublistView(text, i, i + 1000 > text.length ? text.length : i + 1000);
    recs.add(Uint8List.fromList([...enc.encode(chunk), 0x00])); // trailing entry: (0 & 3) + 1 = this byte only
  }
  final cdic = enc.cdicRecords();
  final huffAt = 1 + recs.length;
  final r0 = record0(
    compression: 17480,
    textLength: text.length,
    textRecords: recs.length,
    version: 6,
    huffRecord: huffAt,
    huffCount: 1 + cdic.length,
    extraFlags: 1,
    cover: false,
  );
  return pdb([r0, ...recs, enc.huffRecord(), ...cdic]);
}

// ------------------------------------------------------------------ KF8

class IndexEntrySpec {
  final String label;
  final List<int> control;
  final List<int> values;
  IndexEntrySpec(this.label, this.control, this.values);
}

/// Main INDX record + one data record (+ a CNCX record with [cncx] when given).
List<Uint8List> indexRecords(List<(int, int, int, int)> tags, int controlBytes, List<IndexEntrySpec> entries, {List<String>? cncx}) {
  const hl = 0xC0;
  final tagx = BytesBuilder()
    ..add(ascii.encode('TAGX'))
    ..add(_u32(12 + 4 * tags.length))
    ..add(_u32(controlBytes));
  for (final (t, n, m, e) in tags) {
    tagx.add([t, n, m, e]);
  }
  final main = Uint8List(hl);
  main.setAll(0, ascii.encode('INDX'));
  ByteData.sublistView(main)
    ..setUint32(4, hl)
    ..setUint32(24, 1)
    ..setUint32(28, 65001)
    ..setUint32(36, entries.length)
    ..setUint32(52, cncx == null ? 0 : 1);
  final mainRec = Uint8List.fromList([...main, ...tagx.toBytes()]);

  final body = BytesBuilder();
  final positions = <int>[];
  for (final e in entries) {
    positions.add(hl + body.length);
    final label = latin1.encode(e.label);
    body
      ..add([label.length])
      ..add(label)
      ..add(e.control);
    for (final v in e.values) {
      body.add(vwi(v));
    }
  }
  final idxtAt = hl + body.length;
  final dataHead = Uint8List(hl)..setAll(0, ascii.encode('INDX'));
  ByteData.sublistView(dataHead)
    ..setUint32(4, hl)
    ..setUint32(20, idxtAt)
    ..setUint32(24, entries.length);
  final idxt = BytesBuilder()..add(ascii.encode('IDXT'));
  for (final p in positions) {
    idxt.add(_u16(p));
  }
  final dataRec = Uint8List.fromList([...dataHead, ...body.toBytes(), ...idxt.toBytes()]);
  final out = [mainRec, dataRec];
  if (cncx != null) {
    final c = BytesBuilder();
    for (final s in cncx) {
      final b = utf8.encode(s);
      c
        ..add(vwi(b.length))
        ..add(b);
    }
    out.add(c.toBytes());
  }
  return out;
}

/// Offset of each string of [strings] inside the CNCX record [indexRecords] writes.
List<int> cncxOffsets(List<String> strings) {
  final out = <int>[];
  var o = 0;
  for (final s in strings) {
    out.add(o);
    final b = utf8.encode(s);
    o += vwi(b.length).length + b.length;
  }
  return out;
}

/// A KF8-only book with two files (the second has two fragments, one of them with an insert position inside a tag when
/// [badInsert]), a CSS flow, an NCX and a PNG image referenced as `kindle:embed:0001`. Returns the file and the expected XHTML.
({Uint8List bytes, String html, List<String> parts}) buildKf8({bool badInsert = false, int compression = 2}) {
  const head = '<html><head><title>T</title><link href="kindle:flow:0001?mime=text/css" rel="stylesheet"/></head><body>';
  const skel0 = '$head<div aid="0"></div></body></html>';
  const skel1 = '$head<div aid="1"></div><div aid="2"></div></body></html>';
  const frag0 = '<h1>第一章 起</h1><p>起的正文。</p><p><img src="kindle:embed:0001?mime=image/png"/></p>';
  const frag1 = '<h1>第二章 承</h1><p>承的正文。</p>';
  const frag2 = '<p>承的第二段。</p>';
  int b(String s) => utf8.encode(s).length;

  final flow0 = '$skel0$frag0$skel1$frag1$frag2';
  const css = 'p{text-indent:2em}';
  final raw = Uint8List.fromList(utf8.encode('$flow0$css'));
  final skelPos1 = b(skel0) + b(frag0);
  final ins0 = b(skel0.substring(0, skel0.indexOf('<div aid="0">') + 13));
  final ins1 = skelPos1 + b(skel1.substring(0, skel1.indexOf('<div aid="1">') + 13));
  var ins2 = skelPos1 + b(skel1.substring(0, skel1.indexOf('<div aid="2">') + 13)) + b(frag1);
  if (badInsert) ins2 -= 3; // inside `<div aid="2">`
  final part0 = skel0.replaceFirst('<div aid="0">', '<div aid="0">$frag0');
  final part1 = skel1.replaceFirst('<div aid="1">', '<div aid="1">$frag1').replaceFirst('<div aid="2">', '<div aid="2">$frag2');

  // text records (PalmDOC literals or stored)
  final recs = <Uint8List>[];
  for (var i = 0; i < raw.length; i += 4096) {
    final c = Uint8List.sublistView(raw, i, i + 4096 > raw.length ? raw.length : i + 4096);
    recs.add(compression == 2 ? palmEncodeLiterals(c) : Uint8List.fromList(c));
  }

  final skelIdx = indexRecords(
    [(1, 1, 0x03, 0), (6, 2, 0x0C, 0), (0, 0, 0, 1)],
    1,
    [
      IndexEntrySpec('SKEL0000000000', [0x05], [1, 0, b(skel0)]),
      IndexEntrySpec('SKEL0000000001', [0x05], [2, skelPos1, b(skel1)]),
    ],
  );
  final selectors = ["P-//*[@aid='0']", "P-//*[@aid='1']", "P-//*[@aid='2']"];
  final selOff = cncxOffsets(selectors);
  final fragIdx = indexRecords(
    [(2, 1, 0x01, 0), (3, 1, 0x02, 0), (4, 1, 0x04, 0), (6, 2, 0x08, 0), (0, 0, 0, 1)],
    1,
    [
      IndexEntrySpec(ins0.toString().padLeft(10, '0'), [0x0F], [selOff[0], 0, 0, 0, b(frag0)]),
      IndexEntrySpec(ins1.toString().padLeft(10, '0'), [0x0F], [selOff[1], 1, 1, 0, b(frag1)]),
      IndexEntrySpec(ins2.toString().padLeft(10, '0'), [0x0F], [selOff[2], 1, 2, 0, b(frag2)]),
    ],
    cncx: selectors,
  );
  final labels = ['第一章 起', '第二章 承'];
  final labOff = cncxOffsets(labels);
  final ncxIdx = indexRecords(
    [(1, 1, 0x01, 0), (2, 1, 0x02, 0), (3, 1, 0x04, 0), (4, 1, 0x08, 0), (6, 2, 0x10, 0), (0, 0, 0, 1)],
    1,
    [
      IndexEntrySpec('0', [0x1F], [ins0, b(frag0), labOff[0], 0, 0, 0]),
      IndexEntrySpec('1', [0x1F], [ins1, b(frag1) + b(frag2), labOff[1], 0, 1, 0]),
    ],
    cncx: labels,
  );
  final fdst = Uint8List.fromList([
    ...ascii.encode('FDST'), ..._u32(12), ..._u32(2), //
    ..._u32(0), ..._u32(b(flow0)), ..._u32(b(flow0)), ..._u32(raw.length),
  ]);

  final image = pngHeader(40, 20);
  final imageAt = 1 + recs.length;
  final skelAt = imageAt + 1;
  final fragAt = skelAt + skelIdx.length;
  final ncxAt = fragAt + fragIdx.length;
  final fdstAt = ncxAt + ncxIdx.length;
  final r0 = record0(
    compression: compression,
    textLength: raw.length,
    textRecords: recs.length,
    version: 8,
    firstImage: imageAt,
    fdst: fdstAt,
    ncx: ncxAt,
    fragment: fragAt,
    skeleton: skelAt,
    title: 'KF8 Title',
    author: 'KF8 Author',
  );
  final bytes = pdb([r0, ...recs, image, ...skelIdx, ...fragIdx, ...ncxIdx, fdst]);
  return (bytes: bytes, html: '$part0$part1', parts: [part0, part1]);
}
