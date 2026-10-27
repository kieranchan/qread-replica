// pages/read/web_book_loader.dart — the default chapter source for books from a book source (`Book.origin` = `bookSourceUrl`): the table of
// contents and the chapter text come from the book-source engine (`SourceApi`), the source JSON from `Sourcedata`.
//
// The engine returns the chapter text with paragraphs separated by newlines and images as `<img src="...">` tags; [parseContent] turns
// that into layout blocks (text paragraphs and image blocks) with offsets into the plain text.
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
  static final RegExp _img = RegExp(r'''<img[^>]*?src\s*=\s*["']([^"']+)["'][^>]*>''', caseSensitive: false);

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
      return parseContent(text);
    };
  }

  /// "购买章节": runs the source's `payAction` for [chapter].
  static Future<void> pay(Book book, BookChapter chapter) async {
    final s = await sourceOf(book);
    if (s == null) throw WebBookException('书源不存在: ${book.origin}');
    await SourceApi.payAction(s, eb.Book.fromModel(book), ec.BookChapter.fromModel(chapter, bookUrl: book.bookUrl));
  }

  /// Splits engine text into paragraphs and `<img>` blocks.
  static ChapterContent parseContent(String text) {
    if (!_img.hasMatch(text)) return ChapterContent.fromText(text);
    final blocks = <CalcuPages>[];
    for (final line in text.split('\n')) {
      var pos = 0;
      for (final m in _img.allMatches(line)) {
        final before = line.substring(pos, m.start).trim();
        if (before.isNotEmpty) blocks.add(CalcuPages.text([CLine(str: before, isfirst: true)]));
        blocks.add(CalcuPages.image(CLine(type: CLineType.image, style: CLineStyle.image, href: m.group(1)!.trim())));
        pos = m.end;
      }
      final rest = line.substring(pos).trim();
      if (rest.isNotEmpty) blocks.add(CalcuPages.text([CLine(str: rest, isfirst: true)]));
    }
    return ChapterContent.fromBlocks(blocks);
  }
}
