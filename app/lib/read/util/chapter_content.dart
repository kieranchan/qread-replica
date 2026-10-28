// read/util/chapter_content.dart — what a chapter looks like to the layout engine: the body text plus its paragraph / image
// blocks. All offsets in the blocks index [ChapterContent.text], so a reading position ("character n of the chapter") stays
// valid when the font, the page size or the number of columns changes.
//
// Images take no characters. An image block (`CalcuPages.image`) stands on its own line; an image run inside a text block (`CLine` of
// type image, `str` '') is an inline image of that paragraph: a 段评 bubble `dp:N` or any other image on the same line as text in a
// book source's chapter (WebBookLoader.parseContent), laid out in the line like a character (CalculateChapter). Its `start` / `end` are
// both the offset of the text that follows it.
import '../model/line.dart';
import '../model/page.dart';

class ChapterContent {
  /// The body text (paragraphs joined by `\n`; images, inline ones too, take no characters).
  final String text;
  final List<CalcuPages> blocks;

  const ChapterContent(this.text, this.blocks);

  static const ChapterContent empty = ChapterContent('', <CalcuPages>[]);

  int get length => text.length;

  bool get isEmpty => blocks.isEmpty;

  /// Plain text (TXT chapters, source-book chapters): one paragraph per non-blank line, leading / trailing white space
  /// (including full-width spaces and the `\t` indents of web novels) trimmed. Offsets refer to [text] as given.
  factory ChapterContent.fromText(String text) {
    final blocks = <CalcuPages>[];
    var pos = 0;
    final n = text.length;
    while (pos <= n) {
      var nl = text.indexOf('\n', pos);
      if (nl < 0) nl = n;
      var s = pos;
      var e = nl;
      while (s < e && _isSpace(text.codeUnitAt(s))) {
        s++;
      }
      while (e > s && _isSpace(text.codeUnitAt(e - 1))) {
        e--;
      }
      if (e > s) {
        blocks.add(CalcuPages.text([CLine(str: text.substring(s, e), start: s, end: e, isfirst: true)]));
      }
      pos = nl + 1;
    }
    return ChapterContent(text, blocks);
  }

  /// Re-derives text and offsets from the runs of [blocks] (after the strings of the runs were edited, e.g. by replace rules).
  /// Paragraphs are joined by `\n`; image runs sit at the current end of the text. Paragraphs that became empty are dropped; the inline
  /// images of a paragraph left without text become image blocks.
  factory ChapterContent.fromBlocks(List<CalcuPages> blocks) {
    final sb = StringBuffer();
    final out = <CalcuPages>[];
    for (final b in blocks) {
      if (b.isImage) {
        final r = b.runs.first;
        r.start = sb.length;
        r.end = sb.length;
        out.add(b);
        continue;
      }
      final runs = b.runs.where((r) => r.isImage || r.str.isNotEmpty).toList();
      if (runs.isEmpty) continue;
      if (runs.every((r) => r.isImage)) {
        for (final r in runs) {
          r
            ..start = sb.length
            ..end = sb.length
            ..prefix = ''
            ..isfirst = true;
          out.add(CalcuPages.image(r));
        }
        continue;
      }
      if (out.isNotEmpty) sb.write('\n');
      var pos = sb.length;
      for (var i = 0; i < runs.length; i++) {
        final r = runs[i];
        r.start = pos;
        if (!r.isImage) {
          pos += r.str.length;
          sb.write(r.str);
        }
        r.end = pos;
        r.isfirst = i == 0;
      }
      out.add(CalcuPages.text(runs));
    }
    return ChapterContent(sb.toString(), out);
  }

  /// The content without the images [drop] picks, image blocks and inline image runs alike (显示段评 off drops the `dp:` bubbles).
  /// Text and offsets stay the same, images take no characters. Returns this content when nothing is dropped.
  ChapterContent withoutImages(bool Function(CLine image) drop) {
    var changed = false;
    final kept = <CalcuPages>[];
    for (final b in blocks) {
      if (b.isImage) {
        if (b.runs.isNotEmpty && drop(b.runs.first)) {
          changed = true;
        } else {
          kept.add(b);
        }
        continue;
      }
      if (!b.runs.any((r) => r.isImage && drop(r))) {
        kept.add(b);
        continue;
      }
      changed = true;
      kept.add(CalcuPages.text([for (final r in b.runs) if (!(r.isImage && drop(r))) r]));
    }
    return changed ? ChapterContent.fromBlocks(kept) : this;
  }

  /// True when every block is a single plain-text run (TXT / source-book text): the content can be cached and rewritten as text
  /// (a paragraph with an inline image has two runs, so it is not plain).
  bool get isPlainText => blocks.every((b) => !b.isImage && b.runs.length == 1 && b.runs.first.style.isEmpty);

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0d || c == 0x3000 || c == 0xa0 || c == 0xfeff || c == 0x200b;

  /// Number of source characters in the blocks (for progress fractions).
  int get textLength => text.length;
}
