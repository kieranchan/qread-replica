// read/model/mykey.dart — key of a laid-out chapter in the page cache (class 1485 `Mykey`, 3 slots).
// TODO(asm class 1485): the original's slots are not named; the natural key of a layout is (book, chapter, layout signature).
class Mykey {
  final String bookUrl;
  final int chapterIndex;

  /// Everything that changes the layout: page size + style ([ReadLayoutStyle.signature] + size). Different signature =
  /// different key, so a font-size change never reuses stale pages.
  final String signature;

  const Mykey(this.bookUrl, this.chapterIndex, this.signature);

  @override
  bool operator ==(Object other) =>
      other is Mykey && other.bookUrl == bookUrl && other.chapterIndex == chapterIndex && other.signature == signature;

  @override
  int get hashCode => Object.hash(bookUrl, chapterIndex, signature);

  @override
  String toString() => 'Mykey($bookUrl, $chapterIndex, $signature)';
}
