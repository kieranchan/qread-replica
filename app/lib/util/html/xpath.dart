// util/html/xpath.dart - an XPath 1.0 evaluator over package:html (the original has its own analyze_by_xpath.dart; Legado uses
// JsoupXpath). Supports `/`, `//`, `./`, `.//`, `..`, all axes, `@attr`, `text()`, `node()`, `*`, predicates (position, `last()`,
// attribute tests `[@k='v']`, comparisons, and/or), unions `|`, the usual string/number/boolean functions plus the JsoupXpath
// extensions `allText() ownText() html() outerHtml() innerHtml()`.
import 'package:html/dom.dart' as dom;

import '../legado/java_regex.dart';
import 'jsoup.dart';

class XPathException implements Exception {
  final String message;
  XPathException(this.message);
  @override
  String toString() => 'XPathException: $message';
}

/// A node of the XPath data model: an element/text/comment/document node or an attribute.
class XNode {
  final dom.Node? node;
  final dom.Element? owner;
  final String? attrName;
  final String? attrValue;
  final int attrPos;

  XNode(dom.Node this.node)
      : owner = null,
        attrName = null,
        attrValue = null,
        attrPos = 0;

  XNode.attr(dom.Element this.owner, String this.attrName, String this.attrValue, this.attrPos) : node = null;

  /// A synthetic text node (results of `allText()` etc.).
  factory XNode.text(String value) => XNode(dom.Text(value));

  bool get isAttr => attrName != null;
  bool get isElement => node is dom.Element;
  bool get isText => node is dom.Text;
  dom.Element? get element => node is dom.Element ? node as dom.Element : null;

  Object get key => isAttr ? '${identityHashCode(owner)}@$attrName' : node!;

  /// XPath string-value.
  String get stringValue {
    if (isAttr) return attrValue!;
    final n = node!;
    if (n is dom.Text) return n.data;
    if (n is dom.Comment) return n.data ?? '';
    final sb = StringBuffer();
    void walk(dom.Node x) {
      if (x is dom.Text) {
        sb.write(x.data);
      } else if (x is dom.Element || x is dom.Document) {
        for (final c in x.nodes) {
          walk(c);
        }
      }
    }

    walk(n);
    return sb.toString();
  }

  /// JsoupXpath `JXNode.asString()`: elements print as outer HTML, text and attributes as their value.
  String asString() {
    if (isAttr) return attrValue!;
    final n = node!;
    if (n is dom.Text) return n.data;
    if (n is dom.Element) return n.outerHtml;
    if (n is dom.Document) return n.outerHtml;
    return stringValue;
  }

  @override
  bool operator ==(Object other) => other is XNode && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------------------------------------------------------
enum _T { name, str, num, op, end }

class _Tok {
  final _T t;
  final String v;
  _Tok(this.t, this.v);
  @override
  String toString() => '$t:$v';
}

List<_Tok> _tokenize(String s) {
  final out = <_Tok>[];
  var i = 0;
  bool isNameStart(int c) => (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x5f || c >= 0x80;
  bool isNameChar(int c) => isNameStart(c) || (c >= 0x30 && c <= 0x39) || c == 0x2d || c == 0x2e;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c <= 0x20) {
      i++;
      continue;
    }
    if (c == 0x22 || c == 0x27) {
      final end = s.indexOf(s[i], i + 1);
      if (end < 0) throw XPathException('unterminated string literal');
      out.add(_Tok(_T.str, s.substring(i + 1, end)));
      i = end + 1;
      continue;
    }
    if ((c >= 0x30 && c <= 0x39) || (c == 0x2e && i + 1 < s.length && s.codeUnitAt(i + 1) >= 0x30 && s.codeUnitAt(i + 1) <= 0x39)) {
      var j = i;
      while (j < s.length && ((s.codeUnitAt(j) >= 0x30 && s.codeUnitAt(j) <= 0x39) || s[j] == '.')) {
        j++;
      }
      out.add(_Tok(_T.num, s.substring(i, j)));
      i = j;
      continue;
    }
    if (isNameStart(c)) {
      var j = i;
      while (j < s.length && (isNameChar(s.codeUnitAt(j)) || (s[j] == ':' && j + 1 < s.length && s[j + 1] != ':' && j > i && isNameStart(s.codeUnitAt(j + 1))))) {
        j++;
      }
      // names may not end with '.' or '-' followed by operators; keep as is (XML names allow them)
      out.add(_Tok(_T.name, s.substring(i, j)));
      i = j;
      continue;
    }
    String? two;
    for (final op in const ['//', '::', '..', '!=', '<=', '>=']) {
      if (s.startsWith(op, i)) {
        two = op;
        break;
      }
    }
    if (two != null) {
      out.add(_Tok(_T.op, two));
      i += 2;
      continue;
    }
    if ('/.@()[],|=<>+-*'.contains(s[i])) {
      out.add(_Tok(_T.op, s[i]));
      i++;
      continue;
    }
    throw XPathException('unexpected character "${s[i]}" in "$s"');
  }
  out.add(_Tok(_T.end, ''));
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------------------------------------------------------
abstract class _E {
  Object eval(_Ctx c);
}

class _Ctx {
  final XNode node;
  final int position;
  final int size;
  final _Env env;
  _Ctx(this.node, this.position, this.size, this.env);
}

class _Env {
  final dom.Node root; // what absolute paths start from
  Map<Object, int>? _order;
  _Env(this.root);

  int orderOf(XNode n) {
    _order ??= _buildOrder();
    final dom.Node base = n.isAttr ? n.owner! : n.node!;
    final idx = _order![base] ?? 0;
    return idx * 1000 + (n.isAttr ? n.attrPos + 1 : 0);
  }

  Map<Object, int> _buildOrder() {
    dom.Node top = root;
    while (top.parentNode != null) {
      top = top.parentNode!;
    }
    final m = <Object, int>{};
    var i = 0;
    void walk(dom.Node n) {
      m[n] = i++;
      for (final c in n.nodes) {
        walk(c);
      }
    }

    walk(top);
    return m;
  }
}

class _Lit extends _E {
  final Object v;
  _Lit(this.v);
  @override
  Object eval(_Ctx c) => v;
}

class _Neg extends _E {
  final _E e;
  _Neg(this.e);
  @override
  Object eval(_Ctx c) => -_toNum(e.eval(c));
}

class _Bin extends _E {
  final String op;
  final _E l, r;
  _Bin(this.op, this.l, this.r);
  @override
  Object eval(_Ctx c) {
    switch (op) {
      case 'or':
        return _toBool(l.eval(c)) || _toBool(r.eval(c));
      case 'and':
        return _toBool(l.eval(c)) && _toBool(r.eval(c));
      case '=':
      case '!=':
      case '<':
      case '<=':
      case '>':
      case '>=':
        return _cmp(op, l.eval(c), r.eval(c));
      case '+':
        return _toNum(l.eval(c)) + _toNum(r.eval(c));
      case '-':
        return _toNum(l.eval(c)) - _toNum(r.eval(c));
      case '*':
        return _toNum(l.eval(c)) * _toNum(r.eval(c));
      case 'div':
        return _toNum(l.eval(c)) / _toNum(r.eval(c));
      case 'mod':
        return _toNum(l.eval(c)) % _toNum(r.eval(c));
    }
    throw XPathException('bad operator $op');
  }
}

class _Union extends _E {
  final List<_E> parts;
  _Union(this.parts);
  @override
  Object eval(_Ctx c) {
    final seen = <Object, XNode>{};
    for (final p in parts) {
      final v = p.eval(c);
      if (v is! List<XNode>) throw XPathException('union operands must be node-sets');
      for (final n in v) {
        seen[n.key] = n;
      }
    }
    final list = seen.values.toList();
    list.sort((a, b) => c.env.orderOf(a).compareTo(c.env.orderOf(b)));
    return list;
  }
}

class _Func extends _E {
  final String name;
  final List<_E> args;
  _Func(this.name, this.args);

  @override
  Object eval(_Ctx c) => _callFunction(name, args, c);
}

class _Step {
  final String axis;
  final String test; // name | * | node() | text() | comment() | ext:<fn>
  final List<_E> preds;
  _Step(this.axis, this.test, this.preds);
}

class _Path extends _E {
  final _E? base; // filter expression start
  final bool absolute;
  final List<_Step> steps;
  _Path(this.base, this.absolute, this.steps);

  @override
  Object eval(_Ctx c) {
    List<XNode> cur;
    if (base != null) {
      final v = base!.eval(c);
      if (v is! List<XNode>) {
        if (steps.isEmpty) return v;
        throw XPathException('path applied to a non node-set');
      }
      cur = v;
    } else if (absolute) {
      cur = [XNode(c.env.root)];
    } else {
      cur = [c.node];
    }
    for (final s in steps) {
      cur = _applyStep(s, cur, c.env);
    }
    return cur;
  }
}

class _Filter extends _E {
  final _E base;
  final List<_E> preds;
  _Filter(this.base, this.preds);
  @override
  Object eval(_Ctx c) {
    var v = base.eval(c);
    if (v is! List<XNode>) throw XPathException('predicate on a non node-set');
    for (final p in preds) {
      v = _filterByPredicate(v as List<XNode>, p, c.env);
    }
    return v;
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------------------------------------------------------
class _Parser {
  final List<_Tok> toks;
  int p = 0;
  _Parser(this.toks);

  _Tok get cur => toks[p];
  bool isOp(String v) => cur.t == _T.op && cur.v == v;
  bool isName(String v) => cur.t == _T.name && cur.v == v;

  _E parse() {
    final e = _or();
    if (cur.t != _T.end) throw XPathException('unexpected "${cur.v}"');
    return e;
  }

  _E _or() {
    var l = _and();
    while (isName('or')) {
      p++;
      l = _Bin('or', l, _and());
    }
    return l;
  }

  _E _and() {
    var l = _eq();
    while (isName('and')) {
      p++;
      l = _Bin('and', l, _eq());
    }
    return l;
  }

  _E _eq() {
    var l = _rel();
    while (isOp('=') || isOp('!=')) {
      final op = cur.v;
      p++;
      l = _Bin(op, l, _rel());
    }
    return l;
  }

  _E _rel() {
    var l = _add();
    while (isOp('<') || isOp('>') || isOp('<=') || isOp('>=')) {
      final op = cur.v;
      p++;
      l = _Bin(op, l, _add());
    }
    return l;
  }

  _E _add() {
    var l = _mul();
    while (isOp('+') || isOp('-')) {
      final op = cur.v;
      p++;
      l = _Bin(op, l, _mul());
    }
    return l;
  }

  _E _mul() {
    var l = _unary();
    while (isOp('*') || isName('div') || isName('mod')) {
      final op = cur.v;
      p++;
      l = _Bin(op, l, _unary());
    }
    return l;
  }

  _E _unary() {
    if (isOp('-')) {
      p++;
      return _Neg(_unary());
    }
    return _union();
  }

  _E _union() {
    final first = _pathExpr();
    if (!isOp('|')) return first;
    final parts = [first];
    while (isOp('|')) {
      p++;
      parts.add(_pathExpr());
    }
    return _Union(parts);
  }

  static const _nodeTypes = {'node', 'text', 'comment', 'processing-instruction'};
  static const _axes = {
    'child', 'descendant', 'descendant-or-self', 'parent', 'ancestor', 'ancestor-or-self', 'following', 'following-sibling',
    'preceding', 'preceding-sibling', 'self', 'attribute'
  };

  bool get _startsStep {
    if (cur.t == _T.name) return true;
    if (cur.t == _T.op && (cur.v == '*' || cur.v == '@' || cur.v == '.' || cur.v == '..')) return true;
    return false;
  }

  _E _pathExpr() {
    // filter expression start: literal, number, ( expr ), function call (not a node-type test)
    if (cur.t == _T.str) {
      final v = _Lit(cur.v);
      p++;
      return _filterTail(v);
    }
    if (cur.t == _T.num) {
      final v = _Lit(double.parse(cur.v));
      p++;
      return _filterTail(v);
    }
    if (isOp('(')) {
      p++;
      final e = _or();
      if (!isOp(')')) throw XPathException('missing )');
      p++;
      return _filterTail(e);
    }
    if (cur.t == _T.name && toks[p + 1].t == _T.op && toks[p + 1].v == '(' && !_nodeTypes.contains(cur.v) && !_isExtStep(cur.v)) {
      final name = cur.v;
      p += 2;
      final args = <_E>[];
      if (!isOp(')')) {
        args.add(_or());
        while (isOp(',')) {
          p++;
          args.add(_or());
        }
      }
      if (!isOp(')')) throw XPathException('missing ) after arguments of $name');
      p++;
      return _filterTail(_Func(name, args));
    }
    // location path
    var absolute = false;
    final steps = <_Step>[];
    if (isOp('/')) {
      absolute = true;
      p++;
      if (!_startsStep) return _Path(null, true, steps); // just "/"
    } else if (isOp('//')) {
      absolute = true;
      p++;
      steps.add(_Step('descendant-or-self', 'node()', const []));
    }
    steps.add(_step());
    while (isOp('/') || isOp('//')) {
      if (cur.v == '//') steps.add(_Step('descendant-or-self', 'node()', const []));
      p++;
      steps.add(_step());
    }
    return _Path(null, absolute, steps);
  }

  static const _ext = {'allText', 'ownText', 'html', 'outerHtml', 'innerHtml'};
  bool _isExtStep(String n) => _ext.contains(n);

  _E _filterTail(_E base) {
    final preds = <_E>[];
    while (isOp('[')) {
      preds.add(_pred());
    }
    var e = preds.isEmpty ? base : _Filter(base, preds);
    if (isOp('/') || isOp('//')) {
      final steps = <_Step>[];
      while (isOp('/') || isOp('//')) {
        if (cur.v == '//') steps.add(_Step('descendant-or-self', 'node()', const []));
        p++;
        steps.add(_step());
      }
      e = _Path(e, false, steps);
    }
    return e;
  }

  _E _pred() {
    p++; // [
    final e = _or();
    if (!isOp(']')) throw XPathException('missing ]');
    p++;
    return e;
  }

  _Step _step() {
    if (isOp('.')) {
      p++;
      return _Step('self', 'node()', _preds());
    }
    if (isOp('..')) {
      p++;
      return _Step('parent', 'node()', _preds());
    }
    var axis = 'child';
    if (isOp('@')) {
      axis = 'attribute';
      p++;
    } else if (cur.t == _T.name && toks[p + 1].t == _T.op && toks[p + 1].v == '::') {
      axis = cur.v;
      if (!_axes.contains(axis)) throw XPathException('unknown axis $axis');
      p += 2;
    }
    String test;
    if (isOp('*')) {
      test = '*';
      p++;
    } else if (cur.t == _T.name) {
      final n = cur.v;
      p++;
      if (isOp('(')) {
        p++;
        // function-like node test / extension
        final args = <_E>[];
        if (!isOp(')')) {
          args.add(_or());
        }
        if (!isOp(')')) throw XPathException('missing ) in $n()');
        p++;
        if (_nodeTypes.contains(n)) {
          test = '$n()';
        } else if (_ext.contains(n)) {
          test = 'ext:$n';
        } else {
          throw XPathException('unsupported step function $n()');
        }
      } else {
        test = n;
      }
    } else {
      throw XPathException('step expected near "${cur.v}"');
    }
    return _Step(axis, test, _preds());
  }

  List<_E> _preds() {
    final preds = <_E>[];
    while (isOp('[')) {
      preds.add(_pred());
    }
    return preds;
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------------------------------------------------------
double _toNum(Object v) {
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v is String) return double.tryParse(v.trim()) ?? double.nan;
  if (v is List<XNode>) return v.isEmpty ? double.nan : _toNum(v.first.stringValue);
  return double.nan;
}

String _numToString(double d) {
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  if (d == d.truncateToDouble()) return d.toInt().toString();
  return d.toString();
}

String _toStr(Object v) {
  if (v is String) return v;
  if (v is num) return _numToString(v.toDouble());
  if (v is bool) return v ? 'true' : 'false';
  if (v is List<XNode>) return v.isEmpty ? '' : v.first.stringValue;
  return v.toString();
}

bool _toBool(Object v) {
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  if (v is List<XNode>) return v.isNotEmpty;
  return false;
}

bool _cmpAtoms(String op, Object a, Object b) {
  if (op == '=' || op == '!=') {
    bool eq;
    if (a is bool || b is bool) {
      eq = _toBool(a) == _toBool(b);
    } else if (a is num || b is num) {
      eq = _toNum(a) == _toNum(b);
    } else {
      eq = _toStr(a) == _toStr(b);
    }
    return op == '=' ? eq : !eq;
  }
  final x = _toNum(a), y = _toNum(b);
  switch (op) {
    case '<':
      return x < y;
    case '<=':
      return x <= y;
    case '>':
      return x > y;
    default:
      return x >= y;
  }
}

bool _cmp(String op, Object a, Object b) {
  if (a is List<XNode> && b is List<XNode>) {
    for (final x in a) {
      for (final y in b) {
        if (_cmpAtoms(op, x.stringValue, y.stringValue)) return true;
      }
    }
    return false;
  }
  if (a is List<XNode>) {
    if (b is bool) return _cmpAtoms(op, a.isNotEmpty, b);
    for (final x in a) {
      if (_cmpAtoms(op, b is num ? _toNum(x.stringValue) : x.stringValue, b)) return true;
    }
    return false;
  }
  if (b is List<XNode>) {
    if (a is bool) return _cmpAtoms(op, a, b.isNotEmpty);
    for (final y in b) {
      if (_cmpAtoms(op, a, a is num ? _toNum(y.stringValue) : y.stringValue)) return true;
    }
    return false;
  }
  return _cmpAtoms(op, a, b);
}

Iterable<dom.Node> _descendants(dom.Node n) sync* {
  for (final c in n.nodes) {
    yield c;
    yield* _descendants(c);
  }
}

List<XNode> _axisNodes(String axis, XNode ctx) {
  if (ctx.isAttr) {
    switch (axis) {
      case 'parent':
        return [XNode(ctx.owner!)];
      case 'self':
      case 'ancestor-or-self':
        return [ctx];
      default:
        if (axis == 'ancestor') {
          final out = <XNode>[];
          dom.Node? a = ctx.owner;
          while (a != null) {
            out.add(XNode(a));
            a = a.parentNode;
          }
          return out;
        }
        return [];
    }
  }
  final n = ctx.node!;
  switch (axis) {
    case 'child':
      return n.nodes.map(XNode.new).toList();
    case 'descendant':
      return _descendants(n).map(XNode.new).toList();
    case 'descendant-or-self':
      return [XNode(n), ..._descendants(n).map(XNode.new)];
    case 'self':
      return [ctx];
    case 'parent':
      final p = n.parentNode;
      return p == null ? [] : [XNode(p)];
    case 'ancestor':
    case 'ancestor-or-self':
      final out = <XNode>[];
      if (axis == 'ancestor-or-self') out.add(ctx);
      dom.Node? a = n.parentNode;
      while (a != null) {
        out.add(XNode(a));
        a = a.parentNode;
      }
      return out;
    case 'following-sibling':
    case 'preceding-sibling':
      final p = n.parentNode;
      if (p == null) return [];
      final i = p.nodes.indexOf(n);
      if (axis == 'following-sibling') return p.nodes.sublist(i + 1).map(XNode.new).toList();
      return p.nodes.sublist(0, i).reversed.map(XNode.new).toList();
    case 'following':
      final out = <XNode>[];
      dom.Node? cur = n;
      while (cur != null) {
        final p = cur.parentNode;
        if (p == null) break;
        final i = p.nodes.indexOf(cur);
        for (final s in p.nodes.sublist(i + 1)) {
          out.add(XNode(s));
          out.addAll(_descendants(s).map(XNode.new));
        }
        cur = p;
      }
      return out;
    case 'preceding':
      final out = <XNode>[];
      dom.Node? cur = n;
      while (cur != null) {
        final p = cur.parentNode;
        if (p == null) break;
        final i = p.nodes.indexOf(cur);
        for (final s in p.nodes.sublist(0, i).reversed) {
          final all = [XNode(s), ..._descendants(s).map(XNode.new)].reversed;
          out.addAll(all);
        }
        cur = p;
      }
      return out;
    case 'attribute':
      if (n is! dom.Element) return [];
      var pos = 0;
      return [for (final e in n.attributes.entries) XNode.attr(n, e.key.toString(), e.value, pos++)];
  }
  return [];
}

bool _testNode(String test, String axis, XNode n) {
  switch (test) {
    case 'node()':
      return true;
    case 'text()':
      return n.isText;
    case 'comment()':
      return !n.isAttr && n.node is dom.Comment;
    case 'processing-instruction()':
      return false;
    case '*':
      return axis == 'attribute' ? n.isAttr : n.isElement;
  }
  if (axis == 'attribute') return n.isAttr && n.attrName!.toLowerCase() == test.toLowerCase();
  final e = n.element;
  if (e == null) return false;
  final name = (e.localName ?? '').toLowerCase();
  final t = test.toLowerCase();
  if (name == t) return true;
  final colon = t.indexOf(':');
  return colon > 0 && name == t.substring(colon + 1);
}

const Set<String> _reverseAxes = {'ancestor', 'ancestor-or-self', 'preceding', 'preceding-sibling'};

List<XNode> _applyStep(_Step s, List<XNode> input, _Env env) {
  final seen = <Object, XNode>{};
  var multi = input.length > 1;
  for (final ctx in input) {
    if (s.test.startsWith('ext:')) {
      final name = s.test.substring(4);
      final n = ctx.node;
      if (n == null) continue;
      String v;
      switch (name) {
        case 'allText':
          v = n is dom.Element || n is dom.Document ? jText(n) : ctx.stringValue;
          break;
        case 'ownText':
          v = jOwnText(n);
          break;
        case 'html':
        case 'innerHtml':
          v = jInnerHtml(n);
          break;
        default:
          v = jOuterHtml(n);
      }
      final t = XNode.text(v);
      seen[t.key] = t;
      continue;
    }
    var nodes = _axisNodes(s.axis, ctx).where((x) => _testNode(s.test, s.axis, x)).toList();
    for (final pr in s.preds) {
      nodes = _filterByPredicate(nodes, pr, env);
    }
    for (final x in nodes) {
      seen[x.key] = x;
    }
  }
  final list = seen.values.toList();
  if (multi || _reverseAxes.contains(s.axis) || s.test.startsWith('ext:')) {
    if (list.length > 1 && !s.test.startsWith('ext:')) list.sort((a, b) => env.orderOf(a).compareTo(env.orderOf(b)));
  }
  return list;
}

List<XNode> _filterByPredicate(List<XNode> nodes, _E pred, _Env env) {
  final out = <XNode>[];
  final size = nodes.length;
  for (var i = 0; i < size; i++) {
    final v = pred.eval(_Ctx(nodes[i], i + 1, size, env));
    final keep = v is num ? v == i + 1 : _toBool(v);
    if (keep) out.add(nodes[i]);
  }
  return out;
}

Object _callFunction(String name, List<_E> args, _Ctx c) {
  Object arg(int i) => args[i].eval(c);
  String strArg(int i) => args.length > i ? _toStr(arg(i)) : c.node.stringValue;
  switch (name) {
    case 'last':
      return c.size.toDouble();
    case 'position':
      return c.position.toDouble();
    case 'count':
      final v = arg(0);
      return v is List<XNode> ? v.length.toDouble() : 0.0;
    case 'true':
      return true;
    case 'false':
      return false;
    case 'not':
      return !_toBool(arg(0));
    case 'boolean':
      return _toBool(arg(0));
    case 'string':
      return strArg(0);
    case 'number':
      return args.isEmpty ? _toNum(c.node.stringValue) : _toNum(arg(0));
    case 'concat':
      return args.map((a) => _toStr(a.eval(c))).join();
    case 'contains':
      return strArg(0).contains(_toStr(arg(1)));
    case 'starts-with':
      return strArg(0).startsWith(_toStr(arg(1)));
    case 'ends-with':
      return strArg(0).endsWith(_toStr(arg(1)));
    case 'substring-before':
      final s = strArg(0), t = _toStr(arg(1));
      final i = s.indexOf(t);
      return i < 0 ? '' : s.substring(0, i);
    case 'substring-after':
      final s = strArg(0), t = _toStr(arg(1));
      final i = s.indexOf(t);
      return i < 0 ? '' : s.substring(i + t.length);
    case 'substring':
      final s = strArg(0);
      final start = _toNum(arg(1)).round();
      if (args.length > 2) {
        final len = _toNum(arg(2)).round();
        final from = start < 1 ? 1 : start;
        final to = start + len;
        if (to <= from) return '';
        return s.substring((from - 1).clamp(0, s.length), (to - 1).clamp(0, s.length));
      }
      return s.substring((start < 1 ? 0 : start - 1).clamp(0, s.length));
    case 'string-length':
      return strArg(0).length.toDouble();
    case 'normalize-space':
      return strArg(0).trim().replaceAll(RegExp(r'\s+'), ' ');
    case 'translate':
      final s = strArg(0), from = _toStr(arg(1)), to = _toStr(arg(2));
      final sb = StringBuffer();
      for (final ch in s.split('')) {
        final i = from.indexOf(ch);
        if (i < 0) {
          sb.write(ch);
        } else if (i < to.length) {
          sb.write(to[i]);
        }
      }
      return sb.toString();
    case 'lower-case':
      return strArg(0).toLowerCase();
    case 'upper-case':
      return strArg(0).toUpperCase();
    case 'matches':
      return JavaRegex.compile(_toStr(arg(1))).hasMatch(strArg(0));
    case 'replace':
      return JavaRegex.replaceAll(strArg(0), JavaRegex.compile(_toStr(arg(1))), _toStr(arg(2)));
    case 'name':
    case 'local-name':
      XNode n = c.node;
      if (args.isNotEmpty) {
        final v = arg(0);
        if (v is List<XNode>) {
          if (v.isEmpty) return '';
          n = v.first;
        }
      }
      if (n.isAttr) return n.attrName!;
      return (n.element?.localName ?? '');
    case 'sum':
      final v = arg(0);
      if (v is! List<XNode>) return 0.0;
      return v.fold<double>(0, (a, b) => a + _toNum(b.stringValue));
    case 'floor':
      return _toNum(arg(0)).floorToDouble();
    case 'ceiling':
      return _toNum(arg(0)).ceilToDouble();
    case 'round':
      return _toNum(arg(0)).roundToDouble();
    case 'text':
      return c.node.stringValue;
  }
  throw XPathException('unknown function $name()');
}

class XPath {
  final _E _expr;
  final String source;
  XPath._(this._expr, this.source);

  static final Map<String, XPath> _cache = {};

  static XPath compile(String expr) {
    final hit = _cache[expr];
    if (hit != null) return hit;
    final e = _Parser(_tokenize(expr.trim())).parse();
    final x = XPath._(e, expr);
    if (_cache.length > 500) _cache.clear();
    _cache[expr] = x;
    return x;
  }

  /// Evaluates against [context]. Absolute paths (`/x`, `//x`) start at the document when [context] belongs to a document being
  /// queried as a whole, and at [context] itself when it is an element (JsoupXpath behaviour for list items).
  /// Result: `List<XNode>`, `String`, `double` or `bool`.
  Object evaluate(dom.Node context) {
    final env = _Env(context);
    return _expr.eval(_Ctx(XNode(context), 1, 1, env));
  }

  /// Node-set result (a scalar result becomes a single synthetic text node).
  List<XNode> select(dom.Node context) {
    final v = evaluate(context);
    if (v is List<XNode>) return v;
    return [XNode.text(_toStr(v))];
  }
}
