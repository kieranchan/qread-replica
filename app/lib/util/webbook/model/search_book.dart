// util/webbook/model/search_book.dart - one search/explore result (Legado `SearchBook`). Equality is by `bookUrl` (the engine removes
// duplicate results with a LinkedHashSet).
import 'book.dart';

class SearchBook extends BaseBook {
  String? tocUrl;
  int time = 0;
  int originOrder = 0;
  String? _infoHtml;
  String? tocHtml;

  SearchBook({String bookUrl = '', String origin = '', String originName = '', int type = 0, String name = '', String author = '', String? variable}) {
    this.bookUrl = bookUrl;
    this.origin = origin;
    this.originName = originName;
    this.type = type;
    this.name = name;
    this.author = author;
    this.variable = variable;
  }

  @override
  String? get infoHtml => _infoHtml;
  set infoHtml(String? v) => _infoHtml = v;

  Book toBook() {
    final b = Book(bookUrl: bookUrl, name: name, author: author, origin: origin, originName: originName, type: type, variable: variable);
    b.kind = kind;
    b.coverUrl = coverUrl;
    b.intro = intro;
    b.wordCount = wordCount;
    b.latestChapterTitle = latestChapterTitle;
    b.tocUrl = tocUrl ?? '';
    b.originOrder = originOrder;
    b.infoHtml = _infoHtml;
    b.tocHtml = tocHtml;
    return b;
  }

  @override
  bool operator ==(Object other) => other is SearchBook && other.bookUrl == bookUrl;

  @override
  int get hashCode => bookUrl.hashCode;

  @override
  String toString() => '$name/$author ($bookUrl)';
}

extension BookToSearchBook on Book {
  SearchBook toSearchBook() {
    final s = SearchBook(bookUrl: bookUrl, origin: origin, originName: originName, type: type, name: name, author: author, variable: variable);
    s.kind = kind;
    s.coverUrl = coverUrl;
    s.intro = intro;
    s.wordCount = wordCount;
    s.latestChapterTitle = latestChapterTitle;
    s.tocUrl = tocUrl;
    s.originOrder = originOrder;
    s.infoHtml = infoHtml;
    s.tocHtml = tocHtml;
    return s;
  }
}
