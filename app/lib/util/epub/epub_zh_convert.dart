// util/epub/epub_zh_convert.dart — simplified <-> traditional Chinese conversion for EPUB chapters (original: `_ZhDict` class 1418 with a
// per-direction dictionary cache `_cache` 0x5318 and a `(String, String)` filler closure 0x274c90). The conversion dictionary and
// `ChineseUtils` belong to the engine area (`util/chinese_utils.dart`); the reader only needs a hook, which the app wires at start-up:
//   EpubZhConvert.converter = ChineseUtils.convert;
// Without a converter the text is returned unchanged.
class EpubZhConvert {
  /// `(text, toTraditional)`.
  static String Function(String text, bool toTraditional)? converter;

  static String convert(String text, {required bool toTraditional}) {
    final c = converter;
    if (c == null || text.isEmpty) return text;
    return c(text, toTraditional);
  }
}
