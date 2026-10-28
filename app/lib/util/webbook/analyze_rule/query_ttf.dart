// util/webbook/analyze_rule/query_ttf.dart - font de-obfuscation for rule JavaScript (`java.queryTTF`, `java.replaceFont`).
//
// The original has the class (`QueryTTF extends JsBindable`, no methods survive) and answers `not supported queryTTF/replaceFont`
// (0xd925e8 / 0xd925c0). The replica ports upstream Legado's semantics: parse a TrueType font (plain sfnt or WOFF 1.0), map every
// code point to its glyph outline, and let `replaceFont(text, errorFont, correctFont)` swap each obfuscated character for the
// character whose outline is the same in the standard font. Outlines are compared on the decoded contours (end points, on-curve
// flags, absolute coordinates), so two encodings of the same outline match. Code points 0x100..0x33FF are skipped like Legado does
// (radicals / compatibility forms would otherwise shadow the ideographs that share their outline).
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import '../../legado/js_bindable.dart';
import '../../legado/js_bindable_compat.dart';

class QueryTTF extends JsBindable {
  /// code point -> glyph id (cmap)
  final Map<int, int> unicodeToGlyphId = {};

  /// code point -> outline key (null outline = empty glyph)
  final Map<int, String?> _codeToGlyph = {};

  /// outline key -> smallest code point with that outline
  final Map<String, int> _glyphToCode = {};

  final List<String?> _glyphKeys = [];

  QueryTTF(List<int> font) {
    _parse(_unwrap(Uint8List.fromList(font)));
  }

  // ---- public API (Legado names) ------------------------------------------------------------------------------------------------

  /// Outline of [unicode]; null when the font has no outline for it.
  String? getGlyfByUnicode(int unicode) => _codeToGlyph[unicode];

  int getGlyfIdByUnicode(int unicode) => unicodeToGlyphId[unicode] ?? 0;

  /// Code point whose outline is [glyph]; 0 when unknown.
  int getUnicodeByGlyf(String? glyph) => glyph == null ? 0 : (_glyphToCode[glyph] ?? 0);

  bool isBlankUnicode(int unicode) => const {
        0x09, 0x0A, 0x0D, 0x20, 0xA0, 0x2002, 0x2003, 0x2007, 0x200A, 0x200B, 0x200C, 0x200D, 0x202F, 0x205F, 0x3000,
      }.contains(unicode);

  int get glyphCount => _glyphKeys.length;

  /// `java.replaceFont(text, errorQueryTTF, correctQueryTTF, filter)`: every character of [text] is looked up by outline in
  /// [errorFont] and replaced by the character with that outline in [correctFont]; with [filter], characters without an outline in
  /// [errorFont] are dropped.
  static String replaceFont(String text, QueryTTF? errorFont, QueryTTF? correctFont, {bool filter = false}) {
    if (errorFont == null || correctFont == null) return text;
    final sb = StringBuffer();
    for (final code in text.runes) {
      if (errorFont.isBlankUnicode(code)) {
        sb.writeCharCode(code);
        continue;
      }
      var glyf = errorFont.getGlyfByUnicode(code);
      if (errorFont.getGlyfIdByUnicode(code) == 0) glyf = null;
      if (filter && glyf == null) continue;
      final repl = correctFont.getUnicodeByGlyf(glyf);
      sb.writeCharCode(repl != 0 ? repl : code);
    }
    return sb.toString();
  }

  @override
  Iterable<String> get jsMethods => const ['getGlyfByUnicode', 'getGlyfIdByUnicode', 'getUnicodeByGlyf', 'isBlankUnicode'];

  @override
  Object? jsCall(String name, List<Object?> args) {
    int n(int i) => i < args.length && args[i] is num ? (args[i] as num).toInt() : int.tryParse(jsToString(i < args.length ? args[i] : '')) ?? 0;
    switch (name) {
      case 'getGlyfByUnicode':
        return getGlyfByUnicode(n(0));
      case 'getGlyfIdByUnicode':
        return getGlyfIdByUnicode(n(0));
      case 'getUnicodeByGlyf':
        return getUnicodeByGlyf(args.isEmpty || args[0] == null ? null : jsToString(args[0]));
      case 'isBlankUnicode':
        return isBlankUnicode(n(0));
    }
    return super.jsCall(name, args);
  }

  @override
  String toString() => 'QueryTTF($glyphCount glyphs, ${unicodeToGlyphId.length} code points)';

  // ---- parsing ------------------------------------------------------------------------------------------------------------------

  /// WOFF 1.0 -> sfnt bytes; sfnt is returned unchanged.
  static Uint8List _unwrap(Uint8List b) {
    if (b.length < 12) throw const FormatException('not a font');
    final bd = ByteData.sublistView(b);
    final sig = bd.getUint32(0);
    if (sig == 0x774F4632) throw const FormatException('WOFF2 fonts are not supported');
    if (sig != 0x774F4646) return b; // 'wOFF'
    final numTables = bd.getUint16(12);
    final flavor = bd.getUint32(4);
    final tables = <(int, Uint8List)>[];
    for (var i = 0; i < numTables; i++) {
      final e = 44 + i * 20;
      final tag = bd.getUint32(e);
      final off = bd.getUint32(e + 4);
      final compLen = bd.getUint32(e + 8);
      final origLen = bd.getUint32(e + 12);
      var data = Uint8List.sublistView(b, off, off + compLen);
      if (compLen < origLen) data = Uint8List.fromList(ZLibDecoder().convert(data));
      tables.add((tag, data));
    }
    // rebuild a minimal sfnt (directory + 4-byte aligned tables)
    final headerLen = 12 + 16 * numTables;
    var total = headerLen;
    for (final t in tables) {
      total += (t.$2.length + 3) & ~3;
    }
    final out = Uint8List(total);
    final od = ByteData.sublistView(out);
    od.setUint32(0, flavor);
    od.setUint16(4, numTables);
    var pos = headerLen;
    for (var i = 0; i < tables.length; i++) {
      final (tag, data) = tables[i];
      final r = 12 + i * 16;
      od.setUint32(r, tag);
      od.setUint32(r + 8, pos);
      od.setUint32(r + 12, data.length);
      out.setRange(pos, pos + data.length, data);
      pos += (data.length + 3) & ~3;
    }
    return out;
  }

  void _parse(Uint8List b) {
    final bd = ByteData.sublistView(b);
    final numTables = bd.getUint16(4);
    final dir = <String, (int, int)>{};
    for (var i = 0; i < numTables; i++) {
      final r = 12 + i * 16;
      final tag = String.fromCharCodes(b.sublist(r, r + 4));
      dir[tag] = (bd.getUint32(r + 8), bd.getUint32(r + 12));
    }
    final head = dir['head'], maxp = dir['maxp'], loca = dir['loca'], glyf = dir['glyf'], cmap = dir['cmap'];
    if (head == null || maxp == null || cmap == null) throw const FormatException('font without head/maxp/cmap');
    final longLoca = bd.getInt16(head.$1 + 50) == 1;
    final numGlyphs = bd.getUint16(maxp.$1 + 4);
    final offsets = <int>[];
    if (loca != null && glyf != null) {
      for (var i = 0; i <= numGlyphs; i++) {
        final p = loca.$1 + (longLoca ? i * 4 : i * 2);
        if (p + (longLoca ? 4 : 2) > loca.$1 + loca.$2) break;
        offsets.add(longLoca ? bd.getUint32(p) : bd.getUint16(p) * 2);
      }
    }
    // outlines
    final raw = <int, _Outline?>{};
    _Outline? outline(int gid, int depth) {
      if (raw.containsKey(gid)) return raw[gid];
      if (glyf == null || gid + 1 >= offsets.length || depth > 8) return null;
      final start = glyf.$1 + offsets[gid], end = glyf.$1 + offsets[gid + 1];
      _Outline? o;
      if (end > start && end <= b.length) {
        try {
          o = _readGlyph(bd, start, end, (g) => outline(g, depth + 1));
        } catch (_) {
          o = null;
        }
      }
      raw[gid] = o;
      return o;
    }

    for (var g = 0; g < numGlyphs; g++) {
      _glyphKeys.add(outline(g, 0)?.key);
    }
    _readCmap(bd, cmap.$1);
    final codes = unicodeToGlyphId.keys.toList()..sort();
    for (final code in codes) {
      if (code >= 0x100 && code < 0x3400) continue;
      final gid = unicodeToGlyphId[code]!;
      if (gid == 0) continue;
      final key = gid < _glyphKeys.length ? _glyphKeys[gid] : null;
      _codeToGlyph[code] = key;
      if (key != null) _glyphToCode.putIfAbsent(key, () => code);
    }
  }

  static _Outline _readGlyph(ByteData bd, int start, int end, _Outline? Function(int gid) component) {
    final contours = bd.getInt16(start);
    var p = start + 10;
    if (contours >= 0) {
      final endPts = <int>[for (var i = 0; i < contours; i++) bd.getUint16(p + i * 2)];
      p += contours * 2;
      final instrLen = bd.getUint16(p);
      p += 2 + instrLen;
      final nPts = endPts.isEmpty ? 0 : endPts.last + 1;
      final flags = <int>[];
      while (flags.length < nPts) {
        final f = bd.getUint8(p++);
        flags.add(f);
        if (f & 8 != 0) {
          final rep = bd.getUint8(p++);
          for (var r = 0; r < rep; r++) {
            flags.add(f);
          }
        }
      }
      final xs = <int>[], ys = <int>[];
      var v = 0;
      for (var i = 0; i < nPts; i++) {
        final f = flags[i];
        if (f & 2 != 0) {
          final d = bd.getUint8(p++);
          v += (f & 16 != 0) ? d : -d;
        } else if (f & 16 == 0) {
          v += bd.getInt16(p);
          p += 2;
        }
        xs.add(v);
      }
      v = 0;
      for (var i = 0; i < nPts; i++) {
        final f = flags[i];
        if (f & 4 != 0) {
          final d = bd.getUint8(p++);
          v += (f & 32 != 0) ? d : -d;
        } else if (f & 32 == 0) {
          v += bd.getInt16(p);
          p += 2;
        }
        ys.add(v);
      }
      final sb = StringBuffer('S');
      sb.write(endPts.join(','));
      sb.write('|');
      for (var i = 0; i < nPts; i++) {
        sb.write(flags[i] & 1);
        sb.write(xs[i]);
        sb.write(',');
        sb.write(ys[i]);
        sb.write(';');
      }
      return _Outline(sb.toString());
    }
    // composite glyph: the components' outlines with their placement
    final sb = StringBuffer('C');
    var more = true;
    while (more && p + 4 <= end) {
      final flags = bd.getUint16(p);
      final gid = bd.getUint16(p + 2);
      p += 4;
      int a1, a2;
      if (flags & 1 != 0) {
        a1 = (flags & 2 != 0) ? bd.getInt16(p) : bd.getUint16(p);
        a2 = (flags & 2 != 0) ? bd.getInt16(p + 2) : bd.getUint16(p + 2);
        p += 4;
      } else {
        a1 = (flags & 2 != 0) ? bd.getInt8(p) : bd.getUint8(p);
        a2 = (flags & 2 != 0) ? bd.getInt8(p + 1) : bd.getUint8(p + 1);
        p += 2;
      }
      final t = <int>[];
      if (flags & 8 != 0) {
        t.add(bd.getInt16(p));
        p += 2;
      } else if (flags & 0x40 != 0) {
        t
          ..add(bd.getInt16(p))
          ..add(bd.getInt16(p + 2));
        p += 4;
      } else if (flags & 0x80 != 0) {
        for (var i = 0; i < 4; i++) {
          t.add(bd.getInt16(p + i * 2));
        }
        p += 8;
      }
      sb
        ..write('[')
        ..write(component(gid)?.key ?? '-')
        ..write('@$a1,$a2,${flags & 2},${t.join(',')}]');
      more = flags & 0x20 != 0;
    }
    return _Outline(sb.toString());
  }

  void _readCmap(ByteData bd, int cmapOff) {
    final n = bd.getUint16(cmapOff + 2);
    final subtables = <(int, int, int)>[];
    for (var i = 0; i < n; i++) {
      final r = cmapOff + 4 + i * 8;
      subtables.add((bd.getUint16(r), bd.getUint16(r + 2), cmapOff + bd.getUint32(r + 4)));
    }
    // Unicode subtables first (platform 0, platform 3 encodings 1 and 10), then everything else as a fallback
    int rank((int, int, int) s) => s.$1 == 0 || (s.$1 == 3 && (s.$2 == 1 || s.$2 == 10)) ? 0 : 1;
    subtables.sort((a, b) => rank(a).compareTo(rank(b)));
    final seen = <int>{};
    for (final (platform, _, off) in subtables) {
      if (!seen.add(off)) continue;
      final unicode = platform == 0 || platform == 3;
      final m = <int, int>{};
      try {
        _readSubtable(bd, off, m);
      } catch (_) {
        continue;
      }
      if (!unicode && unicodeToGlyphId.isNotEmpty) continue;
      m.forEach((k, v) => unicodeToGlyphId.putIfAbsent(k, () => v));
    }
  }

  static void _readSubtable(ByteData bd, int off, Map<int, int> out) {
    final format = bd.getUint16(off);
    switch (format) {
      case 0:
        for (var c = 0; c < 256; c++) {
          final g = bd.getUint8(off + 6 + c);
          if (g != 0) out[c] = g;
        }
        break;
      case 4:
        final segX2 = bd.getUint16(off + 6);
        final segs = segX2 ~/ 2;
        final endOff = off + 14, startOff = endOff + segX2 + 2, deltaOff = startOff + segX2, rangeOff = deltaOff + segX2;
        for (var s = 0; s < segs; s++) {
          final endC = bd.getUint16(endOff + s * 2);
          final startC = bd.getUint16(startOff + s * 2);
          final delta = bd.getInt16(deltaOff + s * 2);
          final ro = bd.getUint16(rangeOff + s * 2);
          if (startC == 0xFFFF) continue;
          for (var c = startC; c <= endC; c++) {
            int g;
            if (ro == 0) {
              g = (c + delta) & 0xFFFF;
            } else {
              final gp = rangeOff + s * 2 + ro + (c - startC) * 2;
              g = bd.getUint16(gp);
              if (g != 0) g = (g + delta) & 0xFFFF;
            }
            if (g != 0) out[c] = g;
          }
        }
        break;
      case 6:
        final first = bd.getUint16(off + 6);
        final count = bd.getUint16(off + 8);
        for (var i = 0; i < count; i++) {
          final g = bd.getUint16(off + 10 + i * 2);
          if (g != 0) out[first + i] = g;
        }
        break;
      case 12:
        final groups = bd.getUint32(off + 12);
        for (var i = 0; i < groups; i++) {
          final r = off + 16 + i * 12;
          final s = bd.getUint32(r), e = bd.getUint32(r + 4), g0 = bd.getUint32(r + 8);
          if (e - s > 0x30000) continue;
          for (var c = s; c <= e; c++) {
            final g = g0 + (c - s);
            if (g != 0) out[c] = g;
          }
        }
        break;
    }
  }
}

class _Outline {
  final String key;
  const _Outline(this.key);
}
