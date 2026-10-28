// pages/read/web_book_loader.dart — the default chapter source for books from a book source (`Book.origin` = `bookSourceUrl`): the table of
// contents and the chapter text come from the book-source engine (`SourceApi`), the source JSON from `Sourcedata`.
//
// The engine returns the chapter text with paragraphs separated by newlines and images as `<img src="...">` tags; [parseContent] turns
// that into layout blocks (text paragraphs, with the images of their line inline, and image blocks) with offsets into the plain text.
import '../../api/sourceapi.dart';
import '../../data/source.dart';
import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../read/api/readapi.dart';
import '../../read/model/line.dart';
import '../../read/model/page.dart';
import '../../read/util/chapter_content.dart';
import '../../util/webbook/model/book.dart' as eb;
import '../../util/webbook/model/book_chapter.dart' as ec;
import '../../util/webbook/model/book_source.dart';

class WebBookException implements Exception {
  final String message;
  const WebBookException(this.message);
  @override
  String toString() => message;
}

abstract class WebBookLoader {
  /// An `<img>` tag; the address in group 1 (double quotes) or 2 (single quotes). The value runs to the matching quote, so the JSON of
  /// `src="dp:1,{'js':'…'}"` (the source help's form, 0x95fb18) stays whole, and a JSON with double quotes is taken up to its `}` as
  /// HtmlFormatter.formatKeepImg writes it (the original switches to `src="(.*)"` when the tag holds `{…}`, 0xec0dd4).
  static final RegExp _img = RegExp(r'''<img[^>]*?\bsrc\s*=\s*(?:"([^"]*(?:"[^>]+\})?)"|'([^']*)')[^>]*>''', caseSensitive: false);

  /// The engine's source of [book], null when the source is not installed.
  static Future<BookSource?> sourceOf(Book book) async {
    try {
      await Sourcedata.load();
    } catch (_) {}
    final m = Sourcedata.byUrl(book.origin);
    return m == null ? null : BookSource.fromJson(Map<String, dynamic>.from(m));
  }

  /// The table of contents (reversed when `Book.reverseCatalog` is set; indexes renumbered in reading order).
  static Future<List<BookChapter>> chapters(Book book, {BookSource? source}) async {
    final s = source ?? await sourceOf(book);
    if (s == null) throw WebBookException('书源不存在: ${book.origin}');
    final engineBook = eb.Book.fromModel(book);
    if (book.tocUrl.isEmpty) await SourceApi.bookInfo(s, engineBook);
    final list = await SourceApi.chapters(s, engineBook);
    final models = [for (final c in list) c.toModel()];
    final ordered = book.reverseCatalog ? models.reversed.toList() : models;
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].index = i;
    }
    if (ordered.isNotEmpty) {
      book.totalChapterNum = ordered.length;
      book.latestChapterTitle = ordered.last.name;
    }
    return ordered;
  }

  /// A [ChapterLoader] that fetches chapter text through the engine.
  static ChapterLoader loaderFor(Book book, {BookSource? source}) {
    BookSource? cached = source;
    return (chapter) async {
      final s = cached ??= await sourceOf(book);
      if (s == null) throw WebBookException('书源不存在: ${book.origin}');
      final text = await SourceApi.content(s, eb.Book.fromModel(book), ec.BookChapter.fromModel(chapter, bookUrl: book.bookUrl));
      return parseContent(text, inline: book.type_ != 2); // 2 = BookType.comic
    };
  }

  /// "购买章节": runs the source's `payAction` for [chapter].
  static Future<void> pay(Book book, BookChapter chapter) async {
    final s = await sourceOf(book);
    if (s == null) throw WebBookException('书源不存在: ${book.origin}');
    await SourceApi.payAction(s, eb.Book.fromModel(book), ec.BookChapter.fromModel(chapter, bookUrl: book.bookUrl));
  }

  /// Splits engine text into paragraphs and images. The original keeps the images of a line inside that line's `Line`
  /// (newread/util/format.dart `_extractTextAndImgUrlsIsolate` 0x23c46c -> 0x23d118: CLines of type 1 between the text CLines) and its
  /// source help says so (书源规则说明 0x95fb18: "和文字同行的图片会默认识别为段评，小图显示，其他图片会正常显示"). So an `<img>` on a line that
  /// also has text is an inline image run of that paragraph, at its place in the text (a `dp:N` 段评 bubble at the end of the paragraph
  /// in the usual case); a line of images only gives image blocks. Only the ends of a line are trimmed, as before.
  /// [inline] false keeps every image a block (comics: the original's image-only pass, 0x23c588, and the comic view reads image blocks).
  static ChapterContent parseContent(String text, {bool inline = true}) {
    if (!_img.hasMatch(text)) return ChapterContent.fromText(text);
    CLine image(RegExpMatch m) => CLine(type: CLineType.image, style: CLineStyle.image, href: (m.group(1) ?? m.group(2)!).trim());
    final blocks = <CalcuPages>[];
    for (final line in text.split('\n')) {
      final matches = _img.allMatches(line).toList();
      if (inline && matches.isNotEmpty && line.replaceAll(_img, '').trim().isNotEmpty) {
        final runs = <CLine>[];
        var pos = 0;
        for (final m in matches) {
          if (m.start > pos) runs.add(CLine(str: line.substring(pos, m.start)));
          runs.add(image(m));
          pos = m.end;
        }
        if (pos < line.length) runs.add(CLine(str: line.substring(pos)));
        if (!runs.first.isImage) runs.first.str = runs.first.str.trimLeft();
        if (!runs.last.isImage) runs.last.str = runs.last.str.trimRight();
        blocks.add(CalcuPages.text(runs));
        continue;
      }
      var pos = 0;
      for (final m in matches) {
        final before = line.substring(pos, m.start).trim();
        if (before.isNotEmpty) blocks.add(CalcuPages.text([CLine(str: before, isfirst: true)]));
        blocks.add(CalcuPages.image(image(m)));
        pos = m.end;
      }
      final rest = line.substring(pos).trim();
      if (rest.isNotEmpty) blocks.add(CalcuPages.text([CLine(str: rest, isfirst: true)]));
    }
    return ChapterContent.fromBlocks(blocks);
  }
}
