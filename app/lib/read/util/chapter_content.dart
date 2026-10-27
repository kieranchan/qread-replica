// read/util/chapter_content.dart — what a chapter looks like to the layout engine: the body text plus its paragraph / image
// blocks. All offsets in the blocks index [ChapterContent.text], so a reading position ("character n of the chapter") stays
// valid when the font, the page size or the number of columns changes.
import '../model/line.dart';
import '../model/page.dart';

class ChapterContent {
  /// The body text (paragraphs joined by `\n`; images take no characters).
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

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0d || c == 0x3000 || c == 0xa0 || c == 0xfeff || c == 0x200b;

  /// Number of source characters in the blocks (for progress fractions).
  int get textLength => text.length;
}
