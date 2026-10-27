// util/chinese_utils.dart - traditional <-> simplified conversion (`java.t2s` / `java.s2t`, `toTraditional` / `toSimplified` host
// functions of the WebView bridge). The tables (chinese_tables.dart) are the ones embedded in the original app's pool strings:
// two single-character maps and two phrase maps; phrases are matched longest-first, then characters.
import 'chinese_tables.dart';

class _Table {
  final Map<int, String> chars = {};
  final Map<String, String> phrases = {};
  final Set<int> phraseStarts = {};
  int maxPhraseRunes = 1;

  _Table(String charLines, String phraseLines) {
    for (final line in charLines.split('\n')) {
      final i = line.indexOf('=');
      if (i <= 0) continue;
      final k = line.substring(0, i);
      if (k.runes.length != 1) continue;
      chars[k.runes.first] = line.substring(i + 1);
    }
    for (final line in phraseLines.split('\n')) {
      final i = line.indexOf('=');
      if (i <= 0) continue;
      final k = line.substring(0, i);
      phrases[k] = line.substring(i + 1);
      final n = k.runes.length;
      if (n > maxPhraseRunes) maxPhraseRunes = n;
      phraseStarts.add(k.runes.first);
    }
  }

  String convert(String s) {
    if (s.isEmpty) return s;
    final r = s.runes.toList();
    final sb = StringBuffer();
    var i = 0;
    while (i < r.length) {
      var matched = false;
      if (phraseStarts.contains(r[i])) {
        final maxLen = maxPhraseRunes < r.length - i ? maxPhraseRunes : r.length - i;
        for (var len = maxLen; len >= 2; len--) {
          final hit = phrases[String.fromCharCodes(r.sublist(i, i + len))];
          if (hit != null) {
            sb.write(hit);
            i += len;
            matched = true;
            break;
          }
        }
      }
      if (matched) continue;
      final c = chars[r[i]];
      if (c != null) {
        sb.write(c);
      } else {
        sb.writeCharCode(r[i]);
      }
      i++;
    }
    return sb.toString();
  }
}

abstract class ChineseUtils {
  static _Table? _s2t;
  static _Table? _t2s;

  static _Table get _toTraditionalTable => _s2t ??= _Table(s2tCharTable, s2tPhraseTable);
  static _Table get _toSimplifiedTable => _t2s ??= _Table(t2sCharTable, t2sPhraseTable);

  /// Simplified -> traditional (`java.s2t`).
  static String toTraditional(String s) => _toTraditionalTable.convert(s);

  /// Traditional -> simplified (`java.t2s`).
  static String toSimplified(String s) => _toSimplifiedTable.convert(s);

  /// Async forms kept for callers that mirror the original's `Future<String>` wrappers.
  static Future<String> convertToTraditional(String s) async => toTraditional(s);
  static Future<String> convertToSimplified(String s) async => toSimplified(s);
}
