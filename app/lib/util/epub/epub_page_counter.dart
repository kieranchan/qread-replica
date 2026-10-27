// util/epub/epub_page_counter.dart — counts the pages of every chapter of a book for the current page size and style, so that the reader can
// show "page n of N" / a whole-book progress for EPUB and other multi-chapter local books.
//
// Original (class 1422 `EpubPageCounter`, singleton `instance` 0x4e08, `updateSharedConfig` 0xf2a744, `_RulePack` 0x30 bytes with the
// `esc` / `add` / `addRaw` closures 0x26e508 / 0x26e364 / 0x26e1c4): a hidden WebView renders each EPUB chapter with epub.js using the reader's
// CSS and replace/highlight rules, then counts columns. This port has no WebView: the count comes from the same [CalculateChapter] engine
// that draws the pages (so the number is exact for what the user sees). `_RulePack` is kept as [RulePack] (the fingerprint of the replace /
// highlight rules in force; a change invalidates the counts).
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../models/highlight_rule.dart';
import '../../models/replacerule.dart';
import '../../read/api/calculate/calculate_hapter.dart';
import '../../read/api/read_file_store.dart';
import '../../read/model/mykey.dart';
import '../../read/setting/read_layout_style.dart';
import '../../read/util/chapter_content.dart';

/// The rules that influence chapter text. Only their fingerprint matters to the counter.
class RulePack {
  final List<ReplaceRule> replace;
  final List<HighlightRule> highlight;

  const RulePack({this.replace = const [], this.highlight = const []});

  static const RulePack empty = RulePack();

  /// `RegExp.escape` as in the original's `esc` closure.
  static String esc(String s) => RegExp.escape(s);

  String get signature => ReadFileStore.md5Hex(jsonEncode({
        'r': replace.where((r) => r.isEnabled).map((r) => r.toJson()).toList(),
        'h': highlight.where((r) => r.isEnabled).map((r) => r.toJson()).toList(),
      }));
}

typedef ChapterContentLoader = Future<ChapterContent> Function(BookChapter chapter);

class EpubPageCounter {
  EpubPageCounter._();

  static final EpubPageCounter instance = EpubPageCounter._();

  Size _size = const Size(360, 640);
  ReadLayoutStyle _style = const ReadLayoutStyle();
  ImageSizeResolver? _imageSizeOf;
  RulePack _rules = RulePack.empty;
  String _config = '';

  final Map<Mykey, int> _counts = {};

  /// Sets the page size / style / rules used for counting (original `updateSharedConfig`). Counts of an older configuration are dropped.
  void updateSharedConfig({required Size size, required ReadLayoutStyle style, RulePack rules = RulePack.empty, ImageSizeResolver? imageSizeOf}) {
    final sig = '${size.width}x${size.height}|${style.signature}|${rules.signature}';
    _size = size;
    _style = style;
    _rules = rules;
    _imageSizeOf = imageSizeOf;
    if (sig != _config) {
      _counts.clear();
      _config = sig;
    }
  }

  RulePack get rules => _rules;

  Mykey _key(Book book, int chapterIndex) => Mykey(book.bookUrl, chapterIndex, _config);

  /// Cached page count of a chapter, or null when it was not counted for the current configuration.
  int? cachedCount(Book book, int chapterIndex) => _counts[_key(book, chapterIndex)];

  /// Pages of one chapter (counted once per configuration).
  Future<int> countChapter(Book book, BookChapter chapter, ChapterContent content) async {
    final key = _key(book, chapter.index);
    final hit = _counts[key];
    if (hit != null) return hit;
    final engine = CalculateChapter(style: _style, imageSizeOf: _imageSizeOf);
    final pages = await engine.calculate(size: _size, blocks: content.blocks, title: chapter.name, isVolume: chapter.isVolume);
    _counts[key] = pages.length;
    return pages.length;
  }

  /// Counts every chapter, loading content through [loader]; [onProgress] gets (done, total). Chapters that fail to load count as one page.
  Future<List<int>> countBook(
    Book book,
    List<BookChapter> chapters,
    ChapterContentLoader loader, {
    void Function(int done, int total)? onProgress,
  }) async {
    final out = <int>[];
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      var n = cachedCount(book, c.index);
      if (n == null) {
        try {
          n = await countChapter(book, c, await loader(c));
        } catch (_) {
          n = 1;
        }
      }
      out.add(n);
      onProgress?.call(i + 1, chapters.length);
    }
    return out;
  }

  /// Page number (0-based) in the whole book of page [pageInChapter] of chapter [chapterIndex].
  static int globalPage(List<int> counts, int chapterIndex, int pageInChapter) {
    var n = 0;
    for (var i = 0; i < chapterIndex && i < counts.length; i++) {
      n += counts[i];
    }
    return n + pageInChapter;
  }

  /// Inverse of [globalPage]: (chapter index, page in chapter).
  static (int, int) locate(List<int> counts, int global) {
    var rest = global;
    for (var i = 0; i < counts.length; i++) {
      if (rest < counts[i]) return (i, rest);
      rest -= counts[i];
    }
    return (counts.isEmpty ? 0 : counts.length - 1, counts.isEmpty ? 0 : counts.last - 1);
  }

  static int total(List<int> counts) => counts.fold(0, (a, b) => a + b);

  void clear() => _counts.clear();
}
