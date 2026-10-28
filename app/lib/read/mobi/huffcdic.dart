// read/mobi/huffcdic.dart — HUFF/CDIC decompression (MOBI compression type 17480, used by many Kindle-store and kindlegen
// files). The original app has no such decoder: its text reader (0x255660) only knows PalmDOC (type 2) and copies every other
// record raw, so these books came out as binary noise there. This port decodes them; the layout of the tables is the public
// MOBI format (the HUFF record carries a 256-entry lookup table plus min/max code tables per code length, the CDIC records
// the phrase dictionary; a phrase whose flag bit is clear is itself Huffman coded and is expanded on first use).
import 'dart:typed_data';

import 'mobi_file.dart' show MobiException;

class HuffCdicReader {
  /// `(codeLength, terminal, maxCode)` per value of the top byte of the 32-bit code window.
  final List<(int, bool, int)> _dict1;
  final List<int> _minCode; // index = code length 0..32
  final List<int> _maxCode;
  final List<Uint8List?> _phrases = [];
  final List<bool> _literal = [];

  HuffCdicReader._(this._dict1, this._minCode, this._maxCode);

  static int _u32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  /// [huff] is the HUFF record, [cdics] the CDIC records that follow it (`huffman record offset` / `count` of the MOBI header).
  factory HuffCdicReader(Uint8List huff, List<Uint8List> cdics) {
    if (huff.length < 24 || String.fromCharCodes(huff.sublist(0, 4)) != 'HUFF') {
      throw const MobiException('MOBI文件损坏：HUFF 记录无效');
    }
    final off1 = _u32(huff, 8);
    final off2 = _u32(huff, 12);
    if (off1 + 256 * 4 > huff.length || off2 + 64 * 4 > huff.length) throw const MobiException('MOBI文件损坏：HUFF 表越界');
    final dict1 = <(int, bool, int)>[];
    for (var i = 0; i < 256; i++) {
      final v = _u32(huff, off1 + 4 * i);
      final len = v & 0x1F;
      final term = v & 0x80 != 0;
      final max = (((v >> 8) + 1) << (32 - len)) - 1;
      dict1.add((len, term, max));
    }
    final minCode = <int>[0];
    final maxCode = <int>[0];
    for (var len = 1; len <= 32; len++) {
      final mn = _u32(huff, off2 + 8 * (len - 1));
      final mx = _u32(huff, off2 + 8 * (len - 1) + 4);
      minCode.add(mn << (32 - len));
      maxCode.add(((mx + 1) << (32 - len)) - 1);
    }
    final r = HuffCdicReader._(dict1, minCode, maxCode);
    for (final c in cdics) {
      r._loadCdic(c);
    }
    return r;
  }

  void _loadCdic(Uint8List cdic) {
    if (cdic.length < 16 || String.fromCharCodes(cdic.sublist(0, 4)) != 'CDIC') {
      throw const MobiException('MOBI文件损坏：CDIC 记录无效');
    }
    final headerLen = _u32(cdic, 4);
    final phrases = _u32(cdic, 8);
    final bits = _u32(cdic, 12);
    final n = (1 << bits) < phrases - _phrases.length ? (1 << bits) : phrases - _phrases.length;
    for (var i = 0; i < n; i++) {
      final at = headerLen + 2 * i;
      if (at + 2 > cdic.length) break;
      final off = headerLen + _u16(cdic, at);
      if (off + 2 > cdic.length) {
        _phrases.add(Uint8List(0));
        _literal.add(true);
        continue;
      }
      final blen = _u16(cdic, off);
      final len = blen & 0x7FFF;
      final end = off + 2 + len > cdic.length ? cdic.length : off + 2 + len;
      _phrases.add(Uint8List.sublistView(cdic, off + 2, end));
      _literal.add(blen & 0x8000 != 0);
    }
  }

  int get phraseCount => _phrases.length;

  /// Decodes one text record (trailing entries already removed).
  Uint8List unpack(Uint8List data, [int depth = 0]) {
    if (depth > 32) throw const MobiException('MOBI文件损坏：Huffman 词典循环引用');
    final out = BytesBuilder(copy: false);
    final padded = Uint8List(data.length + 8)..setAll(0, data);
    var bitsLeft = data.length * 8;
    var pos = 0;
    var x = _u64(padded, 0);
    var n = 32;
    while (true) {
      if (n <= 0) {
        pos += 4;
        x = _u64(padded, pos);
        n += 32;
      }
      final code = (x >>> n) & 0xFFFFFFFF;
      var (len, term, max) = _dict1[code >>> 24];
      if (len == 0) throw const MobiException('MOBI文件损坏：Huffman 编码无效');
      if (!term) {
        while (len < 32 && code < _minCode[len]) {
          len++;
        }
        max = _maxCode[len];
      }
      n -= len;
      bitsLeft -= len;
      if (bitsLeft < 0) break;
      final r = (max - code) >>> (32 - len);
      if (r < 0 || r >= _phrases.length) throw const MobiException('MOBI文件损坏：Huffman 词典索引越界');
      var phrase = _phrases[r];
      if (phrase == null) throw const MobiException('MOBI文件损坏：Huffman 词典循环引用');
      if (!_literal[r]) {
        _phrases[r] = null; // guards against self references while it expands
        phrase = unpack(phrase, depth + 1);
        _phrases[r] = phrase;
        _literal[r] = true;
      }
      out.add(phrase);
    }
    return out.toBytes();
  }

  static int _u64(Uint8List b, int o) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | b[o + i];
    }
    return v;
  }
}
