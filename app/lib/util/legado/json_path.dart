// util/legado/json_path.dart - own JSONPath (Jayway flavour, what Legado uses): node kinds property / properties / recursiveProperty /
// wildcard / recursiveWildcard / indexes / slice / filter, filter operators `== != >= > < <= =~ && || ! in nin subsetof anyof noneof size
// empty contains`, `?( )`, slices `[a:b]`, index lists `[1,2]`, regex literals `/re/flags`, plus the path functions length/size/min/max/avg/sum/keys.
import 'dart:convert';

import 'java_regex.dart';

class JsonPathException implements Exception {
  final String message;
  JsonPathException(this.message);
  @override
  String toString() => 'JsonPathException: $message';
}

/// Thrown by [JsonPath.read] when a definite path has no match (Jayway `PathNotFoundException`).
class PathNotFoundException extends JsonPathException {
  PathNotFoundException(super.message);
}

abstract class _Seg {
  bool get definite => false;
}

class _Prop extends _Seg {
  final String name;
  _Prop(this.name);
  @override
  bool get definite => true;
}

class _Props extends _Seg {
  final List<String> names;
  _Props(this.names);
  @override
  bool get definite => false;
}

class _Wildcard extends _Seg {}

class _Indexes extends _Seg {
  final List<int> idx;
  _Indexes(this.idx);
  @override
  bool get definite => idx.length == 1;
}

class _Slice extends _Seg {
  final int? start;
  final int? end;
  _Slice(this.start, this.end);
}

class _Filter extends _Seg {
  final _Expr expr;
  _Filter(this.expr);
}

class _Deep extends _Seg {
  final _Seg inner; // _Prop / _Wildcard / _Indexes / _Slice / _Filter / _Props
  _Deep(this.inner);
}

class _Func extends _Seg {
  final String name;
  final List<Object?> args;
  _Func(this.name, this.args);
  @override
  bool get definite => true;
}

class _Missing {
  const _Missing();
}

const _missing = _Missing();

// ---------------------------------------------------------------------------------------------------------------------------
// Filter expressions
// ---------------------------------------------------------------------------------------------------------------------------
abstract class _Expr {
  Object? eval(Object? current, Object? root);
}

class _Lit extends _Expr {
  final Object? v;
  _Lit(this.v);
  @override
  Object? eval(Object? current, Object? root) => v;
}

class _RegexLit extends _Expr {
  final RegExp re;
  _RegexLit(this.re);
  @override
  Object? eval(Object? current, Object? root) => re;
}

class _PathOperand extends _Expr {
  final JsonPath path;
  final bool fromRoot;
  _PathOperand(this.path, this.fromRoot);
  @override
  Object? eval(Object? current, Object? root) {
    final matches = path._match(fromRoot ? root : current, root);
    if (path._definite) {
      if (matches.isEmpty) return _missing;
      return matches.first;
    }
    return matches;
  }
}

class _ListLit extends _Expr {
  final List<_Expr> items;
  _ListLit(this.items);
  @override
  Object? eval(Object? current, Object? root) => items.map((e) => e.eval(current, root)).toList();
}

class _Not extends _Expr {
  final _Expr e;
  _Not(this.e);
  @override
  Object? eval(Object? current, Object? root) => !_truthy(e.eval(current, root));
}

class _Bin extends _Expr {
  final String op;
  final _Expr l;
  final _Expr r;
  _Bin(this.op, this.l, this.r);

  @override
  Object? eval(Object? current, Object? root) {
    if (op == '&&') return _truthy(l.eval(current, root)) && _truthy(r.eval(current, root));
    if (op == '||') return _truthy(l.eval(current, root)) || _truthy(r.eval(current, root));
    final a = l.eval(current, root);
    final b = r.eval(current, root);
    return _compare(op, a, b);
  }
}

bool _truthy(Object? v) {
  if (v is _Missing) return false;
  if (v is bool) return v;
  if (v is List) return v.isNotEmpty;
  return v != null; // existence test: `?(@.isbn)`
}

num? _asNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

bool _looseEquals(Object? a, Object? b) {
  if (a is _Missing || b is _Missing) return false;
  if (a == null || b == null) return a == b;
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  final na = _asNum(a), nb = _asNum(b);
  if ((a is num || b is num) && na != null && nb != null) return na == nb;
  if (a is List && b is List) return jsonEncode(a) == jsonEncode(b);
  if (a is Map && b is Map) return jsonEncode(a) == jsonEncode(b);
  return a.toString() == b.toString() && (a is String) == (b is String);
}

bool _compare(String op, Object? a, Object? b) {
  switch (op) {
    case '==':
      return _looseEquals(a, b);
    case '!=':
      return !_looseEquals(a, b);
    case '<':
    case '<=':
    case '>':
    case '>=':
      if (a is _Missing || b is _Missing || a == null || b == null) return false;
      if (a is String && b is String) {
        final c = a.compareTo(b);
        return op == '<' ? c < 0 : op == '<=' ? c <= 0 : op == '>' ? c > 0 : c >= 0;
      }
      final x = _asNum(a), y = _asNum(b);
      if (x == null || y == null) return false;
      return op == '<' ? x < y : op == '<=' ? x <= y : op == '>' ? x > y : x >= y;
    case '=~':
      if (a is _Missing || a == null) return false;
      RegExp? re = b is RegExp ? b : null;
      if (re == null && b is String) re = JavaRegex.compileOrQuote(b);
      if (re == null) return false;
      return re.hasMatch(a.toString());
    case 'in':
      if (b is List) return b.any((e) => _looseEquals(a, e));
      return false;
    case 'nin':
      if (b is List) return !b.any((e) => _looseEquals(a, e));
      return true;
    case 'subsetof':
      if (a is List && b is List) return a.every((x) => b.any((y) => _looseEquals(x, y)));
      return false;
    case 'anyof':
      if (a is List && b is List) return a.any((x) => b.any((y) => _looseEquals(x, y)));
      return false;
    case 'noneof':
      if (a is List && b is List) return !a.any((x) => b.any((y) => _looseEquals(x, y)));
      return false;
    case 'size':
      final n = _asNum(b);
      if (a is List) return n != null && a.length == n;
      if (a is String) return n != null && a.length == n;
      return false;
    case 'empty':
      final want = b is bool ? b : true;
      final e = a is List ? a.isEmpty : a is String ? a.isEmpty : false;
      return e == want;
    case 'contains':
      if (a is String) return b != null && a.contains(b.toString());
      if (a is List) return a.any((x) => _looseEquals(x, b));
      return false;
  }
  return false;
}

class _ExprParser {
  final String s;
  int i = 0;
  _ExprParser(this.s);

  void ws() {
    while (i < s.length && s.codeUnitAt(i) <= 0x20) {
      i++;
    }
  }

  _Expr parse() {
    final e = _or();
    ws();
    if (i < s.length) throw JsonPathException('unexpected "${s.substring(i)}" in filter');
    return e;
  }

  _Expr _or() {
    var l = _and();
    while (true) {
      ws();
      if (s.startsWith('||', i)) {
        i += 2;
        l = _Bin('||', l, _and());
      } else {
        return l;
      }
    }
  }

  _Expr _and() {
    var l = _cmp();
    while (true) {
      ws();
      if (s.startsWith('&&', i)) {
        i += 2;
        l = _Bin('&&', l, _cmp());
      } else {
        return l;
      }
    }
  }

  static const _wordOps = ['nin', 'in', 'subsetof', 'anyof', 'noneof', 'size', 'empty', 'contains'];

  _Expr _cmp() {
    final l = _unary();
    ws();
    for (final op in const ['==', '!=', '<=', '>=', '=~', '<', '>']) {
      if (s.startsWith(op, i)) {
        i += op.length;
        return _Bin(op, l, _unary());
      }
    }
    for (final w in _wordOps) {
      if (s.startsWith(w, i) && i + w.length < s.length && s.codeUnitAt(i + w.length) <= 0x20) {
        i += w.length;
        return _Bin(w, l, _unary());
      }
    }
    return l;
  }

  _Expr _unary() {
    ws();
    if (i < s.length && s[i] == '!' && !s.startsWith('!=', i)) {
      i++;
      return _Not(_unary());
    }
    if (i < s.length && s[i] == '(') {
      i++;
      final e = _or();
      ws();
      if (i >= s.length || s[i] != ')') throw JsonPathException('missing ) in filter');
      i++;
      return e;
    }
    return _operand();
  }

  _Expr _operand() {
    ws();
    if (i >= s.length) throw JsonPathException('operand expected in filter');
    final c = s[i];
    if (c == '@' || c == r'$') {
      final start = i;
      i++;
      // path continues until an operator/space/closing paren at depth 0
      var depthB = 0;
      String? quote;
      while (i < s.length) {
        final ch = s[i];
        if (quote != null) {
          if (ch == '\\') {
            i++;
          } else if (ch == quote) {
            quote = null;
          }
        } else if (ch == "'" || ch == '"') {
          quote = ch;
        } else if (ch == '[' || ch == '(') {
          depthB++;
        } else if (ch == ']' || ch == ')') {
          if (depthB == 0) break;
          depthB--;
        } else if (depthB == 0 && (ch == ' ' || ch == '=' || ch == '!' || ch == '<' || ch == '>' || ch == '&' || ch == '|')) {
          break;
        }
        i++;
      }
      final text = s.substring(start, i);
      return _PathOperand(JsonPath.compile(text), c == r'$');
    }
    if (c == "'" || c == '"') {
      final sb = StringBuffer();
      i++;
      while (i < s.length && s[i] != c) {
        if (s[i] == '\\' && i + 1 < s.length) {
          i++;
          final n = s[i];
          sb.write(n == 'n' ? '\n' : n == 't' ? '\t' : n);
        } else {
          sb.write(s[i]);
        }
        i++;
      }
      i++;
      return _Lit(sb.toString());
    }
    if (c == '/') {
      var j = i + 1;
      while (j < s.length && s[j] != '/') {
        if (s[j] == '\\') j++;
        j++;
      }
      final body = s.substring(i + 1, j);
      j++;
      final fl = StringBuffer();
      while (j < s.length && RegExp(r'[imsx]').hasMatch(s[j])) {
        fl.write(s[j]);
        j++;
      }
      i = j;
      final flags = fl.toString();
      return _RegexLit(JavaRegex.compile(body, caseSensitive: !flags.contains('i'), dotAll: flags.contains('s'), multiLine: flags.contains('m')));
    }
    if (c == '[') {
      i++;
      final items = <_Expr>[];
      while (true) {
        ws();
        if (i < s.length && s[i] == ']') {
          i++;
          break;
        }
        items.add(_operand());
        ws();
        if (i < s.length && s[i] == ',') i++;
      }
      return _ListLit(items);
    }
    final m = RegExp(r'^(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)').firstMatch(s.substring(i));
    if (m != null) {
      i += m.group(0)!.length;
      final t = m.group(0)!;
      if (t == 'true') return _Lit(true);
      if (t == 'false') return _Lit(false);
      if (t == 'null') return _Lit(null);
      return _Lit(num.parse(t));
    }
    throw JsonPathException('bad operand at "${s.substring(i)}"');
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// Path
// ---------------------------------------------------------------------------------------------------------------------------
class JsonPath {
  final List<_Seg> _segs;
  final String source;
  JsonPath._(this._segs, this.source);

  static final Map<String, JsonPath> _cache = {};

  bool get _definite => _segs.every((s) => s.definite);

  /// True when the path addresses exactly one location (Jayway `isDefinite`).
  bool get isDefinite => _definite;

  static JsonPath compile(String path) {
    final hit = _cache[path];
    if (hit != null) return hit;
    var p = path.trim();
    if (p.isEmpty) throw JsonPathException('path must not be empty');
    if (!p.startsWith(r'$') && !p.startsWith('@')) p = p.startsWith('[') ? '\$$p' : '\$.$p';
    final segs = _parse(p);
    final jp = JsonPath._(segs, path);
    if (_cache.length > 500) _cache.clear();
    _cache[path] = jp;
    return jp;
  }

  static List<_Seg> _parse(String p) {
    final segs = <_Seg>[];
    var i = 1; // skip $ or @
    final n = p.length;
    while (i < n) {
      final c = p[i];
      if (c == '.') {
        if (i + 1 < n && p[i + 1] == '.') {
          i += 2;
          if (i >= n) throw JsonPathException('path must not end with a ".."');
          if (p[i] == '*') {
            segs.add(_Deep(_Wildcard()));
            i++;
          } else if (p[i] == '[') {
            final r = _bracket(p, i);
            segs.add(_Deep(r.$1));
            i = r.$2;
          } else {
            final r = _name(p, i);
            segs.add(_Deep(_Prop(r.$1)));
            i = r.$2;
          }
        } else {
          i++;
          if (i >= n) throw JsonPathException('path must not end with a "."');
          if (p[i] == '*') {
            segs.add(_Wildcard());
            i++;
          } else if (p[i] == '[') {
            continue; // `.[` form
          } else {
            final r = _name(p, i);
            final name = r.$1;
            i = r.$2;
            if (i < n && p[i] == '(') {
              final close = _matchParen(p, i);
              final argText = p.substring(i + 1, close).trim();
              segs.add(_Func(name, argText.isEmpty ? const [] : argText.split(',').map((e) => e.trim()).toList()));
              i = close + 1;
            } else {
              segs.add(_Prop(name));
            }
          }
        }
      } else if (c == '[') {
        final r = _bracket(p, i);
        segs.add(r.$1);
        i = r.$2;
      } else if (c == ' ') {
        i++;
      } else {
        throw JsonPathException('illegal character at position $i in "$p"');
      }
    }
    return segs;
  }

  static int _matchParen(String p, int open) {
    var depth = 0;
    String? q;
    for (var i = open; i < p.length; i++) {
      final ch = p[i];
      if (q != null) {
        if (ch == '\\') {
          i++;
        } else if (ch == q) {
          q = null;
        }
      } else if (ch == "'" || ch == '"') {
        q = ch;
      } else if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    throw JsonPathException('unbalanced parentheses in "$p"');
  }

  static (String, int) _name(String p, int i) {
    final start = i;
    while (i < p.length && p[i] != '.' && p[i] != '[' && p[i] != '(') {
      i++;
    }
    if (i == start) throw JsonPathException('property name expected at $start in "$p"');
    return (p.substring(start, i), i);
  }

  static (_Seg, int) _bracket(String p, int i) {
    // find matching ]
    var depth = 0;
    String? q;
    var j = i;
    for (; j < p.length; j++) {
      final ch = p[j];
      if (q != null) {
        if (ch == '\\') {
          j++;
        } else if (ch == q) {
          q = null;
        }
      } else if (ch == "'" || ch == '"') {
        q = ch;
      } else if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) break;
      }
    }
    if (j >= p.length) throw JsonPathException('missing ] in "$p"');
    final body = p.substring(i + 1, j).trim();
    final next = j + 1;
    if (body == '*') return (_Wildcard(), next);
    if (body.startsWith('?')) {
      var e = body.substring(1).trim();
      if (e.startsWith('(') && e.endsWith(')')) e = e.substring(1, e.length - 1);
      return (_Filter(_ExprParser(e).parse()), next);
    }
    if (body.startsWith("'") || body.startsWith('"')) {
      final names = <String>[];
      var k = 0;
      while (k < body.length) {
        while (k < body.length && (body[k] == ',' || body[k] == ' ')) {
          k++;
        }
        if (k >= body.length) break;
        final quote = body[k];
        if (quote != "'" && quote != '"') throw JsonPathException('bad property list [$body]');
        final sb = StringBuffer();
        k++;
        while (k < body.length && body[k] != quote) {
          if (body[k] == '\\' && k + 1 < body.length) k++;
          sb.write(body[k]);
          k++;
        }
        k++;
        names.add(sb.toString());
      }
      return (names.length == 1 ? _Prop(names.first) : _Props(names), next);
    }
    if (body.contains(':')) {
      final parts = body.split(':');
      final a = parts[0].trim().isEmpty ? null : int.tryParse(parts[0].trim());
      final b = parts.length > 1 && parts[1].trim().isNotEmpty ? int.tryParse(parts[1].trim()) : null;
      return (_Slice(a, b), next);
    }
    final idx = <int>[];
    for (final part in body.split(',')) {
      final v = int.tryParse(part.trim());
      if (v == null) throw JsonPathException('bad array index [$body]');
      idx.add(v);
    }
    return (_Indexes(idx), next);
  }

  /// Jayway `read`: the single value for a definite path (throws [PathNotFoundException] when absent), else a list of matches.
  Object? read(Object? root) {
    final matches = _match(root, root);
    if (_definite) {
      if (matches.isEmpty) throw PathNotFoundException('No results for path: $source');
      return matches.first;
    }
    return matches;
  }

  /// Parses [json] (a String or already decoded value) and reads [path].
  static Object? readFrom(Object? json, String path) => compile(path).read(parseJson(json));

  static Object? parseJson(Object? json) {
    if (json is String) {
      var t = json.trim();
      try {
        return jsonDecode(t);
      } on FormatException {
        // JSONP: callback({...});
        final m = RegExp(r'^[\w$.]+\s*\(([\s\S]*)\)\s*;?$').firstMatch(t);
        if (m != null) {
          t = m.group(1)!;
          return jsonDecode(t);
        }
        rethrow;
      }
    }
    return json;
  }

  List<Object?> _match(Object? start, Object? root) {
    var cur = <Object?>[start];
    for (var si = 0; si < _segs.length; si++) {
      final seg = _segs[si];
      final next = <Object?>[];
      if (seg is _Func) {
        final isLast = si == _segs.length - 1;
        final v = _function(seg, cur);
        if (!isLast) {
          cur = [v];
          continue;
        }
        return [v];
      }
      for (final node in cur) {
        _apply(seg, node, root, next);
      }
      cur = next;
      if (cur.isEmpty) return const [];
    }
    return cur;
  }

  static Object? _function(_Func f, List<Object?> cur) {
    final target = cur.length == 1 ? cur.first : cur;
    final list = target is List ? target : <Object?>[target];
    final nums = list.map(_asNum).whereType<num>().toList();
    switch (f.name) {
      case 'length':
      case 'size':
        if (target is List) return target.length;
        if (target is String) return target.length;
        if (target is Map) return target.length;
        return 0;
      case 'keys':
        return target is Map ? target.keys.toList() : <Object?>[];
      case 'min':
        return nums.isEmpty ? null : nums.reduce((a, b) => a < b ? a : b);
      case 'max':
        return nums.isEmpty ? null : nums.reduce((a, b) => a > b ? a : b);
      case 'sum':
        return nums.fold<num>(0, (a, b) => a + b);
      case 'avg':
        return nums.isEmpty ? null : nums.fold<num>(0, (a, b) => a + b) / nums.length;
      case 'first':
        return list.isEmpty ? null : list.first;
      case 'last':
        return list.isEmpty ? null : list.last;
      case 'concat':
        return list.join();
    }
    throw JsonPathException('unknown function ${f.name}()');
  }

  void _apply(_Seg seg, Object? node, Object? root, List<Object?> out) {
    if (seg is _Prop) {
      if (node is Map && node.containsKey(seg.name)) out.add(node[seg.name]);
    } else if (seg is _Props) {
      if (node is Map) {
        final m = <String, Object?>{};
        for (final n in seg.names) {
          if (node.containsKey(n)) m[n] = node[n];
        }
        if (m.isNotEmpty) out.add(m);
      }
    } else if (seg is _Wildcard) {
      if (node is Map) {
        out.addAll(node.values);
      } else if (node is List) {
        out.addAll(node);
      }
    } else if (seg is _Indexes) {
      if (node is List) {
        for (final ix in seg.idx) {
          final k = ix < 0 ? node.length + ix : ix;
          if (k >= 0 && k < node.length) out.add(node[k]);
        }
      }
    } else if (seg is _Slice) {
      if (node is List) {
        final len = node.length;
        var a = seg.start ?? 0;
        var b = seg.end ?? len;
        if (seg.start != null && seg.end == null && a < 0) {
          // [-n:] -> last n items
          a = len + a;
          b = len;
        } else if (seg.start == null && seg.end != null && b < 0) {
          // [:-n] -> all but the last n
          a = 0;
          b = len + b;
        } else {
          if (a < 0) a = len + a;
          if (b < 0) b = len + b;
        }
        a = a.clamp(0, len);
        b = b.clamp(0, len);
        for (var k = a; k < b; k++) {
          out.add(node[k]);
        }
      }
    } else if (seg is _Filter) {
      if (node is List) {
        for (final item in node) {
          if (_truthy(seg.expr.eval(item, root))) out.add(item);
        }
      } else if (node is Map) {
        if (_truthy(seg.expr.eval(node, root))) out.add(node);
      }
    } else if (seg is _Deep) {
      void walk(Object? n) {
        _apply(seg.inner, n, root, out);
        if (n is Map) {
          for (final v in n.values) {
            if (v is Map || v is List) walk(v);
          }
        } else if (n is List) {
          for (final v in n) {
            if (v is Map || v is List) walk(v);
          }
        }
      }

      walk(node);
    }
  }
}
