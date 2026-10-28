// read/util/replace_rules.dart — applying the user's replace / purify rules (`ReplaceRule`) to chapter text and titles.
//
// Original: ReadApi 0xed6e9c ("替换净化"), the filter closures 0x254370 (rules for titles: enabled && scopeTitle && in scope) and 0x2a7178
// (rules for content: enabled && scopeContent && in scope), 0x95a088 / 0x959f6c (enabled-with-pattern filter + copy). A rule is in scope when
// its `scope` is empty or contains the book's name or origin, and its `excludeScope` neither contains the name nor the origin
// (String.contains, as in the original). Rules run in `ruleorder`; a rule that takes longer than its `timeoutMillisecond` is switched
// off for the rest of the session ("规则超时已停用").
// 0x254370 reads ReplaceRule isEnabled (0x4f), scopeTitle (0x37), scope (0x2f), excludeScope (0x47) and Book origin (0xc7) / name (0xf):
// scope empty or containing the origin or the name, excludeScope empty or containing neither.
import '../../models/book.dart';
import '../../models/replacerule.dart';

class ReplaceRuleEngine {
  /// Rules that timed out in this session (by id, else pattern).
  static final Set<String> disabled = {};

  static String keyOf(ReplaceRule r) => r.id.isNotEmpty ? r.id : r.pattern;

  /// True when [r] applies to [book] for titles ([title] true) or content.
  static bool applies(ReplaceRule r, Book book, {required bool title}) {
    if (!r.isEnabled || r.pattern.isEmpty) return false;
    if (title ? !r.scopeTitle : !r.scopeContent) return false;
    final scope = r.scope;
    final inScope = scope.isEmpty || scope.contains(book.origin) || scope.contains(book.name);
    if (!inScope) return false;
    final ex = r.excludeScope;
    if (ex.isEmpty) return true;
    return !(ex.contains(book.origin) || ex.contains(book.name));
  }

  /// The rules to run for [book], in `ruleorder`.
  static List<ReplaceRule> select(Iterable<ReplaceRule> rules, Book book, {required bool title}) {
    final out = rules.where((r) => applies(r, book, title: title)).toList();
    out.sort((a, b) => a.ruleorder.compareTo(b.ruleorder));
    return out;
  }

  /// Runs [rules] over [text]. Rules that fail to compile are skipped; rules that exceed their timeout are added to [disabled] and
  /// reported through [onTimeout].
  static String apply(String text, List<ReplaceRule> rules, {void Function(ReplaceRule rule)? onTimeout}) {
    var out = text;
    for (final r in rules) {
      if (disabled.contains(keyOf(r))) continue;
      final sw = Stopwatch()..start();
      try {
        if (r.isRegex) {
          final re = RegExp(r.pattern, multiLine: true);
          out = out.replaceAllMapped(re, (m) => expand(r.replacement, m));
        } else {
          out = out.replaceAll(r.pattern, r.replacement);
        }
      } catch (_) {
        continue;
      }
      final limit = r.timeoutMillisecond > 0 ? r.timeoutMillisecond : 3000;
      if (sw.elapsedMilliseconds > limit) {
        disabled.add(keyOf(r));
        onTimeout?.call(r);
      }
    }
    return out;
  }

  /// Java-style replacement text: `$1` / `${1}` group references, `\$` and `\\` escapes.
  static String expand(String replacement, Match m) {
    if (!replacement.contains(r'$') && !replacement.contains(r'\')) return replacement;
    final sb = StringBuffer();
    for (var i = 0; i < replacement.length; i++) {
      final c = replacement[i];
      if (c == r'\' && i + 1 < replacement.length) {
        sb.write(replacement[++i]);
      } else if (c == r'$' && i + 1 < replacement.length) {
        var j = i + 1;
        final braces = replacement[j] == '{';
        if (braces) j++;
        final start = j;
        while (j < replacement.length && RegExp(r'[0-9]').hasMatch(replacement[j])) {
          j++;
        }
        if (j > start) {
          final g = int.parse(replacement.substring(start, j));
          if (braces && j < replacement.length && replacement[j] == '}') j++;
          if (g <= m.groupCount) sb.write(m.group(g) ?? '');
          i = j - 1;
        } else {
          sb.write(c);
        }
      } else {
        sb.write(c);
      }
    }
    return sb.toString();
  }

  /// `&quot; &amp; &lt; &gt; &apos; &nbsp; &hellip; &mdash; &ndash;` (named and numeric) plus any other numeric entity
  /// (`ReadApi._decodeHtmlEntities` 0x2a732c / closure 0x2a74e0).
  static String decodeHtmlEntities(String s) {
    if (!s.contains('&')) return s;
    const table = <String, String>{
      '&#34;': '"',
      '&quot;': '"',
      '&#38;': '&',
      '&amp;': '&',
      '&#60;': '<',
      '&lt;': '<',
      '&#62;': '>',
      '&gt;': '>',
      '&#39;': "'",
      '&apos;': "'",
      '&#160;': ' ',
      '&nbsp;': ' ',
      '&#8230;': '…',
      '&hellip;': '…',
      '&#8212;': '—',
      '&mdash;': '—',
      '&#8211;': '–',
      '&ndash;': '–',
    };
    var out = s;
    // `&amp;` last so that `&amp;lt;` stays `&lt;`
    for (final e in table.entries) {
      if (e.key == '&#38;' || e.key == '&amp;') continue;
      out = out.replaceAll(e.key, e.value);
    }
    out = out.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (m) {
      final g = m.group(1)!;
      final code = g.startsWith('x') ? int.tryParse(g.substring(1), radix: 16) : int.tryParse(g);
      if (code == null || code <= 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return m.group(0)!;
      return String.fromCharCode(code);
    });
    return out.replaceAll('&#38;', '&').replaceAll('&amp;', '&');
  }
}
