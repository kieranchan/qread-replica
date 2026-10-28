// read/model/mykey.dart — key of a laid-out chapter in the page cache.
// The original class 1485 `Mykey` (3 slots) is the scroll list's item key: created by the list controller (0x25096c / 0x2509f0) as
// (String '' , LabeledGlobalKey<State>, bool false) to measure an item's widget. This port's scroll view does not measure items that
// way, so the name holds the layout cache key (book, chapter, layout signature) instead.
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
