// read/mobi/mobi_file.dart — local MOBI / AZW / AZW3 books (original: `abstract class MobiFile` with `_MobiHeader`; chapters
// 0xedb06c, header 0x24b58c, text 0x255660, chapter split 0x254e84 + fallback 0x254c18, chapter text `_getContent(Map)` 0x2a76e8 ->
// 0xf13c80, EXTH 0xedb3d4).
//
// As the original: record 0 header (errors 文件太小，不是有效的MOBI文件 / MOBI文件记录数为0 / MOBI文件损坏 / 不是有效的MOBI文件), PalmDOC
// text records, UTF-8 (65001) or CP1252 text, EXTH 100 author / 503 title / 201 cover, chapters as byte ranges of the text:
//   1. 0x254e84: every `<mbp:pagebreak/>` followed by a short `<p height="Nem">` heading (case-insensitive regex, title 1..40
//      characters, not one of 目录 前言 序 导读 版权 附录 封面 封底 00 r 000 f000 p top TOP Table of Contents, no ，。！？；：), a heading of
//      12em or more is a volume; text before the first heading belongs to no chapter, like the original;
//   2. else 0x254c18: pieces of 20000 bytes cut after a line break in their second half, named 第N部分.
// Additions of this port (the original copies such records raw and shows noise): Huffman/CDIC compression (huffcdic.dart), KF8-only
// AZW3 books assembled from their skeleton/fragment indexes (kf8.dart), trailing entries stripped from the text records, and between
// steps 1 and 2 the book's own table of contents (MOBI 6 `<reference type="toc" filepos>` page / KF8 NCX index). The chapter text keeps
// images (`<img recindex>` / `kindle:embed:`) instead of the original's plain-text conversion (0x2a7718). DRM-protected files are
// refused. Combined MOBI 6 + KF8 files are read through their MOBI 6 part, as the original reads record 0 only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/bookchapter.dart';
import '../api/read_file_store.dart';
import '../epub/epub_html.dart';
import '../util/chapter_content.dart';
import 'huffcdic.dart';
import 'kf8.dart';

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

  /// HUFF record and number of HUFF + CDIC records (compression 17480).
  final int huffRecord;
  final int huffCount;

  /// KF8 (version 8) record numbers of the FDST table and the NCX / fragment / skeleton indexes ([Kf8.nullIndex] when absent).
  final int fdst;
  final int ncx;
  final int fragment;
  final int skeleton;

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
    this.huffRecord = 0,
    this.huffCount = 0,
    this.fdst = Kf8.nullIndex,
    this.ncx = Kf8.nullIndex,
    this.fragment = Kf8.nullIndex,
    this.skeleton = Kf8.nullIndex,
  });

  bool get isKf8 => version >= 8;

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
  /// Size of a 第N部分 piece in bytes and the point after which a line break may end it (0x254c18).
  static const int pieceBytes = 20000;
  static const int pieceMinBytes = 10000;

  /// Compression types of record 0.
  static const int noCompression = 1;
  static const int palmDoc = 2;
  static const int huffCdic = 17480;

  // ---------------------------------------------------------------- low level

  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static int _u32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// Offsets of the PDB records (+ the end of file as a last entry).
  static List<int> recordOffsets(Uint8List b) {
    if (b.length < 78) throw const MobiException('文件太小，不是有效的MOBI文件');
    final n = _u16(b, 76);
    if (n == 0) throw const MobiException('MOBI文件记录数为0');
    if (n < 2 || 78 + 8 * n > b.length) throw const MobiException('MOBI文件损坏');
    final offs = <int>[for (var i = 0; i < n; i++) _u32(b, 78 + 8 * i)];
    offs.add(b.length);
    for (var i = 0; i < n; i++) {
      if (offs[i] > offs[i + 1] || offs[i] > b.length) throw const MobiException('MOBI文件损坏');
    }
    return offs;
  }

  static Uint8List? _record(Uint8List b, List<int> offs, int i) =>
      i < 0 || i >= offs.length - 1 ? null : Uint8List.sublistView(b, offs[i], offs[i + 1]);

  /// Parses record 0.
  static MobiHeader readHeader(Uint8List b, List<int> offs) {
    final r0 = offs[0];
    final r0end = offs[1];
    if (r0 + 16 + 8 > r0end) throw const MobiException('MOBI文件损坏');
    final compression = _u16(b, r0);
    final textLength = _u32(b, r0 + 4);
    final textRecords = _u16(b, r0 + 8);
    final recordSize = _u16(b, r0 + 10);
    final encryption = _u16(b, r0 + 12);
    final id = String.fromCharCodes(b.sublist(r0 + 16, r0 + 20));
    if (id != 'MOBI') throw const MobiException('不是有效的MOBI文件');
    final hlen = _u32(b, r0 + 20);
    int field(int off, [int fallback = 0]) => 16 + hlen >= off + 4 && r0 + off + 4 <= r0end ? _u32(b, r0 + off) : fallback;
    final encoding = field(28);
    final version = field(36);
    final fullNameOff = field(84);
    final fullNameLen = field(88);
    var firstImage = field(108, 0xFFFFFFFF);
    final huffRecord = field(0x70);
    final huffCount = field(0x74);
    var extraFlags = 0;
    if (hlen >= 0xE4 && version >= 5 && r0 + 0xF4 <= r0end) extraFlags = _u16(b, r0 + 0xF2);
    final exthFlags = field(128);
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
    final kf8 = version >= 8;
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
      huffRecord: huffRecord,
      huffCount: huffCount,
      fdst: kf8 ? field(0xC0, Kf8.nullIndex) : Kf8.nullIndex,
      ncx: kf8 ? field(0xF4, Kf8.nullIndex) : Kf8.nullIndex,
      fragment: kf8 ? field(0xF8, Kf8.nullIndex) : Kf8.nullIndex,
      skeleton: kf8 ? field(0xFC, Kf8.nullIndex) : Kf8.nullIndex,
    );
  }

  static String _decodeText(Uint8List bytes, int encoding) => encoding == 65001 ? utf8.decode(bytes, allowMalformed: true) : latin1.decode(bytes);

  /// PalmDOC (LZ77) decompression of one record (0x255a34).
  static Uint8List palmDocDecompress(Uint8List data) {
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
    return Uint8List.fromList(buf);
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

  /// Decompressed book text in its original encoding, cut to the header's text length like the original (0x255660).
  static Uint8List readText(Uint8List b, List<int> offs, MobiHeader h) {
    if (h.encryption != 0) throw const MobiException('该 MOBI 文件有 DRM 保护，无法打开');
    if (h.compression != noCompression && h.compression != palmDoc && h.compression != huffCdic) {
      throw MobiException('不支持的 MOBI 压缩方式: ${h.compression}');
    }
    HuffCdicReader? huff;
    if (h.compression == huffCdic) {
      final hr = _record(b, offs, h.huffRecord);
      if (hr == null || h.huffCount < 1) throw const MobiException('MOBI文件损坏：缺少 HUFF 记录');
      huff = HuffCdicReader(hr, [
        for (var i = 1; i < h.huffCount; i++) ?_record(b, offs, h.huffRecord + i),
      ]);
    }
    final out = BytesBuilder(copy: false);
    final last = h.textRecords.clamp(0, offs.length - 2).toInt();
    for (var i = 1; i <= last; i++) {
      var rec = Uint8List.sublistView(b, offs[i], offs[i + 1]);
      rec = Uint8List.sublistView(rec, 0, rec.length - trailingSize(rec, h.extraFlags).clamp(0, rec.length).toInt());
      out.add(switch (h.compression) {
        palmDoc => palmDocDecompress(rec),
        huffCdic => huff!.unpack(rec),
        _ => rec,
      });
    }
    final text = out.toBytes();
    if (h.textLength > 0 && text.length > h.textLength) return Uint8List.sublistView(text, 0, h.textLength);
    return text;
  }

  // ---------------------------------------------------------------- chapters

  /// 0x254e84: a page break followed by a one-line `<p height="Nem">` heading.
  static final RegExp _heading = RegExp(
    r'<mbp:pagebreak\s*/>\s*<p\s+height="(\d+)em"[^>]*>\s*(?:<font[^>]*>)?\s*(?:<b>)?([^<]{1,160}?)(?:</b>)?\s*(?:</font>)?\s*</p>',
    caseSensitive: false,
  );

  /// Titles 0x2554ac never takes as a chapter.
  static const List<String> skipTitles = [
    '目录', '前言', '序', '导读', '版权', '附录', '封面', '封底', '00', 'r', '000', 'f000', 'p', 'top', 'TOP', //
    'Table of Contents', 'table of contents',
  ];
  static final RegExp _sentencePunct = RegExp('[，。！？；：]');

  /// Chapter ranges `(start, end, title, isVolume)` as byte offsets into [text]: the original's split (0x254e84, else 0x254c18), with
  /// the book's own table of contents ([toc]: `(offset, title)`) tried in between.
  static List<(int, int, String, bool)> splitChapters(Uint8List text, int encoding, {List<(int, String)>? toc}) {
    final headed = headingChapters(text, encoding);
    if (headed.isNotEmpty) return headed;
    final own = toc ?? filposToc(text, encoding);
    final fromToc = tocChapters(text, own);
    if (fromToc.isNotEmpty) return fromToc;
    return pieceChapters(text);
  }

  /// 0x254e84. The regex runs on a byte view of the text (one char per byte) so the offsets are exact byte offsets; the title is
  /// then decoded and held to the original's 1..40 characters.
  static List<(int, int, String, bool)> headingChapters(Uint8List text, int encoding) {
    final s = latin1.decode(text);
    final total = text.length;
    final out = <(int, int, String, bool)>[];
    for (final m in _heading.allMatches(s)) {
      final height = int.tryParse(m.group(1) ?? '0') ?? 0;
      final raw = _decodeText(latin1.encode(m.group(2) ?? ''), encoding);
      if (raw.length > 40) continue;
      final title = raw.trim();
      if (title.isEmpty || title.length > 40) continue;
      if (skipTitles.contains(title)) continue;
      if (_sentencePunct.hasMatch(title)) continue;
      final start = m.start;
      if (start <= 0 || start >= total) continue;
      if (out.isNotEmpty && out.last.$1 == start) continue;
      out.add((start, 0, title, height >= 12));
    }
    return [
      for (var i = 0; i < out.length; i++) (out[i].$1, i + 1 < out.length ? out[i + 1].$1 : total, out[i].$3, out[i].$4),
    ];
  }

  /// 0x254c18: 20000-byte pieces; a piece ends after the last `\n` / `\r` in its second half when there is one. Named 第N部分.
  static List<(int, int, String, bool)> pieceChapters(Uint8List text) {
    final len = text.length;
    final out = <(int, int, String, bool)>[];
    var start = 0;
    while (start < len) {
      var end = start + pieceBytes > len ? len : start + pieceBytes;
      if (end < len) {
        for (var j = end; j > start + pieceMinBytes && j > start; j--) {
          if (j < len && (text[j] == 0x0A || text[j] == 0x0D)) {
            end = j + 1;
            break;
          }
        }
      }
      out.add((start, end, '第${out.length + 1}部分', false));
      start = end;
    }
    return out;
  }

  /// The MOBI 6 book's own TOC page: `<reference type="toc" filepos>` and the `<a filepos>` links on that page (addition of this port).
  static List<(int, String)> filposToc(Uint8List text, int encoding) {
    final s = latin1.decode(text);
    final tocPos = RegExp(r'<reference[^>]*type="toc"[^>]*filepos=\D*(\d+)', caseSensitive: false).firstMatch(s) ??
        RegExp(r'<reference[^>]*filepos=\D*(\d+)[^>]*type="toc"', caseSensitive: false).firstMatch(s);
    if (tocPos == null) return const [];
    final start = int.parse(tocPos.group(1)!);
    if (start <= 0 || start >= s.length) return const [];
    final pb = RegExp(r'<mbp:pagebreak\s*/?>', caseSensitive: false).firstMatch(s.substring(start));
    final end = pb == null ? s.length : start + pb.start;
    final entries = <(int, String)>[];
    for (final m in RegExp(r'<a\s[^>]*filepos=\D*(\d+)[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true).allMatches(s.substring(start, end))) {
      final pos = int.parse(m.group(1)!);
      final title = _decodeText(latin1.encode(m.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '')), encoding).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (pos > 0 && pos < s.length && title.isNotEmpty) entries.add((pos, title));
    }
    return entries;
  }

  /// Chapters from TOC entries `(offset, title)`; text before the first entry becomes 前言 when it has any. Needs two entries.
  static List<(int, int, String, bool)> tocChapters(Uint8List text, List<(int, String)> toc) {
    final entries = [for (final e in toc) if (e.$1 >= 0 && e.$1 < text.length) e]..sort((a, b) => a.$1.compareTo(b.$1));
    final dedup = <(int, String)>[];
    for (final e in entries) {
      if (dedup.isEmpty || dedup.last.$1 != e.$1) dedup.add(e);
    }
    if (dedup.length < 2) return const [];
    final out = <(int, int, String, bool)>[];
    if (dedup.first.$1 > 0 && _hasText(latin1.decode(Uint8List.sublistView(text, 0, dedup.first.$1)))) out.add((0, dedup.first.$1, '前言', false));
    for (var i = 0; i < dedup.length; i++) {
      out.add((dedup[i].$1, i + 1 < dedup.length ? dedup[i + 1].$1 : text.length, dedup[i].$2, false));
    }
    return out;
  }

  static bool _hasText(String html) {
    final body = html.replaceAll(RegExp(r'<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true), '');
    return body.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'[\s ]|&nbsp;'), '').isNotEmpty || body.contains('recindex');
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

  /// Image types the original accepts for the EXTH 201 cover (0xedb3d4: JPEG, PNG, GIF, BMP magic).
  static String _imageExt(Uint8List d) {
    if (d.length > 3 && d[0] == 0xFF && d[1] == 0xD8 && d[2] == 0xFF) return 'jpg';
    if (d.length > 4 && d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4E && d[3] == 0x47) return 'png';
    if (d.length > 4 && d[0] == 0x47 && d[1] == 0x49 && d[2] == 0x46 && d[3] == 0x38) return 'gif';
    if (d.length > 2 && d[0] == 0x42 && d[1] == 0x4D) return 'bmp';
    return '';
  }

  static Map<String, dynamic> _parseSync(String path, String workDir, String? coverDir, String bookUrl) {
    final f = File(path);
    if (!f.existsSync()) throw MobiException('MOBI文件不存在: $path');
    final b = f.readAsBytesSync();
    final offs = recordOffsets(b);
    final h = readHeader(b, offs);
    var text = readText(b, offs, h);
    List<(int, String)>? toc;
    if (h.isKf8) {
      final kf8 = Kf8.assemble(
        raw: text,
        record: (i) => _record(b, offs, i),
        fdst: h.fdst,
        skeleton: h.skeleton,
        fragment: h.fragment,
        ncx: h.ncx,
      );
      text = kf8.html;
      toc = [for (final e in kf8.toc) (e.$1, e.$2)];
    }

    final dir = Directory(workDir)..createSync(recursive: true);
    File('${dir.path}/text.html').writeAsBytesSync(text);

    // images
    final imageFiles = <int, String>{};
    if (h.firstImage > 0) {
      for (var r = h.firstImage; r < offs.length - 1; r++) {
        final d = Uint8List.sublistView(b, offs[r], offs[r + 1]);
        final ext = _imageExt(d);
        if (ext.isEmpty) continue; // not an image record (FLIS, FCIS, SRCS, FONT, RESC, ...)
        final out = File('${dir.path}/img_${r - h.firstImage + 1}.$ext');
        out.writeAsBytesSync(d);
        imageFiles[r - h.firstImage + 1] = out.path;
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

    final encoding = h.isKf8 ? 65001 : h.encoding;
    final ranges = splitChapters(text, encoding, toc: toc);
    final chapters = <BookChapter>[
      for (var i = 0; i < ranges.length; i++)
        BookChapter(
          name: ranges[i].$3,
          chapterId: '$i',
          tag: 'mobi',
          baseUrl: workDir,
          index: i,
          isVolume: ranges[i].$4,
          start: ranges[i].$1,
          end: ranges[i].$2,
        ),
    ];
    final title = h.exthString(503).isNotEmpty ? h.exthString(503) : (h.title.isNotEmpty ? h.title : p.basenameWithoutExtension(path));
    return {
      'name': title,
      'author': h.exthString(100),
      'intro': h.exthString(103).replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      'charset': encoding == 65001 ? 'UTF-8' : 'windows-1252',
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
      final len = raf.lengthSync();
      // 0xf13c80: start clamped to the text, end (0 = to the end) clamped to start..length
      final s = start.clamp(0, len).toInt();
      final e = (end > 0 ? end : len).clamp(s, len).toInt();
      raf.setPositionSync(s);
      data = raf.readSync(e - s);
    } finally {
      raf.closeSync();
    }
    if (data.isEmpty) return ChapterContent.fromText('章节内容为空');
    var html = charset == 'UTF-8' ? utf8.decode(data, allowMalformed: true) : latin1.decode(data);
    // `<img recindex="0007">` / `<img src="kindle:embed:0007?mime=image/jpeg">` -> `<img src="mobi-img-7">`; page breaks are
    // chapter boundaries already
    html = html.replaceAllMapped(RegExp(r'recindex="?0*(\d+)"?', caseSensitive: false), (m) => 'src="mobi-img-${m.group(1)}"');
    html = html.replaceAllMapped(RegExp(r'''(["'])kindle:embed:([0-9A-Va-v]+)[^"']*\1'''), (m) {
      final n = Kf8.embedIndex('kindle:embed:${m.group(2)}');
      return n == null ? m.group(0)! : '"mobi-img-$n"';
    });
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
