// read/txt/text_file.dart — local TXT books (original: `abstract class TextFile`, with `_getContent(Map)` running in an isolate;
// 0x2a7dd0, helpers 0x258a50 .. 0x259228 / 0xf14090).
//
// Import: detect the charset (BOM, UTF-16 NUL pattern, strict UTF-8 check, else GBK), split the file into lines at the byte
// level, find chapter titles with the user's `TxtTocRule`s and describe every chapter by a byte range of the *file*
// (`BookChapter.start` / `BookChapter.end`; exclusive). Reading a chapter later decodes just that range, so a 20 MB novel
// never has to be held in memory by the reader. If no rule finds at least [minRuleMatches] titles the file is cut into
// pieces of about [fixedChars] characters at line boundaries (the "no TOC rule" fallback).
//
// What the original does that this port approximates: rule selection (here: first enabled rule, in list order, with at least
// two matching lines), volume detection ([isVolumeTitle]) and the default rule set ([defaultRules]; the user's rules come from
// data/txtrule). Rules are applied to single lines (every TOC rule of the original app is anchored `^..$`);
// patterns spanning lines are not supported. TODO(asm 0x258c48): exact rule-selection order of the original.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/bookchapter.dart';
import '../../models/txt_toc_rule.dart';
import '../api/read_file_store.dart';
import 'text_encoding.dart';

class TextParseResult {
  final String name;
  final String author;
  final String charset;
  final int byteLength;
  final String ruleName; // '' when the fixed-size fallback was used
  final List<BookChapter> chapters;

  const TextParseResult({
    required this.name,
    required this.author,
    required this.charset,
    required this.byteLength,
    required this.ruleName,
    required this.chapters,
  });
}

abstract class TextFile {
  /// Chapter size of the fallback split (characters, measured as `fixedChars * bytesPerChar` bytes).
  static const int fixedChars = 10000;

  /// A rule must find at least this many title lines to be used.
  static const int minRuleMatches = 2;

  /// Common Chinese web-novel chapter patterns, used when the caller has no rule list (the user's list lives in data/txtrule).
  static final List<TxtTocRule> defaultRules = [
    TxtTocRule(
      name: '目录(去空白)',
      rule: r'^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第?[零〇一二两三四五六七八九十百千万0-9]{1,8}[章节回卷集部篇]).{0,30}$',
      isEnabled: true,
    ),
    TxtTocRule(name: '数字标题', rule: r'^[ 　\t]{0,4}[0-9]{1,5}[ 　\t、.．].{1,30}$', isEnabled: true),
    TxtTocRule(name: 'Chapter', rule: r'^[ 　\t]{0,4}(?i)(?:chapter|section)[ 　\t]*[0-9ivxlc]+.{0,30}$', isEnabled: true),
  ];

  // ---------------------------------------------------------------- import

  /// Parses [file]. Runs in an isolate (the original does the heavy part in `compute`).
  static Future<TextParseResult> parse(
    File file, {
    List<TxtTocRule>? rules,
    String? charset,
    String? bookUrl,
  }) async {
    final path = file.path;
    final ruleMaps = (rules ?? defaultRules).where((r) => r.isEnabled && r.rule.isNotEmpty).map((r) => r.toJson()).toList();
    final map = await ReadIsolate.run(() => _parseSync(path, ruleMaps, charset ?? '', bookUrl ?? path));
    return TextParseResult(
      name: map['name'] as String,
      author: map['author'] as String,
      charset: map['charset'] as String,
      byteLength: map['length'] as int,
      ruleName: map['rule'] as String,
      chapters: (map['chapters'] as List).map((e) => BookChapter.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  static Map<String, dynamic> _parseSync(String path, List<Map<String, dynamic>> ruleMaps, String charsetHint, String bookUrl) {
    final bytes = File(path).readAsBytesSync();
    final enc = TextEncodings.detect(bytes, hint: charsetHint);
    final rules = ruleMaps.map(TxtTocRule.fromJson).toList();
    final split = splitBytes(bytes, enc, rules, bookUrl: bookUrl);
    final na = guessNameAuthor(p.basenameWithoutExtension(path));
    return {
      'name': na.$1,
      'author': na.$2,
      'charset': enc.charsetName,
      'length': bytes.length,
      'rule': split.ruleName,
      'chapters': split.chapters.map((c) => c.toJson()).toList(),
    };
  }

  /// The chapter split itself (pure, synchronous; used by [parse] and the tests).
  static ({String ruleName, List<BookChapter> chapters}) splitBytes(
    Uint8List bytes,
    TextEncodingInfo enc,
    List<TxtTocRule> rules, {
    String bookUrl = '',
    int fixed = fixedChars,
  }) {
    final dataStart = enc.bomLength;
    final dataEnd = bytes.length - ((bytes.length - dataStart) % enc.unit);
    if (dataEnd <= dataStart) return (ruleName: '', chapters: <BookChapter>[]);

    final starts = _lineStarts(bytes, enc, dataStart, dataEnd);
    final nLines = starts.length - 1;

    // Candidate title lines: short, non-blank.
    final maxLineBytes = 400 * enc.unit;
    final candLine = <int>[];
    final candText = <String>[];
    for (var i = 0; i < nLines; i++) {
      final len = starts[i + 1] - starts[i];
      if (len > maxLineBytes) continue;
      final t = TextEncodings.decode(bytes, enc.encoding, starts[i], starts[i + 1]).replaceAll(RegExp(r'[\r\n]+$'), '');
      if (t.trim().isEmpty) continue;
      candLine.add(i);
      candText.add(t);
    }

    for (final rule in rules) {
      final re = toDartRegExp(rule.rule);
      if (re == null) continue;
      final hits = <int>[]; // indexes into cand*
      for (var k = 0; k < candText.length; k++) {
        if (re.hasMatch(candText[k])) hits.add(k);
      }
      if (hits.length < minRuleMatches) continue;
      return (
        ruleName: rule.name,
        chapters: _chaptersFromTitles(bytes, enc, starts, [for (final k in hits) (candLine[k], candText[k])], dataStart, dataEnd, bookUrl),
      );
    }
    return (ruleName: '', chapters: _fixedChapters(bytes, enc, starts, dataStart, dataEnd, bookUrl, fixed));
  }

  static List<int> _lineStarts(Uint8List b, TextEncodingInfo enc, int from, int to) {
    final starts = <int>[from];
    if (enc.unit == 1) {
      var i = from;
      while (true) {
        final nl = b.indexOf(0x0A, i);
        if (nl < 0 || nl >= to) break;
        starts.add(nl + 1);
        i = nl + 1;
      }
    } else {
      final le = enc.encoding == TextEncoding.utf16le;
      for (var i = from; i + 1 < to; i += 2) {
        final isNl = le ? (b[i] == 0x0A && b[i + 1] == 0x00) : (b[i] == 0x00 && b[i + 1] == 0x0A);
        if (isNl) starts.add(i + 2);
      }
    }
    if (starts.last != to) starts.add(to);
    return starts;
  }

  static List<BookChapter> _chaptersFromTitles(
    Uint8List bytes,
    TextEncodingInfo enc,
    List<int> starts,
    List<(int, String)> titles,
    int dataStart,
    int dataEnd,
    String bookUrl,
  ) {
    final out = <BookChapter>[];
    void add(String name, int s, int e, {required bool titled}) {
      final i = out.length;
      out.add(BookChapter(
        name: name,
        chapterId: '$i',
        tag: titled ? 't' : '',
        baseUrl: bookUrl,
        isVolume: titled && isVolumeTitle(name),
        index: i,
        start: s,
        end: e,
      ));
    }

    final firstStart = starts[titles.first.$1];
    if (firstStart > dataStart && _hasText(bytes, enc, dataStart, firstStart)) {
      add('前言', dataStart, firstStart, titled: false);
    }
    for (var k = 0; k < titles.length; k++) {
      final s = starts[titles[k].$1];
      final e = k + 1 < titles.length ? starts[titles[k + 1].$1] : dataEnd;
      add(_cleanTitle(titles[k].$2), s, e, titled: true);
    }
    return out;
  }

  static List<BookChapter> _fixedChapters(Uint8List bytes, TextEncodingInfo enc, List<int> starts, int dataStart, int dataEnd, String bookUrl, int fixed) {
    final perChar = enc.encoding == TextEncoding.utf8 ? 3 : 2;
    final target = fixed * perChar;
    final out = <BookChapter>[];
    var segStart = dataStart;
    void close(int end) {
      final i = out.length;
      out.add(BookChapter(name: '第${i + 1}章', chapterId: '$i', baseUrl: bookUrl, index: i, start: segStart, end: end));
      segStart = end;
    }

    for (var i = 0; i + 1 < starts.length; i++) {
      final le = starts[i + 1];
      // a line far longer than the target (no line breaks in the file): cut it at character boundaries
      while (le - segStart > target * 2) {
        close(_safeCut(bytes, enc, segStart, target, le));
      }
      if (le - segStart >= target) close(le);
    }
    if (segStart < dataEnd) close(dataEnd);
    return out;
  }

  /// A cut position `>= from + target` (or the end) that does not split a character.
  static int _safeCut(Uint8List b, TextEncodingInfo enc, int from, int target, int to) {
    var cut = from + target;
    if (cut >= to) return to;
    switch (enc.encoding) {
      case TextEncoding.utf8:
        while (cut < to && (b[cut] & 0xC0) == 0x80) {
          cut++;
        }
      case TextEncoding.gbk:
        // walk from the start so that lead/trail bytes stay paired
        var i = from;
        while (i < cut) {
          i += b[i] >= 0x81 && i + 1 < to ? 2 : 1;
        }
        cut = i;
      case TextEncoding.utf16le:
      case TextEncoding.utf16be:
        cut = from + ((cut - from) ~/ 2) * 2;
        final hi = enc.encoding == TextEncoding.utf16le ? b[cut - 1] : b[cut - 2];
        if (hi >= 0xD8 && hi <= 0xDB && cut + 2 <= to) cut += 2; // do not split a surrogate pair
    }
    return cut > to ? to : cut;
  }

  static bool _hasText(Uint8List bytes, TextEncodingInfo enc, int s, int e) {
    final end = e - s > 4000 ? s + 4000 : e;
    return TextEncodings.decode(bytes, enc.encoding, s, end - ((end - s) % enc.unit)).trim().isNotEmpty;
  }

  static String _cleanTitle(String line) => line.replaceAll(RegExp(r'[\s　]+'), ' ').trim();

  /// "第三卷 xxx" / "卷三" / "第2部" (no 章/节/回): the chapter is a volume heading.
  static bool isVolumeTitle(String title) {
    final t = title.trim();
    if (RegExp(r'[章节回]').hasMatch(t.length > 12 ? t.substring(0, 12) : t)) return false;
    return RegExp(r'^(?:第\s*[零〇一二两三四五六七八九十百千万0-9]+\s*[卷部集篇]|[卷篇部]\s*[零〇一二两三四五六七八九十百千万0-9]+|卷\s*[零〇一二两三四五六七八九十百千万0-9]*)').hasMatch(t);
  }

  /// Java-flavoured TOC rule -> Dart [RegExp] (leading `(?i)`/`(?s)`/`(?m)` flag groups, mid-pattern `(?i)` applied globally);
  /// null when the pattern cannot be compiled (possessive quantifiers, unsupported classes).
  static RegExp? toDartRegExp(String rule) {
    var src = rule;
    var ci = false;
    var dotAll = false;
    final flagGroup = RegExp(r'\(\?([imsu]+)\)');
    for (final m in flagGroup.allMatches(rule)) {
      final f = m.group(1)!;
      if (f.contains('i')) ci = true;
      if (f.contains('s')) dotAll = true;
    }
    src = src.replaceAll(flagGroup, '');
    try {
      return RegExp(src, multiLine: true, caseSensitive: !ci, dotAll: dotAll);
    } catch (_) {
      try {
        return RegExp(src, multiLine: true, caseSensitive: !ci, dotAll: dotAll, unicode: true);
      } catch (_) {
        return null;
      }
    }
  }

  /// File name -> (book name, author). Understands `《书名》作者：某某`, `书名 作者：某某` and `书名 by 某某`.
  static (String, String) guessNameAuthor(String fileBaseName) {
    final base = fileBaseName.trim();
    var m = RegExp(r'^《(.+?)》\s*(?:[-_\s]*(?:作者|by)[:：\s]*)?(.*)$', caseSensitive: false).firstMatch(base);
    if (m != null) return (m.group(1)!.trim(), (m.group(2) ?? '').trim());
    m = RegExp(r'^(.+?)[\s_\-]*(?:作者|by)[:：\s]*(.+)$', caseSensitive: false).firstMatch(base);
    if (m != null) return (m.group(1)!.trim(), m.group(2)!.trim());
    return (base, '');
  }

  // ---------------------------------------------------------------- reading

  /// Text of one chapter (original `_getContent(Map)`; keys: `path`, `start`, `end`, `charset`, `name`, `tag`). Line endings are
  /// normalised to `\n`; when the chapter starts with its title line (`tag == 't'`) that line is dropped.
  static Future<String> getContent(Map<String, dynamic> args) => ReadIsolate.run(() => getContentSync(args));

  static String getContentSync(Map<String, dynamic> args) {
    final path = args['path'] as String;
    final start = args['start'] as int;
    final end = args['end'] as int;
    final enc = TextEncodings.fromName(args['charset'] as String?)?.encoding ?? TextEncoding.utf8;
    final raf = File(path).openSync();
    Uint8List data;
    try {
      raf.setPositionSync(start);
      data = raf.readSync(end - start);
    } finally {
      raf.closeSync();
    }
    var text = TextEncodings.decode(data, enc);
    if (text.startsWith('﻿')) text = text.substring(1);
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if ((args['tag'] as String? ?? '') == 't') {
      final nl = text.indexOf('\n');
      text = nl < 0 ? '' : text.substring(nl + 1);
    }
    return text;
  }

  /// Convenience: chapter text for a chapter produced by [parse].
  static Future<String> readChapter(File file, BookChapter chapter, String charset) => getContent({
        'path': file.path,
        'start': chapter.start,
        'end': chapter.end,
        'charset': charset,
        'name': chapter.name,
        'tag': chapter.tag,
      });

  /// Whole decoded file (small files, tests).
  static String decodeAll(Uint8List bytes, {String? charset}) {
    final enc = TextEncodings.detect(bytes, hint: charset);
    return TextEncodings.decode(bytes, enc.encoding, enc.bomLength);
  }

  /// JSON helper for callers that keep parse results in the item store.
  static String chaptersToJson(List<BookChapter> chapters) => jsonEncode(chapters.map((c) => c.toJson()).toList());
}
