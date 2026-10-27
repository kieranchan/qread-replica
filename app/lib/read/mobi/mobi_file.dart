// read/mobi/mobi_file.dart — local MOBI / AZW books, best effort (original: `abstract class MobiFile` with `_MobiHeader`, `_getContent(Map)`
// 0x2a76e8 and three `Match -> String` HTML fix-up closures 0x2a7c08 / 0x2a7cbc / 0x2a7d4c).
//
// Supported: PalmDOC-compressed (type 2) and uncompressed (type 1) MOBI 6 files, UTF-8 and cp1252 text, EXTH title / author / description /
// cover, `<img recindex>` images (JPEG / PNG / GIF records), chapters from the book's own table of contents (`<reference type="toc"
// filepos>` and the `<a filepos>` links on that page), else from `<mbp:pagebreak>`, else fixed-size pieces.
//
// NOT supported (reported with a clear message): Huffman/CDIC compression (type 17480, some old Kindle files), DRM-protected files
// (encryption type != 0), and KF8-only AZW3 files (the text is stored as skeleton + fragment parts joined through INDX tables that this
// port does not parse; combined MOBI6+KF8 files are read through their MOBI 6 part). Convert such books to EPUB first.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/bookchapter.dart';
import '../api/read_file_store.dart';
import '../epub/epub_html.dart';
import '../util/chapter_content.dart';

class MobiException implements Exception {
  final String message;
  const MobiException(this.message);
  @override
  String toString() => message;
}

/// Class 1491 `_MobiHeader` (12 slots in the original): the fields of record 0 this reader uses.
class MobiHeader {
  final int compression;
  final int textLength;
  final int textRecords;
  final int recordSize;
  final int encryption;
  final int version;
  final int encoding;
  final int firstImage;
  final int extraFlags;
  final String title;
  final Map<int, List<Uint8List>> exth;

  const MobiHeader({
    required this.compression,
    required this.textLength,
    required this.textRecords,
    required this.recordSize,
    required this.encryption,
    required this.version,
    required this.encoding,
    required this.firstImage,
    required this.extraFlags,
    required this.title,
    required this.exth,
  });

  String exthString(int type) {
    final v = exth[type];
    if (v == null || v.isEmpty) return '';
    return utf8.decode(v.first, allowMalformed: true).trim();
  }
}

class MobiParseResult {
  final String name;
  final String author;
  final String intro;
  final String charset;
  final String coverFile;
  final List<BookChapter> chapters;

  /// Directory with `text.html` (decompressed book text, original encoding) and `img_<n>.<ext>`.
  final String workDir;

  const MobiParseResult({
    required this.name,
    required this.author,
    required this.intro,
    required this.charset,
    required this.coverFile,
    required this.chapters,
    required this.workDir,
  });
}

abstract class MobiFile {
  static const int fixedChars = 10000;

  // ---------------------------------------------------------------- low level

  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static int _u32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// Offsets of the PDB records (+ the end of file as a last entry).
  static List<int> recordOffsets(Uint8List b) {
    if (b.length < 78 + 8) throw const MobiException('不是有效的MOBI文件');
    final n = _u16(b, 76);
    if (n < 2 || 78 + 8 * n > b.length) throw const MobiException('不是有效的MOBI文件：记录表损坏');
    final offs = <int>[for (var i = 0; i < n; i++) _u32(b, 78 + 8 * i)];
    offs.add(b.length);
    return offs;
  }

  /// Parses record 0.
  static MobiHeader readHeader(Uint8List b, List<int> offs) {
    final r0 = offs[0];
    final r0end = offs[1];
    if (r0 + 16 + 8 > r0end) throw const MobiException('不是有效的MOBI文件');
    final compression = _u16(b, r0);
    final textLength = _u32(b, r0 + 4);
    final textRecords = _u16(b, r0 + 8);
    final recordSize = _u16(b, r0 + 10);
    final encryption = _u16(b, r0 + 12);
    final id = String.fromCharCodes(b.sublist(r0 + 16, r0 + 20));
    if (id != 'MOBI') throw const MobiException('不是有效的MOBI文件：缺少 MOBI 头');
    final hlen = _u32(b, r0 + 20);
    final encoding = _u32(b, r0 + 28);
    final version = _u32(b, r0 + 36);
    final fullNameOff = _u32(b, r0 + 84);
    final fullNameLen = _u32(b, r0 + 88);
    var firstImage = hlen >= 0x70 ? _u32(b, r0 + 108) : 0xFFFFFFFF;
    var extraFlags = 0;
    if (hlen >= 0xE4 && version >= 5 && r0 + 0xF4 <= r0end) extraFlags = _u16(b, r0 + 0xF2);
    final exthFlags = hlen >= 0x84 ? _u32(b, r0 + 128) : 0;
    final exth = <int, List<Uint8List>>{};
    if (exthFlags & 0x40 != 0) {
      final eo = r0 + 16 + hlen;
      if (eo + 12 <= r0end && String.fromCharCodes(b.sublist(eo, eo + 4)) == 'EXTH') {
        final count = _u32(b, eo + 8);
        var o = eo + 12;
        for (var i = 0; i < count && o + 8 <= r0end; i++) {
          final type = _u32(b, o);
          final len = _u32(b, o + 4);
          if (len < 8 || o + len > r0end) break;
          exth.putIfAbsent(type, () => []).add(Uint8List.sublistView(b, o + 8, o + len));
          o += len;
        }
      }
    }
    var title = '';
    if (fullNameLen > 0 && r0 + fullNameOff + fullNameLen <= r0end) {
      title = _decodeText(Uint8List.sublistView(b, r0 + fullNameOff, r0 + fullNameOff + fullNameLen), encoding).trim();
    }
    if (firstImage > offs.length - 2) firstImage = -1;
    return MobiHeader(
      compression: compression,
      textLength: textLength,
      textRecords: textRecords,
      recordSize: recordSize,
      encryption: encryption,
      version: version,
      encoding: encoding,
      firstImage: firstImage,
      extraFlags: extraFlags,
      title: title,
      exth: exth,
    );
  }

  static String _decodeText(Uint8List bytes, int encoding) => encoding == 65001 ? utf8.decode(bytes, allowMalformed: true) : latin1.decode(bytes);

  /// PalmDOC (LZ77) decompression of one record.
  static Uint8List palmDocDecompress(Uint8List data) {
    final out = BytesBuilder(copy: false);
    final buf = <int>[]; // window needs random access to the output
    var i = 0;
    final n = data.length;
    while (i < n) {
      final c = data[i++];
      if (c == 0 || (c >= 9 && c <= 0x7F)) {
        buf.add(c);
      } else if (c >= 1 && c <= 8) {
        for (var k = 0; k < c && i < n; k++) {
          buf.add(data[i++]);
        }
      } else if (c >= 0xC0) {
        buf.add(0x20);
        buf.add(c ^ 0x80);
      } else {
        if (i >= n) break;
        final pair = (c << 8) | data[i++];
        final dist = (pair >> 3) & 0x7FF;
        final len = (pair & 7) + 3;
        if (dist == 0 || dist > buf.length) break;
        for (var k = 0; k < len; k++) {
          buf.add(buf[buf.length - dist]);
        }
      }
    }
    out.add(buf);
    return out.toBytes();
  }

  /// Number of bytes of trailing entries at the end of a text record (multibyte overlap + extra data flags).
  static int trailingSize(Uint8List rec, int flags) {
    var num = 0;
    var f = flags >> 1;
    while (f != 0) {
      if (f & 1 != 0) {
        var size = rec.length - num;
        var bitpos = 0;
        var result = 0;
        while (true) {
          if (size <= 0) break;
          final v = rec[size - 1];
          result |= (v & 0x7F) << bitpos;
          bitpos += 7;
          size--;
          if ((v & 0x80) != 0 || bitpos >= 28 || size == 0) break;
        }
        num += result;
      }
      f >>= 1;
    }
    if (flags & 1 != 0 && rec.length - num - 1 >= 0) num += (rec[rec.length - num - 1] & 3) + 1;
    return num;
  }

  /// Decompressed book text in its original encoding.
  static Uint8List readText(Uint8List b, List<int> offs, MobiHeader h) {
    if (h.compression == 17480) {
      throw const MobiException('暂不支持 Huffman 压缩的 MOBI 文件，请先转换为 EPUB');
    }
    if (h.compression != 1 && h.compression != 2) {
      throw MobiException('不支持的 MOBI 压缩方式: ${h.compression}');
    }
    if (h.encryption != 0) throw const MobiException('该 MOBI 文件有 DRM 保护，无法打开');
    if (h.version >= 8) {
      // A KF8-only file: the text records hold skeleton/fragment parts that need the INDX tables to be put back together.
      throw const MobiException('暂不支持 AZW3/KF8 格式（需要解析 skeleton 索引），请先转换为 EPUB');
    }
    final out = BytesBuilder(copy: false);
    final last = h.textRecords.clamp(0, offs.length - 2).toInt();
    for (var i = 1; i <= last; i++) {
      var rec = Uint8List.sublistView(b, offs[i], offs[i + 1]);
      rec = Uint8List.sublistView(rec, 0, rec.length - trailingSize(rec, h.extraFlags).clamp(0, rec.length).toInt());
      out.add(h.compression == 2 ? palmDocDecompress(rec) : rec);
    }
    return out.toBytes();
  }

  // ---------------------------------------------------------------- chapters

  static final RegExp _pagebreak = RegExp(r'<mbp:pagebreak\s*/?>', caseSensitive: false);

  /// Chapter ranges `(start, end, title)` as byte offsets into [text].
  static List<(int, int, String)> splitChapters(Uint8List text, int encoding) {
    final s = latin1.decode(text); // 1 byte = 1 char, so string indexes are byte offsets
    // 1. the book's own TOC
    final tocPos = RegExp(r'<reference[^>]*type="toc"[^>]*filepos=\D*(\d+)', caseSensitive: false).firstMatch(s) ??
        RegExp(r'<reference[^>]*filepos=\D*(\d+)[^>]*type="toc"', caseSensitive: false).firstMatch(s);
    if (tocPos != null) {
      final start = int.parse(tocPos.group(1)!);
      if (start > 0 && start < s.length) {
        final pb = _pagebreak.firstMatch(s.substring(start));
        final end = pb == null ? s.length : start + pb.start;
        final entries = <(int, String)>[];
        for (final m in RegExp(r'<a\s[^>]*filepos=\D*(\d+)[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true).allMatches(s.substring(start, end))) {
          final pos = int.parse(m.group(1)!);
          final title = _decodeText(latin1.encode(m.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '')), encoding).replaceAll(RegExp(r'\s+'), ' ').trim();
          if (pos > 0 && pos < s.length && title.isNotEmpty) entries.add((pos, title));
        }
        entries.sort((a, b) => a.$1.compareTo(b.$1));
        final dedup = <(int, String)>[];
        for (final e in entries) {
          if (dedup.isEmpty || dedup.last.$1 != e.$1) dedup.add(e);
        }
        if (dedup.length >= 2) {
          final out = <(int, int, String)>[];
          if (dedup.first.$1 > 0 && _hasText(s.substring(0, dedup.first.$1))) out.add((0, dedup.first.$1, '前言'));
          for (var i = 0; i < dedup.length; i++) {
            out.add((dedup[i].$1, i + 1 < dedup.length ? dedup[i + 1].$1 : s.length, dedup[i].$2));
          }
          return out;
        }
      }
    }
    // 2. page breaks
    final cuts = <int>[0, for (final m in _pagebreak.allMatches(s)) m.end];
    cuts.add(s.length);
    final pieces = <(int, int)>[];
    for (var i = 0; i + 1 < cuts.length; i++) {
      if (cuts[i + 1] > cuts[i] && _hasText(s.substring(cuts[i], cuts[i + 1]))) pieces.add((cuts[i], cuts[i + 1]));
    }
    if (pieces.length >= 2) {
      return [
        for (var i = 0; i < pieces.length; i++) (pieces[i].$1, pieces[i].$2, _titleOf(s.substring(pieces[i].$1, pieces[i].$2), encoding, i)),
      ];
    }
    // 3. fixed-size pieces at tag boundaries
    final out = <(int, int, String)>[];
    final target = fixedChars * (encoding == 65001 ? 3 : 2);
    var start = 0;
    while (start < s.length) {
      var end = start + target;
      if (end >= s.length) {
        end = s.length;
      } else {
        final nl = s.indexOf('</p>', end);
        end = nl < 0 ? s.length : nl + 4;
      }
      out.add((start, end, '第${out.length + 1}章'));
      start = end;
    }
    return out;
  }

  static bool _hasText(String html) => html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'[\s ]|&nbsp;'), '').isNotEmpty || html.contains('recindex');

  static String _titleOf(String htmlLatin1, int encoding, int index) {
    final head = htmlLatin1.length > 4000 ? htmlLatin1.substring(0, 4000) : htmlLatin1;
    final h = RegExp(r'<h[1-4][^>]*>(.*?)</h[1-4]>', caseSensitive: false, dotAll: true).firstMatch(head);
    var t = h?.group(1) ?? RegExp(r'>([^<>]{2,40})<').firstMatch(head)?.group(1) ?? '';
    t = _decodeText(latin1.encode(t.replaceAll(RegExp(r'<[^>]*>'), '')), encoding).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 40) t = t.substring(0, 40);
    return t.isEmpty ? '第${index + 1}章' : t;
  }

  // ---------------------------------------------------------------- public API

  /// Parses [file] (isolate). Writes `text.html` and the images into `<workDir>`; the cover (if any) is copied to [coverDir].
  static Future<MobiParseResult> parse(File file, {required Directory workDir, Directory? coverDir, String? bookUrl}) async {
    final path = file.path;
    final work = workDir.path;
    final cover = coverDir?.path;
    final url = bookUrl ?? path;
    final map = await ReadIsolate.run(() => _parseSync(path, work, cover, url));
    return MobiParseResult(
      name: map['name'] as String,
      author: map['author'] as String,
      intro: map['intro'] as String,
      charset: map['charset'] as String,
      coverFile: map['cover'] as String,
      workDir: work,
      chapters: (map['chapters'] as List).map((e) => BookChapter.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  static String _imageExt(Uint8List d) {
    if (d.length > 3 && d[0] == 0xFF && d[1] == 0xD8) return 'jpg';
    if (d.length > 4 && d[0] == 0x89 && d[1] == 0x50) return 'png';
    if (d.length > 3 && d[0] == 0x47 && d[1] == 0x49 && d[2] == 0x46) return 'gif';
    if (d.length > 2 && d[0] == 0x42 && d[1] == 0x4D) return 'bmp';
    return '';
  }

  static Map<String, dynamic> _parseSync(String path, String workDir, String? coverDir, String bookUrl) {
    final b = File(path).readAsBytesSync();
    final offs = recordOffsets(b);
    final h = readHeader(b, offs);
    final text = readText(b, offs, h);

    final dir = Directory(workDir)..createSync(recursive: true);
    File('${dir.path}/text.html').writeAsBytesSync(text);

    // images
    final imageFiles = <int, String>{};
    if (h.firstImage > 0) {
      for (var r = h.firstImage; r < offs.length - 1; r++) {
        final d = Uint8List.sublistView(b, offs[r], offs[r + 1]);
        final ext = _imageExt(d);
        if (ext.isEmpty) continue; // not an image record (FLIS, FCIS, SRCS, ...)
        final f = File('${dir.path}/img_${r - h.firstImage + 1}.$ext');
        f.writeAsBytesSync(d);
        imageFiles[r - h.firstImage + 1] = f.path;
      }
    }
    var cover = '';
    final coverOff = h.exth[201]?.firstOrNull;
    if (coverDir != null && coverOff != null && coverOff.length == 4) {
      final idx = _u32(coverOff, 0) + 1;
      final src = imageFiles[idx];
      if (src != null) {
        final dest = File('$coverDir/${ReadFileStore.md5Hex(bookUrl)}${p.extension(src)}');
        dest.parent.createSync(recursive: true);
        File(src).copySync(dest.path);
        cover = dest.path;
      }
    }

    final ranges = splitChapters(text, h.encoding);
    final chapters = <BookChapter>[
      for (var i = 0; i < ranges.length; i++)
        BookChapter(name: ranges[i].$3, chapterId: '$i', tag: 'mobi', baseUrl: workDir, index: i, start: ranges[i].$1, end: ranges[i].$2),
    ];
    final title = h.exthString(503).isNotEmpty ? h.exthString(503) : (h.title.isNotEmpty ? h.title : p.basenameWithoutExtension(path));
    return {
      'name': title,
      'author': h.exthString(100),
      'intro': h.exthString(103).replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      'charset': h.encoding == 65001 ? 'UTF-8' : 'windows-1252',
      'cover': cover,
      'chapters': chapters.map((c) => c.toJson()).toList(),
    };
  }

  /// Chapter body (original `_getContent(Map)`): the byte range of `<workDir>/text.html`, converted to blocks.
  static Future<ChapterContent> getChapterContent(BookChapter chapter, String charset) {
    final work = chapter.baseUrl;
    final start = chapter.start;
    final end = chapter.end;
    final title = chapter.name;
    return ReadIsolate.run(() => getChapterContentSync(work, start, end, charset, title));
  }

  static ChapterContent getChapterContentSync(String workDir, int start, int end, String charset, String title) {
    final raf = File('$workDir/text.html').openSync();
    Uint8List data;
    try {
      raf.setPositionSync(start);
      data = raf.readSync(end - start);
    } finally {
      raf.closeSync();
    }
    var html = charset == 'UTF-8' ? utf8.decode(data, allowMalformed: true) : latin1.decode(data);
    // `<img recindex="0007">` -> `<img src="mobi-img-7">`; page breaks are chapter boundaries already
    html = html.replaceAllMapped(RegExp(r'recindex="?0*(\d+)"?', caseSensitive: false), (m) => 'src="mobi-img-${m.group(1)}"');
    html = html.replaceAll(RegExp(r'<mbp:pagebreak\s*/?>', caseSensitive: false), '<br/>');
    String? resolve(String ref) {
      final m = RegExp(r'^mobi-img-(\d+)$').firstMatch(ref);
      if (m == null) return null;
      final dir = Directory(workDir);
      for (final e in dir.listSync()) {
        final name = p.basename(e.path);
        if (name.startsWith('img_${m.group(1)}.')) return e.path;
      }
      return null;
    }

    final content = EpubHtml.toContent(html, resolveImage: resolve);
    return _dropTitle(content, title);
  }

  static ChapterContent _dropTitle(ChapterContent c, String title) {
    if (c.blocks.isEmpty || c.blocks.first.isImage) return c;
    String norm(String s) => s.replaceAll(RegExp(r'[\s　]+'), '');
    final first = c.blocks.first.runs.map((r) => r.str).join();
    if (first.isEmpty || norm(first) != norm(title)) return c;
    final shift = c.blocks.length > 1 ? first.length + 1 : first.length;
    for (final b in c.blocks.skip(1)) {
      for (final r in b.runs) {
        if (r.start >= 0) r.start -= shift;
        if (r.end >= 0) r.end -= shift;
      }
    }
    return ChapterContent(c.text.length >= shift ? c.text.substring(shift) : '', c.blocks.skip(1).toList());
  }
}
