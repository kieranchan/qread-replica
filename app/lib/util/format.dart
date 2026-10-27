// util/format.dart - text/number formatting helpers of the engine: word counts, chapter-number normalisation (`第一百二十章` ->
// `第120章`), full-width -> half-width. (The original's format.dart additionally holds the reader's text/image extraction, which
// belongs to the read-core module.)

abstract class Format {
  static const Map<String, int> _chn = {
    '零': 0, '〇': 0, '一': 1, '壹': 1, '二': 2, '贰': 2, '两': 2, '三': 3, '叁': 3, '四': 4, '肆': 4, '五': 5, '伍': 5, '六': 6,
    '陆': 6, '七': 7, '柒': 7, '八': 8, '捌': 8, '九': 9, '玖': 9, '十': 10, '拾': 10, '百': 100, '佰': 100, '千': 1000, '仟': 1000,
    '万': 10000, '亿': 100000000,
  };

  static final RegExp _numPattern = RegExp(r'(第)([\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+)([章节回集卷])');

  static String fullToHalf(String input) {
    final sb = StringBuffer();
    for (final c in input.runes) {
      if (c == 0x3000) {
        sb.write(' ');
      } else if (c >= 0xff01 && c <= 0xff5e) {
        sb.writeCharCode(c - 0xfee0);
      } else {
        sb.writeCharCode(c);
      }
    }
    return sb.toString();
  }

  /// Legado `StringUtils.chineseNumToInt`; -1 for unparsable input.
  static int chineseNumToInt(String chNum) {
    final cn = chNum.split('');
    if (cn.length > 1 && RegExp(r'^[〇一二三四五六七八九壹贰叁肆伍陆柒捌玖]+$').hasMatch(chNum)) {
      // "一零二五" digit-by-digit form
      final digits = cn.map((c) => _chn[c]!.toString()).join();
      return int.parse(digits);
    }
    var result = 0, tmp = 0, billion = 0;
    for (var i = 0; i < cn.length; i++) {
      final n = _chn[cn[i]];
      if (n == null) return -1;
      if (n == 100000000) {
        result += tmp;
        result *= n;
        billion += result;
        result = 0;
        tmp = 0;
      } else if (n == 10000) {
        result += tmp;
        result *= n;
        tmp = 0;
      } else if (n >= 10) {
        if (tmp == 0) tmp = 1;
        result += n * tmp;
        tmp = 0;
      } else {
        if (i >= 2 && i == cn.length - 1 && (_chn[cn[i - 1]] ?? 0) > 10) {
          tmp = tmp + n * _chn[cn[i - 1]]! ~/ 10;
        } else {
          tmp = tmp * 10 + n;
        }
      }
    }
    return result + tmp + billion;
  }

  static int stringToInt(String? str) {
    if (str == null) return -1;
    final t = fullToHalf(str).replaceAll(RegExp(r'\s'), '');
    return int.tryParse(t) ?? chineseNumToInt(t);
  }

  /// `java.toNumChapter`: normalises the number in a chapter title to Arabic digits.
  static String? toNumChapter(String? str) {
    if (str == null) return null;
    final m = _numPattern.firstMatch(str);
    if (m == null) return str;
    final n = stringToInt(m.group(2));
    if (n < 0) return str;
    return '${m.group(1)}$n${m.group(3)}';
  }

  /// Legado `StringUtils.wordCountFormat`: `1234` -> `1234字`, `23456` -> `2.3万字`, non-numeric text is kept.
  static String wordCountFormat(String? wc) {
    if (wc == null) return '';
    final t = wc.trim();
    final n = int.tryParse(t);
    if (n == null) return wc;
    if (n <= 0) return '';
    if (n > 10000) {
      final v = n / 10000.0;
      var s = v.toStringAsFixed(1);
      if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
      return '$s万字';
    }
    return '$n字';
  }

  /// Legado `String?.isTrue()`: blank or "null" -> [nullIsTrue]; false/no/not/0 (any case) -> false; everything else true.
  static bool isTrue(String? s, {bool nullIsTrue = false}) {
    if (s == null || s.trim().isEmpty || s == 'null') return nullIsTrue;
    return !RegExp(r'^(false|no|not|0)$', caseSensitive: false).hasMatch(s.trim());
  }
}
