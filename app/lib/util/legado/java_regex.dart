// util/legado/java_regex.dart - Java `java.util.regex` flavoured patterns on top of Dart's RegExp (the original ships its own
// `java_regex.dart` for the same reason: book-source rules are written for Android).
//
// Handled: leading inline flags `(?i)(?s)(?m)(?x)(?u)`, `\Q..\E`, possessive quantifiers (dropped), `\h`, `\R`, `\A`, `\z`, `\Z`,
// `\p{Alpha}`-style POSIX/Java classes, Java replacement strings (`$1`, `${name}`, `\$`).
// Not handled: class intersections `[a-z&&[^b]]`, scoped inline flags in the middle of a pattern.

class JavaRegex {
  static final Map<String, RegExp> _cache = {};

  /// Compiles [pattern]; throws [FormatException] when Dart cannot parse the converted pattern.
  static RegExp compile(String pattern, {bool caseSensitive = true, bool multiLine = false, bool dotAll = false}) {
    final key = '${caseSensitive ? 1 : 0}${multiLine ? 1 : 0}${dotAll ? 1 : 0}$pattern';
    final hit = _cache[key];
    if (hit != null) return hit;
    var cs = caseSensitive;
    var ml = multiLine;
    var da = dotAll;
    var p = pattern;
    // leading inline flags
    final flagRe = RegExp(r'^\(\?([a-zA-Z]+)\)');
    while (true) {
      final m = flagRe.firstMatch(p);
      if (m == null) break;
      final flags = m.group(1)!;
      if (!RegExp(r'^[imsuxdU]+$').hasMatch(flags)) break;
      if (flags.contains('i')) cs = false;
      if (flags.contains('m')) ml = true;
      if (flags.contains('s')) da = true;
      p = p.substring(m.end);
    }
    final conv = _convert(p);
    RegExp re;
    try {
      re = RegExp(conv.$1, caseSensitive: cs, multiLine: ml, dotAll: da, unicode: conv.$2);
    } on FormatException {
      if (conv.$2) rethrow;
      re = RegExp(conv.$1, caseSensitive: cs, multiLine: ml, dotAll: da, unicode: true);
    }
    if (_cache.length > 800) _cache.clear();
    _cache[key] = re;
    return re;
  }

  /// Like [compile] but falls back to a literal match of [pattern] (Legado's `Pattern.quote` fallback).
  static RegExp compileOrQuote(String pattern) {
    try {
      return compile(pattern);
    } on FormatException {
      return RegExp(RegExp.escape(pattern));
    }
  }

  static String quote(String s) => RegExp.escape(s);

  static const Map<String, String> _posix = {
    'Alpha': 'a-zA-Z',
    'Digit': '0-9',
    'Alnum': 'a-zA-Z0-9',
    'Upper': 'A-Z',
    'Lower': 'a-z',
    'Punct': r'!-/:-@\[-`{-~',
    'Space': r' \t\n\x0B\f\r',
    'Blank': r' \t',
    'XDigit': '0-9a-fA-F',
    'ASCII': r'\x00-\x7F',
    'Cntrl': r'\x00-\x1F\x7F',
    'Graph': r'!-~',
    'Print': r' -~',
    'javaLowerCase': 'a-z',
    'javaUpperCase': 'A-Z',
  };

  static const Map<String, String> _unicodeNames = {
    'IsHan': r'\p{Script=Han}',
    'IsHani': r'\p{Script=Han}',
    'IsLatin': r'\p{Script=Latin}',
    'IsCyrillic': r'\p{Script=Cyrillic}',
    'IsAlphabetic': r'\p{Alphabetic}',
    'IsLetter': r'\p{L}',
    'IsDigit': r'\p{Nd}',
    'IsUppercase': r'\p{Lu}',
    'IsLowercase': r'\p{Ll}',
    'IsPunctuation': r'\p{P}',
    'IsWhite_Space': r'\s',
    'javaLetter': r'\p{L}',
    'javaDigit': r'\p{Nd}',
  };

  static (String, bool) _convert(String p) {
    final out = StringBuffer();
    var unicode = false;
    var inClass = 0;
    var i = 0;
    var prevQuantifier = false;
    while (i < p.length) {
      final c = p[i];
      if (c == '\\' && i + 1 < p.length) {
        final n = p[i + 1];
        if (n == 'Q') {
          final end = p.indexOf(r'\E', i + 2);
          final lit = end < 0 ? p.substring(i + 2) : p.substring(i + 2, end);
          out.write(RegExp.escape(lit));
          i = end < 0 ? p.length : end + 2;
          prevQuantifier = false;
          continue;
        }
        if (n == 'h') {
          out.write(inClass > 0 ? r' \t\u00a0\u1680\u180e\u2000-\u200a\u202f\u205f\u3000' : r'[ \t\u00a0\u1680\u180e\u2000-\u200a\u202f\u205f\u3000]');
          i += 2;
          prevQuantifier = false;
          continue;
        }
        if (n == 'R' && inClass == 0) {
          out.write(r'(?:\r\n|[\n\r\u2028\u2029\u000B\u000C\u0085])');
          i += 2;
          prevQuantifier = false;
          continue;
        }
        if (n == 'A' && inClass == 0) {
          out.write('^');
          i += 2;
          continue;
        }
        if ((n == 'z' || n == 'Z') && inClass == 0) {
          out.write(r'$');
          i += 2;
          continue;
        }
        if (n == 'G' && inClass == 0) {
          i += 2;
          continue;
        }
        if ((n == 'p' || n == 'P') && i + 2 < p.length) {
          String? name;
          var end = i + 2;
          if (p[i + 2] == '{') {
            final close = p.indexOf('}', i + 3);
            if (close > 0) {
              name = p.substring(i + 3, close);
              end = close + 1;
            }
          } else {
            name = p[i + 2];
            end = i + 3;
          }
          if (name != null) {
            final posix = _posix[name];
            if (posix != null) {
              if (inClass > 0) {
                out.write(n == 'p' ? posix : '');
              } else {
                out.write(n == 'p' ? '[$posix]' : '[^$posix]');
              }
            } else {
              final mapped = _unicodeNames[name] ?? '\\p{${name.replaceFirst(RegExp(r'^Is(?=[A-Z])'), '')}}';
              out.write(n == 'p' ? mapped : mapped.replaceFirst(r'\p', r'\P'));
              unicode = true;
            }
            i = end;
            prevQuantifier = false;
            continue;
          }
        }
        out.write(c);
        out.write(n);
        i += 2;
        prevQuantifier = false;
        continue;
      }
      if (c == '[') {
        inClass++;
        out.write(c);
        i++;
        // Java allows ']' right after '[' or '[^' as a literal only inside nested classes; keep Dart semantics.
        prevQuantifier = false;
        continue;
      }
      if (c == ']' && inClass > 0) {
        inClass--;
        out.write(c);
        i++;
        prevQuantifier = false;
        continue;
      }
      if (inClass == 0) {
        if (c == '+' && prevQuantifier) {
          // possessive quantifier: drop the extra '+'
          i++;
          prevQuantifier = false;
          continue;
        }
        if (c == '*' || c == '+' || c == '?') {
          // lazy marker `*?` is a lazy quantifier, not a new one
          final isLazy = c == '?' && prevQuantifier;
          out.write(c);
          i++;
          prevQuantifier = !isLazy;
          continue;
        }
        if (c == '}') {
          out.write(c);
          i++;
          prevQuantifier = true;
          continue;
        }
        if (c == '(' && i + 2 < p.length && p[i + 1] == '?' && p[i + 2] == '#') {
          // comment group (?#...)
          final close = p.indexOf(')', i);
          i = close < 0 ? p.length : close + 1;
          continue;
        }
      }
      out.write(c);
      i++;
      prevQuantifier = false;
    }
    var s = out.toString();
    if (unicode) {
      // unicode mode rejects identity escapes of non-syntax characters
      s = s.replaceAllMapped(RegExp(r'\\([^\x00-\x2f:-@\[-`{-~dDwWsSbBnrtfv0-9pPuxck]|[ "%&,:;<=>@_`~!#\x27-])'), (m) => m.group(1)!);
      s = s.replaceAllMapped(RegExp(r'\\([\-"%&,:;<=>@_`~!# ])'), (m) => m.group(1)!);
    }
    return (s, unicode);
  }

  /// Java `Matcher.replaceAll(replacement)` semantics. Throws [FormatException] on references to missing groups.
  static String replaceAll(String input, RegExp re, String replacement) {
    return input.replaceAllMapped(re, (m) => _expand(m, replacement));
  }

  static String replaceFirst(String input, RegExp re, String replacement) {
    return input.replaceFirstMapped(re, (m) => _expand(m, replacement));
  }

  static String _expand(Match m, String rep) {
    if (!rep.contains(r'$') && !rep.contains('\\')) return rep;
    final sb = StringBuffer();
    var i = 0;
    while (i < rep.length) {
      final c = rep[i];
      if (c == '\\') {
        i++;
        if (i >= rep.length) throw const FormatException('character to be escaped is missing');
        sb.write(rep[i]);
        i++;
      } else if (c == r'$') {
        i++;
        if (i >= rep.length) throw const FormatException('Illegal group reference: group index is missing');
        if (rep[i] == '{') {
          final close = rep.indexOf('}', i);
          if (close < 0) throw const FormatException("named capturing group is missing trailing '}'");
          final name = rep.substring(i + 1, close);
          String? v;
          try {
            v = (m as RegExpMatch).namedGroup(name);
          } catch (_) {
            throw FormatException('No group with name {$name}');
          }
          sb.write(v ?? '');
          i = close + 1;
        } else {
          var d = rep.codeUnitAt(i) - 0x30;
          if (d < 0 || d > 9) throw const FormatException('Illegal group reference');
          i++;
          var ref = d;
          if (ref > m.groupCount) throw FormatException('No group $ref');
          while (i < rep.length) {
            final nd = rep.codeUnitAt(i) - 0x30;
            if (nd < 0 || nd > 9) break;
            final nr = ref * 10 + nd;
            if (nr > m.groupCount) break;
            ref = nr;
            i++;
          }
          sb.write(m.group(ref) ?? '');
        }
      } else {
        sb.write(c);
        i++;
      }
    }
    return sb.toString();
  }
}
