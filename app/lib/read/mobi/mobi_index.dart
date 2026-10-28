// read/mobi/mobi_index.dart — reader for the INDX tables of KF8 (AZW3) books: skeleton, fragment and NCX indexes.
// Not in the original app (its MOBI code reads MOBI 6 text records only, 0x255660); format as published for the MOBI/KF8
// container: a main INDX record (header + TAGX tag table) followed by `count` INDX data records whose IDXT lists the entries,
// then `ncncx` CNCX records with the strings the entries point to.
import 'dart:convert';
import 'dart:typed_data';

import 'mobi_file.dart' show MobiException;

class MobiIndexEntry {
  /// The entry's label (skeleton name, fragment insert position as a decimal string, NCX number ...).
  final String label;

  /// Tag number -> values.
  final Map<int, List<int>> tags;

  const MobiIndexEntry(this.label, this.tags);

  int tag(int t, [int i = 0, int fallback = -1]) {
    final v = tags[t];
    return v == null || v.length <= i ? fallback : v[i];
  }
}

class MobiIndex {
  final List<MobiIndexEntry> entries;

  /// CNCX strings by offset (offsets of the 2nd CNCX record start at 0x10000 and so on).
  final Map<int, String> cncx;

  const MobiIndex(this.entries, this.cncx);

  static int _u32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  /// Forward variable-width integer (7 bits per byte, the last byte has the high bit set): `(value, consumed)`.
  static (int, int) vwi(Uint8List b, int o) {
    var v = 0;
    var n = 0;
    while (o + n < b.length) {
      final c = b[o + n];
      n++;
      v = (v << 7) | (c & 0x7F);
      if (c & 0x80 != 0) break;
    }
    return (v, n);
  }

  /// Reads the index whose main record is `record(idx)`; [record] returns the bytes of a PDB record (null when missing).
  static MobiIndex read(Uint8List? Function(int) record, int idx) {
    final main = record(idx);
    if (main == null || main.length < 0x38 || String.fromCharCodes(main.sublist(0, 4)) != 'INDX') {
      throw const MobiException('MOBI文件损坏：索引记录无效');
    }
    final headerLen = _u32(main, 4);
    final count = _u32(main, 24);
    final ncncx = _u32(main, 52);

    final cncx = <int, String>{};
    for (var j = 0; j < ncncx; j++) {
      final c = record(idx + count + 1 + j);
      if (c == null) break;
      var o = 0;
      while (o < c.length && c[o] != 0) {
        final start = o;
        final (len, used) = vwi(c, o);
        o += used;
        final end = o + len > c.length ? c.length : o + len;
        cncx[j * 0x10000 + start] = utf8.decode(c.sublist(o, end), allowMalformed: true);
        o = end;
      }
    }

    // TAGX: (tag, values per entry, mask, end flag)
    var controlBytes = 0;
    final tagTable = <(int, int, int, int)>[];
    if (headerLen + 12 <= main.length && String.fromCharCodes(main.sublist(headerLen, headerLen + 4)) == 'TAGX') {
      final firstEntry = _u32(main, headerLen + 4);
      controlBytes = _u32(main, headerLen + 8);
      for (var i = 12; i + 4 <= firstEntry && headerLen + i + 4 <= main.length; i += 4) {
        final p = headerLen + i;
        tagTable.add((main[p], main[p + 1], main[p + 2], main[p + 3]));
      }
    }

    final entries = <MobiIndexEntry>[];
    for (var i = idx + 1; i <= idx + count; i++) {
      final d = record(i);
      if (d == null || d.length < 28 || String.fromCharCodes(d.sublist(0, 4)) != 'INDX') continue;
      final idxt = _u32(d, 20);
      final n = _u32(d, 24);
      final positions = <int>[];
      for (var j = 0; j < n; j++) {
        if (idxt + 4 + 2 * j + 2 > d.length) break;
        positions.add(_u16(d, idxt + 4 + 2 * j));
      }
      positions.add(idxt);
      for (var j = 0; j + 1 < positions.length; j++) {
        final start = positions[j];
        final end = positions[j + 1];
        if (start >= d.length || end > d.length || end <= start) continue;
        final textLen = d[start];
        final textEnd = start + 1 + textLen > end ? end : start + 1 + textLen;
        final label = latin1.decode(d.sublist(start + 1, textEnd));
        entries.add(MobiIndexEntry(label, _tagMap(d, controlBytes, tagTable, textEnd, end)));
      }
    }
    return MobiIndex(entries, cncx);
  }

  static int _bits(int v) {
    var n = 0;
    while (v != 0) {
      n += v & 1;
      v >>= 1;
    }
    return n;
  }

  static Map<int, List<int>> _tagMap(Uint8List d, int controlBytes, List<(int, int, int, int)> table, int start, int end) {
    final pending = <(int, int?, int?, int)>[]; // tag, value count, value bytes, values per entry
    var cbIndex = 0;
    var data = start + controlBytes;
    for (final (tag, perEntry, mask0, endFlag) in table) {
      if (endFlag == 1) {
        cbIndex++;
        continue;
      }
      if (start + cbIndex >= end) break;
      var mask = mask0;
      var value = d[start + cbIndex] & mask;
      if (value == 0) continue;
      if (value == mask) {
        if (_bits(mask) > 1) {
          final (bytes, used) = vwi(d, data);
          data += used;
          pending.add((tag, null, bytes, perEntry));
        } else {
          pending.add((tag, 1, null, perEntry));
        }
      } else {
        while (mask & 1 == 0) {
          mask >>= 1;
          value >>= 1;
        }
        pending.add((tag, value, null, perEntry));
      }
    }
    final out = <int, List<int>>{};
    for (final (tag, count, bytes, perEntry) in pending) {
      final values = <int>[];
      if (count != null) {
        for (var k = 0; k < count * perEntry && data < end; k++) {
          final (v, used) = vwi(d, data);
          data += used;
          values.add(v);
        }
      } else {
        var consumed = 0;
        while (consumed < bytes! && data < end) {
          final (v, used) = vwi(d, data);
          data += used;
          consumed += used;
          values.add(v);
        }
      }
      out[tag] = values;
    }
    return out;
  }
}
