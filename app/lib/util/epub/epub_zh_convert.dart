// util/epub/epub_zh_convert.dart — simplified <-> traditional Chinese conversion for EPUB chapters (original: `_ZhDict` class 1418 with a
// per-direction dictionary cache `_cache` 0x5318 and a `(String, String)` filler closure 0x274c90). The dictionaries are the engine's
// `ChineseUtils` (`util/chinese_utils.dart`, used directly like the original's 0xe8f868 / 0xe8fdd4); tests may swap [converter].
import '../chinese_utils.dart';

class EpubZhConvert {
  /// `(text, toTraditional)`.
  static String Function(String text, bool toTraditional)? converter = _chineseUtils;

  static String _chineseUtils(String text, bool toTraditional) =>
      toTraditional ? ChineseUtils.toTraditional(text) : ChineseUtils.toSimplified(text);

  static String convert(String text, {required bool toTraditional}) {
    final c = converter;
    if (c == null || text.isEmpty) return text;
    return c(text, toTraditional);
  }
}
