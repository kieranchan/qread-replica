// util/legado/cjk_charsets.dart - Big5 and full GB18030 (four-byte sequences included) for page decoding and URL encoding.
//
// The original decodes `gbk` / `gb2312` / `gb18030` with one GBK table (`gbkcodec`, charset switch at 0xe59850) and has no Big5;
// the replica keeps GBK for the two-byte part (fast_gbk = ICU gbkuni30, the GB18030 two-byte mapping) and adds the four-byte
// ranges plus a cp950 Big5 table, both generated from Python's codecs (`tools/scripts/gen_charset_tables.py`).
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

import 'cjk_charset_tables.dart';

abstract class CjkCharsets {
  static const int _replacement = 0xFFFD;

  // ---- GB18030 ------------------------------------------------------------------------------------------------------------------

  static bool _isFourByteAt(List<int> b, int i) =>
      i + 3 < b.length &&
      b[i] >= 0x81 &&
      b[i] <= 0xFE &&
      b[i + 1] >= 0x30 &&
      b[i + 1] <= 0x39 &&
      b[i + 2] >= 0x81 &&
      b[i + 2] <= 0xFE &&
      b[i + 3] >= 0x30 &&
      b[i + 3] <= 0x39;

  /// Code point of the four-byte sequence starting at [i]; U+FFFD when it maps to nothing.
  static int _fourByte(List<int> b, int i) {
    final b1 = b[i], b2 = b[i + 1], b3 = b[i + 2], b4 = b[i + 3];
    if (b1 >= 0x90 && b1 <= 0xE3) {
      final cp = 0x10000 + (b1 - 0x90) * 12600 + (b2 - 0x30) * 1260 + (b3 - 0x81) * 10 + (b4 - 0x30);
      return cp <= 0x10FFFF ? cp : _replacement;
    }
    if (b1 > 0x84) return _replacement;
    final lin = (b1 - 0x81) * 12600 + (b2 - 0x30) * 1260 + (b3 - 0x81) * 10 + (b4 - 0x30);
    if (lin >= 39420) return _replacement;
    // last range start <= lin
    var lo = 0, hi = gb18030RangeStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (gb18030RangeStarts[mid] <= lin) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return gb18030RangeCodePoints[lo] + (lin - gb18030RangeStarts[lo]);
  }

  /// GB18030 decoding: runs of one/two-byte characters go through the GBK table, four-byte sequences through the range table.
  static String decodeGb18030(List<int> bytes) {
    final out = StringBuffer();
    var start = 0;
    var i = 0;
    final n = bytes.length;
    while (i < n) {
      final b = bytes[i];
      if (b < 0x80) {
        i++;
        continue;
      }
      if (b >= 0x81 && b <= 0xFE && i + 1 < n) {
        if (_isFourByteAt(bytes, i)) {
          if (i > start) out.write(gbk.decode(bytes.sublist(start, i), allowMalformed: true));
          out.writeCharCode(_fourByte(bytes, i));
          i += 4;
          start = i;
          continue;
        }
        i += 2;
        continue;
      }
      i++;
    }
    if (start < n) out.write(gbk.decode(start == 0 ? bytes : bytes.sublist(start), allowMalformed: true));
    return out.toString();
  }

  static Map<int, int>? _gbkKnown;

  /// GB18030 encoding: GBK pairs where the table has the character, four-byte sequences for everything else.
  static Uint8List encodeGb18030(String s) {
    final out = BytesBuilder(copy: false);
    for (final r in s.runes) {
      if (r < 0x80) {
        out.addByte(r);
        continue;
      }
      final pair = _gbkPair(r);
      if (pair != null) {
        out.addByte(pair >> 8);
        out.addByte(pair & 0xff);
        continue;
      }
      out.add(_toFourByte(r));
    }
    return out.takeBytes();
  }

  static int? _gbkPair(int r) {
    if (r > 0xFFFF) return null;
    final cache = _gbkKnown ??= <int, int>{};
    final hit = cache[r];
    if (hit != null) return hit < 0 ? null : hit;
    final e = gbk.encode(String.fromCharCode(r));
    // fast_gbk answers 0xA7F6 (U+E7B3) for characters it does not know
    final known = e.length == 2 && !(e[0] == 0xA7 && e[1] == 0xF6 && r != 0xE7B3);
    final v = known ? (e[0] << 8) | e[1] : -1;
    cache[r] = v;
    return known ? v : null;
  }

  static List<int> _toFourByte(int cp) {
    int lin;
    if (cp >= 0x10000) {
      lin = cp - 0x10000;
      return [0x90 + lin ~/ 12600, 0x30 + (lin % 12600) ~/ 1260, 0x81 + (lin % 1260) ~/ 10, 0x30 + lin % 10];
    }
    var lo = 0, hi = gb18030RangeCodePoints.length - 1, found = -1;
    // ranges are ordered by code point too
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (gb18030RangeCodePoints[mid] <= cp) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return const [0x3F];
    final endLin = found + 1 < gb18030RangeStarts.length ? gb18030RangeStarts[found + 1] : 39420;
    lin = gb18030RangeStarts[found] + (cp - gb18030RangeCodePoints[found]);
    if (lin >= endLin) return const [0x3F];
    return [0x81 + lin ~/ 12600, 0x30 + (lin % 12600) ~/ 1260, 0x81 + (lin % 1260) ~/ 10, 0x30 + lin % 10];
  }

  // ---- Big5 ---------------------------------------------------------------------------------------------------------------------

  static int _trailIndex(int t) {
    if (t >= 0x40 && t <= 0x7E) return t - 0x40;
    if (t >= 0xA1 && t <= 0xFE) return t - 0xA1 + 63;
    return -1;
  }

  /// Big5 (cp950) decoding; invalid pairs become U+FFFD (the trail byte is kept when it is ASCII, as browsers do).
  static String decodeBig5(List<int> bytes) {
    final out = StringBuffer();
    final n = bytes.length;
    var i = 0;
    while (i < n) {
      final b = bytes[i];
      if (b < 0x80) {
        out.writeCharCode(b);
        i++;
        continue;
      }
      if (b >= 0xA1 && b <= 0xF9 && i + 1 < n) {
        final t = _trailIndex(bytes[i + 1]);
        if (t >= 0) {
          out.writeCharCode(big5Rows[b - 0xA1].codeUnitAt(t));
          i += 2;
          continue;
        }
      }
      out.writeCharCode(_replacement);
      i++;
      if (b >= 0x81 && b <= 0xFE && i < n && bytes[i] >= 0x80) i++;
    }
    return out.toString();
  }

  static Map<int, int>? _big5Reverse;

  static Uint8List encodeBig5(String s) {
    final rev = _big5Reverse ??= () {
      final m = <int, int>{};
      for (var lead = 0; lead < big5Rows.length; lead++) {
        final row = big5Rows[lead];
        for (var t = 0; t < row.length; t++) {
          final cu = row.codeUnitAt(t);
          if (cu == _replacement) continue;
          final trail = t < 63 ? 0x40 + t : 0xA1 + t - 63;
          m.putIfAbsent(cu, () => ((0xA1 + lead) << 8) | trail);
        }
      }
      return m;
    }();
    final out = BytesBuilder(copy: false);
    for (final r in s.runes) {
      if (r < 0x80) {
        out.addByte(r);
        continue;
      }
      final v = rev[r];
      if (v == null) {
        out.addByte(0x3F);
      } else {
        out.addByte(v >> 8);
        out.addByte(v & 0xff);
      }
    }
    return out.takeBytes();
  }
}
