import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/util/legado/js_engines.dart';
import 'package:newread/util/webbook/analyze_rule/analyze_rule.dart';
import 'package:newread/util/webbook/analyze_rule/js_files.dart';
import 'package:newread/util/webbook/analyze_rule/query_ttf.dart';
import 'package:newread/util/webbook/analyze_rule/rule_data.dart';
import 'package:newread/util/webbook/util/cache_manager.dart';

/// A glyph for the test fonts: simple contours (points with on-curve flags) or a composite of other glyph ids.
class G {
  final List<List<(int, int, bool)>> contours;
  final List<(int, int, int)> components; // glyph id, dx, dy
  final bool shortCoords;
  const G(this.contours, {this.components = const [], this.shortCoords = true});
  const G.composite(this.components)
      : contours = const [],
        shortCoords = true;
}

/// Builds a TrueType font: head, maxp, cmap (format 4, or 12 when [format12]), loca (long), glyf.
Uint8List buildTtf(List<G> glyphs, Map<int, int> cmap, {bool format12 = false}) {
  final glyf = BytesBuilder();
  final loca = <int>[];
  void u16(BytesBuilder b, int v) => b.add([(v >> 8) & 0xff, v & 0xff]);
  for (final g in glyphs) {
    loca.add(glyf.length);
    if (g.contours.isEmpty && g.components.isEmpty) continue;
    final b = BytesBuilder();
    if (g.components.isNotEmpty) {
      u16(b, 0xFFFF); // -1 contours
      b.add(List.filled(8, 0));
      for (var i = 0; i < g.components.length; i++) {
        final (gid, dx, dy) = g.components[i];
        final more = i < g.components.length - 1;
        u16(b, 0x0001 | 0x0002 | (more ? 0x0020 : 0)); // ARG_1_AND_2_ARE_WORDS | ARGS_ARE_XY_VALUES
        u16(b, gid);
        u16(b, dx & 0xffff);
        u16(b, dy & 0xffff);
      }
    } else {
      u16(b, g.contours.length);
      b.add(List.filled(8, 0));
      var n = 0;
      for (final c in g.contours) {
        n += c.length;
        u16(b, n - 1);
      }
      u16(b, 0); // no instructions
      final pts = g.contours.expand((c) => c).toList();
      final flags = <int>[];
      final xs = BytesBuilder(), ys = BytesBuilder();
      var px = 0, py = 0;
      for (final (x, y, on) in pts) {
        var f = on ? 1 : 0;
        final dx = x - px, dy = y - py;
        if (g.shortCoords && dx.abs() < 256) {
          f |= 2 | (dx >= 0 ? 16 : 0);
          xs.addByte(dx.abs());
        } else {
          u16(xs, dx & 0xffff);
        }
        if (g.shortCoords && dy.abs() < 256) {
          f |= 4 | (dy >= 0 ? 32 : 0);
          ys.addByte(dy.abs());
        } else {
          u16(ys, dy & 0xffff);
        }
        flags.add(f);
        px = x;
        py = y;
      }
      b
        ..add(flags)
        ..add(xs.takeBytes())
        ..add(ys.takeBytes());
    }
    final bytes = b.takeBytes();
    glyf.add(bytes);
    if (bytes.length.isOdd) glyf.addByte(0);
  }
  loca.add(glyf.length);
  final head = BytesBuilder()
    ..add(List.filled(50, 0))
    ..add([0, 1]) // indexToLocFormat = long
    ..add([0, 0]);
  final maxp = BytesBuilder()
    ..add([0, 1, 0, 0]);
  u16(maxp, glyphs.length);
  final locaB = BytesBuilder();
  for (final o in loca) {
    locaB.add([(o >> 24) & 0xff, (o >> 16) & 0xff, (o >> 8) & 0xff, o & 0xff]);
  }
  final codes = cmap.keys.toList()..sort();
  final sub = BytesBuilder();
  if (format12) {
    u16(sub, 12);
    u16(sub, 0);
    void u32(int v) => sub.add([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
    u32(16 + 12 * codes.length);
    u32(0);
    u32(codes.length);
    for (final c in codes) {
      u32(c);
      u32(c);
      u32(cmap[c]!);
    }
  } else {
    // one segment per code + the 0xFFFF terminator, idDelta mapping
    final segs = codes.length + 1;
    u16(sub, 4);
    u16(sub, 16 + segs * 8);
    u16(sub, 0);
    u16(sub, segs * 2);
    u16(sub, 0);
    u16(sub, 0);
    u16(sub, 0);
    for (final c in codes) {
      u16(sub, c);
    }
    u16(sub, 0xFFFF);
    u16(sub, 0);
    for (final c in codes) {
      u16(sub, c);
    }
    u16(sub, 0xFFFF);
    for (final c in codes) {
      u16(sub, (cmap[c]! - c) & 0xffff);
    }
    u16(sub, 1);
    for (var i = 0; i < segs; i++) {
      u16(sub, 0);
    }
  }
  final cmapB = BytesBuilder();
  u16(cmapB, 0);
  u16(cmapB, 1);
  u16(cmapB, 3);
  u16(cmapB, format12 ? 10 : 1);
  cmapB.add([0, 0, 0, 12]);
  cmapB.add(sub.takeBytes());
  final tables = {'cmap': cmapB.takeBytes(), 'glyf': glyf.takeBytes(), 'head': head.takeBytes(), 'loca': locaB.takeBytes(), 'maxp': maxp.takeBytes()};
  final out = BytesBuilder();
  out.add([0, 1, 0, 0]);
  u16(out, tables.length);
  out.add(List.filled(6, 0));
  var off = 12 + 16 * tables.length;
  final body = BytesBuilder();
  tables.forEach((tag, data) {
    out.add(ascii.encode(tag));
    out.add([0, 0, 0, 0]);
    out.add([(off >> 24) & 0xff, (off >> 16) & 0xff, (off >> 8) & 0xff, off & 0xff]);
    out.add([(data.length >> 24) & 0xff, (data.length >> 16) & 0xff, (data.length >> 8) & 0xff, data.length & 0xff]);
    final padded = (data.length + 3) & ~3;
    body.add(data);
    body.add(List.filled(padded - data.length, 0));
    off += padded;
  });
  out.add(body.takeBytes());
  return out.takeBytes();
}

/// WOFF 1.0 wrapper with zlib-compressed tables.
Uint8List toWoff(Uint8List ttf) {
  final bd = ByteData.sublistView(ttf);
  final n = bd.getUint16(4);
  final entries = <(int, Uint8List, int)>[];
  for (var i = 0; i < n; i++) {
    final r = 12 + i * 16;
    final data = Uint8List.sublistView(ttf, bd.getUint32(r + 8), bd.getUint32(r + 8) + bd.getUint32(r + 12));
    final comp = Uint8List.fromList(ZLibCodec().encode(data));
    entries.add((bd.getUint32(r), comp.length < data.length ? comp : data, data.length));
  }
  final out = BytesBuilder();
  void u32(int v) => out.add([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
  void u16(int v) => out.add([(v >> 8) & 0xff, v & 0xff]);
  out.add(ascii.encode('wOFF'));
  u32(0x00010000);
  u32(0); // length (unchecked)
  u16(n);
  u16(0);
  u32(ttf.length);
  out.add(List.filled(24, 0));
  var off = 44 + 20 * n;
  final body = BytesBuilder();
  for (final (tag, data, orig) in entries) {
    u32(tag);
    u32(off);
    u32(data.length);
    u32(orig);
    u32(0);
    final padded = (data.length + 3) & ~3;
    body.add(data);
    body.add(List.filled(padded - data.length, 0));
    off += padded;
  }
  out.add(body.takeBytes());
  return out.takeBytes();
}

const square = [
  [(0, 0, true), (500, 0, true), (500, 500, true), (0, 500, true)]
];
const triangle = [
  [(0, 0, true), (300, 600, false), (600, 0, true)]
];
const bar = [
  [(100, 100, true), (900, 100, true), (900, 200, true), (100, 200, true)]
];

void main() {
  // standard font: 中 = square, 文 = triangle, 字 = composite(square + bar shifted), ⼀ (U+2F00) and 一 share the bar outline
  final standard = buildTtf(
    [const G([]), const G(square), const G(triangle), const G(bar), const G.composite([(1, 0, 0), (3, 0, 600)])],
    {0x4E2D: 1, 0x6587: 2, 0x4E00: 3, 0x2F00: 3, 0x5B57: 4, 0x20: 0},
  );
  // obfuscated font: private-use code points, other glyph order, long coordinates (another encoding of the same outlines)
  final obfuscated = buildTtf(
    [const G([]), const G(triangle, shortCoords: false), const G(bar), const G(square, shortCoords: false), const G.composite([(3, 0, 0), (2, 0, 600)])],
    {0xE001: 1, 0xE002: 3, 0xE003: 4, 0xE004: 2, 0xE005: 0},
    format12: true,
  );

  test('outline lookup and replaceFont (sfnt and WOFF)', () {
    final std = QueryTTF(standard);
    for (final err in [QueryTTF(obfuscated), QueryTTF(toWoff(obfuscated))]) {
      expect(err.getGlyfIdByUnicode(0xE002), 3);
      expect(std.getUnicodeByGlyf(err.getGlyfByUnicode(0xE001)), 0x6587);
      expect(QueryTTF.replaceFont('第章 x', err, std), '第中文字一章 x');
      // filter drops characters without an outline in the obfuscated font (the space stays: blank)
      expect(QueryTTF.replaceFont('a ', err, std, filter: true), ' 中');
    }
    // the radical U+2F00 is skipped (0x100..0x33FF), so the shared outline maps to 一
    expect(std.getUnicodeByGlyf(std.getGlyfByUnicode(0x4E00)), 0x4E00);
    expect(QueryTTF.replaceFont('abc', null, std), 'abc');
  });

  group('JS natives', () {
    late HttpServer server;
    late Directory tmp;
    setUpAll(() async {
      JsEngines.useDart();
      tmp = Directory.systemTemp.createTempSync('jsfiles');
      JsFiles.root = tmp;
      final zip = ZipEncoder().encodeBytes(Archive()
        ..addFile(ArchiveFile.bytes('a.txt', utf8.encode('第一章')))
        ..addFile(ArchiveFile.bytes('b.txt', [0xB5, 0xDA, 0xB6, 0xFE, 0xD5, 0xC2]))); // 第二章 in GBK
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        final body = switch (r.uri.path) {
          '/std.ttf' => standard,
          '/obf.woff' => toWoff(obfuscated),
          '/book.zip' => zip,
          _ => utf8.encode('plain ${r.uri.path}'),
        };
        r.response.add(body);
        r.response.close();
      });
    });
    tearDownAll(() async {
      await server.close(force: true);
      tmp.deleteSync(recursive: true);
    });
    setUp(CacheManager.resetForTests);

    String base() => 'http://127.0.0.1:${server.port}';

    test('queryTTF from base64 and from a url, replaceFont with the returned objects', () async {
      final r = AnalyzeRule(RuleData())..setContent('');
      final b64 = base64.encode(obfuscated);
      final out = await r.getString('@js:var e = java.queryTTF("$b64"); var s = java.queryTTF("${base()}/std.ttf"); '
          'java.replaceFont(result, e, s) + "|" + java.replaceFont(result, e, s, true)');
      expect(out, '中一|中一');
      final viaWoff = await r.getString('@js:java.replaceFont(result, java.queryTTF("${base()}/obf.woff"), java.queryTTF("${base()}/std.ttf"))');
      expect(viaWoff, '中一');
    });

    test('downloadFile / readTxtFile / unzipFile / getTxtInFolder / zip content / deleteFile, sandboxed', () async {
      final r = AnalyzeRule(RuleData())..setContent('');
      final path = await r.getString('@js:java.downloadFile("${base()}/book.zip")');
      expect(path, startsWith('/'));
      expect(path, endsWith('.zip'));
      expect(File('${tmp.path}$path').existsSync(), isTrue);
      final folder = await r.getString('@js:java.unzipFile("$path")');
      expect(folder, startsWith('ArchiveTemp/'));
      expect(await r.getString('@js:java.readTxtFile("$folder/b.txt")'), '第二章');
      expect(await r.getString('@js:java.getTxtInFolder("$folder")'), '第一章\n第二章');
      expect(Directory('${tmp.path}/$folder').existsSync(), isFalse);
      expect(await r.getString('@js:java.getZipStringContent("${base()}/book.zip", "a.txt")'), '第一章');
      expect(await r.getString('@js:java.getZipByteArrayContent("${base()}/book.zip", "b.txt").length'), '6');
      expect(await r.getString('@js:java.cacheFile("${base()}/x.js", 60)'), 'plain /x.js');
      expect(await r.getString('@js:java.deleteFile("$path")'), 'true');
      expect(File('${tmp.path}$path').existsSync(), isFalse);
      expect(() => JsFiles.getFile('../../outside.txt'), throwsA(anything));
      expect(await r.getString('@js:try { java.readFile("../x") ; "no" } catch (e) { "blocked" }'), 'blocked');
    });
  });
}
