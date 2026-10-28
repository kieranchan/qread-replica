// read/mobi/kf8.dart — KF8 (AZW3) text: puts the book's XHTML back together from the skeleton and fragment indexes and reads the
// NCX index for the table of contents.
//
// The original app does not do this: its MOBI reader (0xedb06c -> 0x255660) concatenates the text records as they are, which for a
// KF8-only book gives the skeleton files followed by their fragments in storage order. This port rebuilds the files the way the
// format stores them: flow 0 of the FDST table holds, per file, a skeleton (`<html>...<body>` with insert points) followed by its
// fragments; every fragment entry names its absolute insert position. After assembly each part occupies the same range of
// "assembled" positions as its stored skeleton + fragments, which is the coordinate space of the NCX positions.
import 'dart:typed_data';

import 'mobi_index.dart';

class Kf8Text {
  /// Flow 0 with every skeleton file assembled, files back to back.
  final Uint8List html;

  /// Table of contents: `(byte offset in [html], title, depth)` in NCX order.
  final List<(int, String, int)> toc;

  const Kf8Text(this.html, this.toc);
}

abstract class Kf8 {
  static const int nullIndex = 0xFFFFFFFF;

  static int _u32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// Flow 0 of the FDST table, or all of [raw] when there is no FDST record.
  static Uint8List flow0(Uint8List raw, Uint8List? fdst) {
    if (fdst == null || fdst.length < 12 || String.fromCharCodes(fdst.sublist(0, 4)) != 'FDST') return raw;
    final secStart = _u32(fdst, 4);
    final n = _u32(fdst, 8);
    if (n < 1 || secStart + 8 > fdst.length) return raw;
    final s = _u32(fdst, secStart);
    var e = _u32(fdst, secStart + 4);
    if (e > raw.length) e = raw.length;
    if (s >= e) return raw;
    return Uint8List.sublistView(raw, s, e);
  }

  static int _indexOf(List<int> b, int c, [int from = 0]) {
    for (var i = from; i < b.length; i++) {
      if (b[i] == c) return i;
    }
    return -1;
  }

  static int _lastIndexOf(List<int> b, int c) {
    for (var i = b.length - 1; i >= 0; i--) {
      if (b[i] == c) return i;
    }
    return -1;
  }

  /// End of the start tag that carries `aid="<aid>"` (index of its `>`), or -1.
  static int _aidTagEnd(List<int> skeleton, String aid) {
    final s = String.fromCharCodes(skeleton);
    final m = RegExp('<[^>]*\\said=[\'"]${RegExp.escape(aid)}[\'"][^>]*>').firstMatch(s);
    return m == null ? -1 : m.end - 1;
  }

  /// Assembles flow 0. [record] returns a PDB record by number (KF8 record numbers are absolute in a KF8-only file).
  static Kf8Text assemble({
    required Uint8List raw,
    required Uint8List? Function(int) record,
    int fdst = nullIndex,
    int skeleton = nullIndex,
    int fragment = nullIndex,
    int ncx = nullIndex,
  }) {
    final text = flow0(raw, fdst == nullIndex ? null : record(fdst));
    if (skeleton == nullIndex || fragment == nullIndex) {
      return Kf8Text(text, _toc(record, ncx, const [], const []));
    }
    final skel = MobiIndex.read(record, skeleton);
    final frag = MobiIndex.read(record, fragment);
    final out = BytesBuilder(copy: false);
    final parts = <(int, int, int)>[]; // assembled start, assembled end, output start
    var fi = 0;
    for (final s in skel.entries) {
      final count = s.tag(1, 0, 0);
      final skelPos = s.tag(6, 0, 0);
      final skelLen = s.tag(6, 1, 0);
      if (skelPos < 0 || skelPos + skelLen > text.length) continue;
      var base = skelPos + skelLen;
      final built = List<int>.of(Uint8List.sublistView(text, skelPos, base), growable: true);
      for (var k = 0; k < count && fi < frag.entries.length; k++, fi++) {
        final f = frag.entries[fi];
        final length = f.tag(6, 1, 0);
        final startPos = f.tag(6, 0, 0);
        final partEnd = base + length > text.length ? text.length : base + length;
        final part = Uint8List.sublistView(text, base < partEnd ? base : partEnd, partEnd);
        var insert = (int.tryParse(f.label) ?? skelPos) - skelPos;
        if (insert < 0 || insert > built.length) insert = built.length;
        final head = built.sublist(0, insert);
        final tail = built.sublist(insert);
        final tailGt = _indexOf(tail, 0x3E);
        final tailLt = _indexOf(tail, 0x3C);
        if ((tailGt >= 0 && (tailLt < 0 || tailGt < tailLt)) || _lastIndexOf(head, 0x3E) < _lastIndexOf(head, 0x3C)) {
          // the insert point falls inside a tag (badly formed file): put the fragment after the tag that carries its aid
          final selector = frag.cncx[f.tag(2, 0, -1)] ?? '';
          final aid = RegExp(r"aid='([^']*)'").firstMatch(selector)?.group(1);
          if (aid != null) {
            final ep = _aidTagEnd(built, aid);
            if (ep >= 0) insert = (ep + 1 + startPos).clamp(0, built.length).toInt();
          }
        }
        built.insertAll(insert, part);
        base += length;
      }
      parts.add((skelPos, base, out.length));
      out.add(built);
    }
    final html = out.toBytes();
    return Kf8Text(html, _toc(record, ncx, parts, frag.entries));
  }

  static List<(int, String, int)> _toc(Uint8List? Function(int) record, int ncx, List<(int, int, int)> parts, List<MobiIndexEntry> frags) {
    if (ncx == nullIndex) return const [];
    final MobiIndex index;
    try {
      index = MobiIndex.read(record, ncx);
    } catch (_) {
      return const [];
    }
    int map(int assembled) {
      if (parts.isEmpty) return assembled;
      for (final (s, e, o) in parts) {
        if (assembled >= s && assembled < e) return o + (assembled - s);
      }
      return -1;
    }

    final out = <(int, String, int)>[];
    for (final e in index.entries) {
      final title = (index.cncx[e.tag(3)] ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (title.isEmpty) continue;
      var pos = -1;
      final fid = e.tag(6, 0);
      if (fid >= 0 && fid < frags.length) {
        pos = (int.tryParse(frags[fid].label) ?? -1) + e.tag(6, 1, 0);
      } else {
        pos = e.tag(1);
      }
      if (pos < 0) continue;
      final at = map(pos);
      if (at < 0) continue;
      out.add((at, title, e.tag(4, 0, 0)));
    }
    return out;
  }

  /// `kindle:embed:XXXX` (base 32, 1-based resource number) -> resource number.
  static int? embedIndex(String ref) {
    final m = RegExp(r'kindle:embed:([0-9A-Va-v]+)').firstMatch(ref);
    if (m == null) return null;
    return int.tryParse(m.group(1)!, radix: 32);
  }
}
