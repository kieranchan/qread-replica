// util/html/css_select.dart - a jsoup-flavoured CSS selector engine over package:html.
// package:html only knows W3C selectors; book sources use jsoup extensions (`:eq(n)`, `:lt/:gt`, `:contains`, `:matches`, `:has`,
// attribute regex `[a~=re]`, case-insensitive attribute values, ...), so `select()` is implemented here.
import 'package:html/dom.dart' as dom;

import '../legado/java_regex.dart';
import 'jsoup.dart';

class CssSelectException implements Exception {
  final String message;
  CssSelectException(this.message);
  @override
  String toString() => 'CssSelectException: $message';
}

typedef _Cond = bool Function(dom.Element e);

class _Compound {
  String? tag;
  final List<_Cond> conds = [];

  bool matches(dom.Element e) {
    final t = tag;
    if (t != null && t != '*') {
      final name = (e.localName ?? '').toLowerCase();
      if (name != t) {
        // `ns|tag` selects `ns:tag`
        return false;
      }
    }
    for (final c in conds) {
      if (!c(e)) return false;
    }
    return true;
  }
}

class _Complex {
  final List<_Compound> compounds = [];
  final List<String> combs = []; // combs[i] joins compounds[i] and compounds[i+1]
  String? leading; // relative selectors (`:has(> a)`)
}

class CssSelector {
  final List<_Complex> _alts;
  CssSelector._(this._alts);

  static final Map<String, CssSelector> _cache = {};

  /// Parses [query]; throws [CssSelectException] on malformed input (jsoup throws `Selector.SelectorParseException`).
  static CssSelector parse(String query) {
    final q = query.trim();
    final hit = _cache[q];
    if (hit != null) return hit;
    final p = _Parser(q);
    final alts = p.parseGroup(relative: false);
    if (!p.atEnd) throw CssSelectException('unexpected "${q.substring(p.i)}" in "$q"');
    if (alts.isEmpty) throw CssSelectException('empty selector');
    final s = CssSelector._(alts);
    if (_cache.length > 500) _cache.clear();
    _cache[q] = s;
    return s;
  }

  /// All elements in the subtree of [root] (including [root] itself when it is an element, as jsoup does) that match.
  List<dom.Element> select(dom.Node root) {
    final out = <dom.Element>[];
    for (final e in jSelfAndDescendants(root)) {
      if (matches(e)) out.add(e);
    }
    return out;
  }

  bool matches(dom.Element e) {
    for (final alt in _alts) {
      if (_matchRight(e, alt, alt.compounds.length - 1, null)) return true;
    }
    return false;
  }

  /// Convenience: `Selector.select(query, root)`.
  static List<dom.Element> query(String query, dom.Node root) => parse(query).select(root);
}

dom.Element? _parentEl(dom.Element e) {
  final p = e.parentNode;
  return p is dom.Element ? p : null;
}

dom.Element? _prevEl(dom.Element e) {
  final p = e.parentNode;
  if (p == null) return null;
  dom.Element? prev;
  for (final n in p.nodes) {
    if (identical(n, e)) return prev;
    if (n is dom.Element) prev = n;
  }
  return null;
}

bool _relation(dom.Element scope, dom.Element e, String comb) {
  switch (comb) {
    case '>':
      return identical(_parentEl(e), scope);
    case '+':
      return identical(_prevEl(e), scope);
    case '~':
      var p = _prevEl(e);
      while (p != null) {
        if (identical(p, scope)) return true;
        p = _prevEl(p);
      }
      return false;
    default:
      var p = _parentEl(e);
      while (p != null) {
        if (identical(p, scope)) return true;
        p = _parentEl(p);
      }
      return false;
  }
}

bool _matchRight(dom.Element e, _Complex c, int idx, dom.Element? scope) {
  if (!c.compounds[idx].matches(e)) return false;
  if (idx == 0) {
    if (c.leading == null || scope == null) return true;
    return _relation(scope, e, c.leading!);
  }
  switch (c.combs[idx - 1]) {
    case '>':
      final p = _parentEl(e);
      return p != null && _matchRight(p, c, idx - 1, scope);
    case '+':
      final p = _prevEl(e);
      return p != null && _matchRight(p, c, idx - 1, scope);
    case '~':
      var p = _prevEl(e);
      while (p != null) {
        if (_matchRight(p, c, idx - 1, scope)) return true;
        p = _prevEl(p);
      }
      return false;
    default:
      var p = _parentEl(e);
      while (p != null) {
        if (_matchRight(p, c, idx - 1, scope)) return true;
        p = _parentEl(p);
      }
      return false;
  }
}

class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);

  bool get atEnd => i >= s.length;

  void _ws() {
    while (i < s.length && _isSpace(s.codeUnitAt(i))) {
      i++;
    }
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d || c == 0x0c;

  List<_Complex> parseGroup({required bool relative}) {
    final alts = <_Complex>[];
    while (true) {
      _ws();
      if (atEnd || s[i] == ')') break;
      alts.add(_parseComplex(relative));
      _ws();
      if (!atEnd && s[i] == ',') {
        i++;
        continue;
      }
      break;
    }
    return alts;
  }

  _Complex _parseComplex(bool relative) {
    final c = _Complex();
    _ws();
    if (relative && !atEnd && '>+~'.contains(s[i])) {
      c.leading = s[i];
      i++;
      _ws();
    } else if (relative) {
      c.leading = ' ';
    }
    c.compounds.add(_parseCompound());
    while (true) {
      final before = i;
      _ws();
      final sawWs = i > before;
      if (atEnd || s[i] == ',' || s[i] == ')') break;
      String comb;
      if ('>+~'.contains(s[i])) {
        comb = s[i];
        i++;
        _ws();
      } else if (sawWs) {
        comb = ' ';
      } else {
        throw CssSelectException('unexpected "${s.substring(i)}"');
      }
      c.combs.add(comb);
      c.compounds.add(_parseCompound());
    }
    return c;
  }

  String _ident() {
    final sb = StringBuffer();
    while (i < s.length) {
      final ch = s.codeUnitAt(i);
      if (ch == 0x5c && i + 1 < s.length) {
        sb.write(s[i + 1]);
        i += 2;
        continue;
      }
      final isIdent = (ch >= 0x30 && ch <= 0x39) ||
          (ch >= 0x41 && ch <= 0x5a) ||
          (ch >= 0x61 && ch <= 0x7a) ||
          ch == 0x2d ||
          ch == 0x5f ||
          ch >= 0x80;
      if (!isIdent) break;
      sb.writeCharCode(ch);
      i++;
    }
    return sb.toString();
  }

  /// Reads up to the matching ')' (the '(' is already consumed).
  String _parenArg() {
    final start = i;
    var depth = 1;
    String? quote;
    while (i < s.length) {
      final ch = s[i];
      if (quote != null) {
        if (ch == '\\') {
          i++;
        } else if (ch == quote) {
          quote = null;
        }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '\\') {
        i++;
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) {
          final arg = s.substring(start, i);
          i++;
          return arg;
        }
      }
      i++;
    }
    throw CssSelectException('unbalanced parentheses in "$s"');
  }

  static String _unquote(String v) {
    final t = v.trim();
    if (t.length >= 2 && ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'")))) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  _Compound _parseCompound() {
    final c = _Compound();
    var any = false;
    if (!atEnd && s[i] == '*') {
      c.tag = '*';
      i++;
      any = true;
    } else if (!atEnd) {
      final id = _ident();
      if (id.isNotEmpty) {
        if (!atEnd && s[i] == '|' && i + 1 < s.length && s[i + 1] != '=') {
          i++;
          final local = _ident();
          c.tag = '${id.toLowerCase()}:${local.toLowerCase()}';
        } else {
          c.tag = id.toLowerCase();
        }
        any = true;
      }
    }
    while (!atEnd) {
      final ch = s[i];
      if (ch == '#') {
        i++;
        final id = _ident();
        if (id.isEmpty) throw CssSelectException('empty id in "$s"');
        c.conds.add((e) => e.id == id);
      } else if (ch == '.') {
        i++;
        final cls = _ident();
        if (cls.isEmpty) throw CssSelectException('empty class in "$s"');
        c.conds.add((e) => jHasClass(e, cls));
      } else if (ch == '[') {
        i++;
        c.conds.add(_parseAttr());
      } else if (ch == ':') {
        i++;
        c.conds.add(_parsePseudo());
      } else {
        break;
      }
      any = true;
    }
    if (!any) throw CssSelectException('cannot parse "${s.substring(i)}"');
    return c;
  }

  _Cond _parseAttr() {
    final start = i;
    var depth = 1;
    String? quote;
    while (i < s.length) {
      final ch = s[i];
      if (quote != null) {
        if (ch == '\\') {
          i++;
        } else if (ch == quote) {
          quote = null;
        }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    if (i >= s.length) throw CssSelectException('unbalanced brackets in "$s"');
    final body = s.substring(start, i).trim();
    i++; // ]
    if (body.startsWith('^')) {
      final prefix = body.substring(1).toLowerCase();
      return (e) => e.attributes.keys.any((k) => k.toString().toLowerCase().startsWith(prefix));
    }
    final m = RegExp(r'^([^\s=!^$*~|]+)\s*(?:([!^$*~|]?=)\s*([\s\S]*))?$').firstMatch(body);
    if (m == null) throw CssSelectException('bad attribute selector [$body]');
    final key = m.group(1)!;
    final op = m.group(2);
    if (op == null) return (e) => jHasAttr(e, key);
    final value = _unquote(m.group(3) ?? '');
    final lv = value.toLowerCase();
    switch (op) {
      case '=':
        return (e) => jHasAttr(e, key) && jAttr(e, key).trim().toLowerCase() == lv;
      case '!=':
        return (e) => !jHasAttr(e, key) || jAttr(e, key).trim().toLowerCase() != lv;
      case '^=':
        return (e) => jHasAttr(e, key) && jAttr(e, key).toLowerCase().startsWith(lv);
      case r'$=':
        return (e) => jHasAttr(e, key) && jAttr(e, key).toLowerCase().endsWith(lv);
      case '*=':
        return (e) => jHasAttr(e, key) && jAttr(e, key).toLowerCase().contains(lv);
      case '|=':
        return (e) {
          final a = jAttr(e, key).toLowerCase();
          return jHasAttr(e, key) && (a == lv || a.startsWith('$lv-'));
        };
      case '~=':
        final re = JavaRegex.compile(value);
        return (e) => jHasAttr(e, key) && re.hasMatch(jAttr(e, key));
    }
    throw CssSelectException('bad attribute operator $op');
  }

  _Cond _parsePseudo() {
    final name = _ident().toLowerCase();
    String? arg;
    if (!atEnd && s[i] == '(') {
      i++;
      arg = _parenArg();
    }
    int num(String a) {
      final n = int.tryParse(a.trim());
      if (n == null) throw CssSelectException('index must be numeric: $a');
      return n;
    }

    switch (name) {
      case 'eq':
        final n = num(arg ?? '');
        return (e) => jSiblingIndex(e) == n;
      case 'lt':
        final n = num(arg ?? '');
        return (e) => jSiblingIndex(e) < n;
      case 'gt':
        final n = num(arg ?? '');
        return (e) => jSiblingIndex(e) > n;
      case 'contains':
        final t = _unquote(arg ?? '').toLowerCase();
        return (e) => jText(e).toLowerCase().contains(t);
      case 'containsown':
        final t = _unquote(arg ?? '').toLowerCase();
        return (e) => jOwnText(e).toLowerCase().contains(t);
      case 'containsdata':
        final t = _unquote(arg ?? '').toLowerCase();
        return (e) => jData(e).toLowerCase().contains(t);
      case 'containswholetext':
        final t = _unquote(arg ?? '');
        return (e) => jWholeText(e).contains(t);
      case 'containswholeowntext':
        final t = _unquote(arg ?? '');
        return (e) => e.nodes.whereType<dom.Text>().map((x) => x.data).join().contains(t);
      case 'matches':
        final re = JavaRegex.compile(_unquote(arg ?? ''));
        return (e) => re.hasMatch(jText(e));
      case 'matchesown':
        final re = JavaRegex.compile(_unquote(arg ?? ''));
        return (e) => re.hasMatch(jOwnText(e));
      case 'matcheswholetext':
        final re = JavaRegex.compile(_unquote(arg ?? ''));
        return (e) => re.hasMatch(jWholeText(e));
      case 'has':
        final sub = _Parser(arg ?? '');
        final alts = sub.parseGroup(relative: true);
        if (alts.isEmpty) throw CssSelectException(':has(selector) needs a selector');
        final inner = CssSelector._(alts);
        return (e) {
          for (final alt in alts) {
            final lead = alt.leading ?? ' ';
            Iterable<dom.Element> candidates;
            if (lead == '+' || lead == '~') {
              final p = _parentEl(e);
              candidates = p == null
                  ? const []
                  : () sync* {
                      var seen = false;
                      for (final n in p.nodes) {
                        if (identical(n, e)) {
                          seen = true;
                          continue;
                        }
                        if (seen && n is dom.Element) yield* jSelfAndDescendants(n);
                      }
                    }();
            } else {
              candidates = jSelfAndDescendants(e).where((x) => !identical(x, e));
            }
            for (final d in candidates) {
              if (_matchRight(d, alt, alt.compounds.length - 1, e)) return true;
            }
          }
          // keep `inner` referenced for debugging parity with jsoup's evaluator tree
          return inner._alts.isEmpty;
        };
      case 'not':
        final sub = _Parser(arg ?? '');
        final alts = sub.parseGroup(relative: false);
        final inner = CssSelector._(alts);
        return (e) => !inner.matches(e);
      case 'is':
        final sub = _Parser(arg ?? '');
        final inner = CssSelector._(sub.parseGroup(relative: false));
        return (e) => inner.matches(e);
      case 'first-child':
        return (e) => _childIndex(e, false) == 1;
      case 'last-child':
        return (e) => _childIndex(e, true) == 1;
      case 'only-child':
        return (e) => _childIndex(e, false) == 1 && _childIndex(e, true) == 1;
      case 'first-of-type':
        return (e) => _typeIndex(e, false) == 1;
      case 'last-of-type':
        return (e) => _typeIndex(e, true) == 1;
      case 'only-of-type':
        return (e) => _typeIndex(e, false) == 1 && _typeIndex(e, true) == 1;
      case 'nth-child':
        final ab = _parseNth(arg ?? '');
        return (e) => _nth(ab, _childIndex(e, false));
      case 'nth-last-child':
        final ab = _parseNth(arg ?? '');
        return (e) => _nth(ab, _childIndex(e, true));
      case 'nth-of-type':
        final ab = _parseNth(arg ?? '');
        return (e) => _nth(ab, _typeIndex(e, false));
      case 'nth-last-of-type':
        final ab = _parseNth(arg ?? '');
        return (e) => _nth(ab, _typeIndex(e, true));
      case 'empty':
        return (e) => e.nodes.every((n) => n is dom.Comment || (n is dom.Text && n.data.isEmpty));
      case 'root':
        return (e) => e.parentNode is dom.Document || e.parentNode == null;
      case 'matchtext':
        return (e) => true;
    }
    throw CssSelectException('unknown pseudo-class :$name');
  }

  static int _childIndex(dom.Element e, bool fromEnd) {
    final p = e.parentNode;
    if (p == null) return 1;
    final els = p.nodes.whereType<dom.Element>().toList();
    final i = els.indexWhere((x) => identical(x, e));
    return fromEnd ? els.length - i : i + 1;
  }

  static int _typeIndex(dom.Element e, bool fromEnd) {
    final p = e.parentNode;
    if (p == null) return 1;
    final els = p.nodes.whereType<dom.Element>().where((x) => x.localName == e.localName).toList();
    final i = els.indexWhere((x) => identical(x, e));
    return fromEnd ? els.length - i : i + 1;
  }

  static (int, int) _parseNth(String raw) {
    final a = raw.trim().toLowerCase().replaceAll(' ', '');
    if (a == 'odd') return (2, 1);
    if (a == 'even') return (2, 0);
    final m = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(a);
    if (m != null) {
      final ap = m.group(1)!;
      final aa = ap.isEmpty || ap == '+' ? 1 : (ap == '-' ? -1 : int.parse(ap));
      final bb = m.group(2) == null ? 0 : int.parse(m.group(2)!);
      return (aa, bb);
    }
    final n = int.tryParse(a);
    if (n == null) throw CssSelectException('bad nth expression "$raw"');
    return (0, n);
  }

  static bool _nth((int, int) ab, int pos) {
    final (a, b) = ab;
    if (a == 0) return pos == b;
    final d = pos - b;
    return d % a == 0 && d ~/ a >= 0;
  }
}
