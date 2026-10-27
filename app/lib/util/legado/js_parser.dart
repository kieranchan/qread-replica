// util/legado/js_parser.dart - lexer, AST and parser of the pure Dart JavaScript interpreter (script_engine.dart). The original ships a
// similar mini interpreter for HarmonyOS (class `_ArkTsJsRunner`): var/let/const, function and arrow functions, template literals,
// if/else/for/while/try-catch, regex literals, `new X(..)`, destructuring. Supported here as well: switch, do-while, for-in/for-of,
// labelled break/continue, spread/rest, optional chaining, `??`, `**`, getters/setters in object literals, default parameters.
// Not supported: classes, generators, async/await, modules, `with`, tagged templates.

class JsSyntaxError implements Exception {
  final String message;
  JsSyntaxError(this.message);
  @override
  String toString() => 'SyntaxError: $message';
}

// ---------------------------------------------------------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------------------------------------------------------
abstract class Node {}

abstract class Expr extends Node {}

abstract class Stmt extends Node {}

class NumLit extends Expr {
  final num v;
  NumLit(this.v);
}

class StrLit extends Expr {
  final String v;
  StrLit(this.v);
}

class TemplateLit extends Expr {
  final List<String> quasis;
  final List<Expr> exprs;
  TemplateLit(this.quasis, this.exprs);
}

class RegexLit extends Expr {
  final String source;
  final String flags;
  RegexLit(this.source, this.flags);
}

class Ident extends Expr {
  final String name;
  Ident(this.name);
}

class ThisExpr extends Expr {}

class ArrayLit extends Expr {
  final List<Expr?> elements; // null = hole; Spread allowed
  ArrayLit(this.elements);
}

class PropDef {
  final Expr? computedKey;
  final String? key;
  final Expr? value; // null for spread when [spread] set
  final String kind; // init | get | set | spread
  PropDef(this.key, this.value, this.kind, [this.computedKey]);
}

class ObjectLit extends Expr {
  final List<PropDef> props;
  ObjectLit(this.props);
}

class FuncNode {
  final String? name;
  final List<Pat> params;
  final List<Stmt> body;
  final Expr? exprBody; // arrow with expression body
  final bool isArrow;
  FuncNode(this.name, this.params, this.body, this.exprBody, this.isArrow);
}

class FuncExpr extends Expr {
  final FuncNode fn;
  FuncExpr(this.fn);
}

class Unary extends Expr {
  final String op;
  final Expr arg;
  Unary(this.op, this.arg);
}

class Update extends Expr {
  final String op; // ++ --
  final bool prefix;
  final Expr target;
  Update(this.op, this.prefix, this.target);
}

class Binary extends Expr {
  final String op;
  final Expr l, r;
  Binary(this.op, this.l, this.r);
}

class Logical extends Expr {
  final String op; // && || ??
  final Expr l, r;
  Logical(this.op, this.l, this.r);
}

class Assign extends Expr {
  final String op; // = += ...
  final Node target; // Expr (Ident/Member) or Pat
  final Expr value;
  Assign(this.op, this.target, this.value);
}

class Cond extends Expr {
  final Expr test, a, b;
  Cond(this.test, this.a, this.b);
}

class Call extends Expr {
  final Expr callee;
  final List<Expr> args;
  final bool optional;
  Call(this.callee, this.args, this.optional);
}

class NewExpr extends Expr {
  final Expr callee;
  final List<Expr> args;
  NewExpr(this.callee, this.args);
}

class Member extends Expr {
  final Expr obj;
  final Expr? computed;
  final String? name;
  final bool optional;
  Member(this.obj, this.name, this.computed, this.optional);
}

class Seq extends Expr {
  final List<Expr> list;
  Seq(this.list);
}

class Spread extends Expr {
  final Expr arg;
  Spread(this.arg);
}

// patterns -------------------------------------------------------------------------------------------------------------------
abstract class Pat extends Node {}

class IdentPat extends Pat {
  final String name;
  IdentPat(this.name);
}

class DefaultPat extends Pat {
  final Pat target;
  final Expr def;
  DefaultPat(this.target, this.def);
}

class RestPat extends Pat {
  final Pat target;
  RestPat(this.target);
}

class ArrayPat extends Pat {
  final List<Pat?> elements;
  ArrayPat(this.elements);
}

class ObjPatProp {
  final String? key;
  final Expr? computedKey;
  final Pat target;
  ObjPatProp(this.key, this.computedKey, this.target);
}

class ObjectPat extends Pat {
  final List<ObjPatProp> props;
  final Pat? rest;
  ObjectPat(this.props, this.rest);
}

/// An arbitrary assignable expression used as a pattern target (`a.b = ...` inside destructuring).
class ExprPat extends Pat {
  final Expr expr;
  ExprPat(this.expr);
}

// statements -----------------------------------------------------------------------------------------------------------------
class VarDecl extends Stmt {
  final String kind; // var let const
  final List<(Pat, Expr?)> decls;
  VarDecl(this.kind, this.decls);
}

class ExprStmt extends Stmt {
  final Expr e;
  ExprStmt(this.e);
}

class Block extends Stmt {
  final List<Stmt> body;
  Block(this.body);
}

class If extends Stmt {
  final Expr test;
  final Stmt a;
  final Stmt? b;
  If(this.test, this.a, this.b);
}

class For extends Stmt {
  final Node? init; // VarDecl or Expr
  final Expr? test;
  final Expr? update;
  final Stmt body;
  For(this.init, this.test, this.update, this.body);
}

class ForIn extends Stmt {
  final String? declKind; // var/let/const or null
  final Pat target;
  final Expr right;
  final Stmt body;
  final bool isOf;
  ForIn(this.declKind, this.target, this.right, this.body, this.isOf);
}

class While extends Stmt {
  final Expr test;
  final Stmt body;
  While(this.test, this.body);
}

class DoWhile extends Stmt {
  final Stmt body;
  final Expr test;
  DoWhile(this.body, this.test);
}

class Return extends Stmt {
  final Expr? arg;
  Return(this.arg);
}

class Break extends Stmt {
  final String? label;
  Break(this.label);
}

class Continue extends Stmt {
  final String? label;
  Continue(this.label);
}

class Throw extends Stmt {
  final Expr arg;
  Throw(this.arg);
}

class Try extends Stmt {
  final Block block;
  final Pat? param;
  final Block? handler;
  final Block? finalizer;
  Try(this.block, this.param, this.handler, this.finalizer);
}

class SwitchCase {
  final Expr? test;
  final List<Stmt> body;
  SwitchCase(this.test, this.body);
}

class Switch extends Stmt {
  final Expr disc;
  final List<SwitchCase> cases;
  Switch(this.disc, this.cases);
}

class FuncDecl extends Stmt {
  final FuncNode fn;
  FuncDecl(this.fn);
}

class Empty extends Stmt {}

class Labeled extends Stmt {
  final String label;
  final Stmt body;
  Labeled(this.label, this.body);
}

// ---------------------------------------------------------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------------------------------------------------------
enum T { num, str, tmpl, regex, name, punct, eof }

class Tok {
  final T t;
  final String v;
  final bool nl; // newline before this token
  final num? n;
  final List<String>? parts; // template cooked strings
  final List<String>? exprs; // template expression sources
  final String? flags;
  final int pos;
  Tok(this.t, this.v, this.nl, this.pos, {this.n, this.parts, this.exprs, this.flags});
  @override
  String toString() => '$t($v)';
}

const Set<String> _regexAfterKeywords = {'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void', 'throw', 'case', 'do', 'else', 'yield'};

List<Tok> tokenize(String s) {
  final out = <Tok>[];
  var i = 0;
  var nl = false;
  bool isIdStart(int c) => (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x24 || c == 0x5f || c >= 0x80;
  bool isIdPart(int c) => isIdStart(c) || (c >= 0x30 && c <= 0x39);
  bool regexAllowed() {
    if (out.isEmpty) return true;
    final p = out.last;
    if (p.t == T.num || p.t == T.str || p.t == T.tmpl || p.t == T.regex) return false;
    if (p.t == T.name) return _regexAfterKeywords.contains(p.v);
    return !(p.v == ')' || p.v == ']' || p.v == '}');
  }

  const puncts = [
    '>>>=', '...', '===', '!==', '**=', '<<=', '>>=', '>>>', '&&=', '||=', '??=', '=>', '==', '!=', '<=', '>=', '&&', '||', '??', '?.',
    '++', '--', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '**',
  ];

  String readEscape() {
    // s[i] is the char after the backslash
    final c = s[i];
    i++;
    switch (c) {
      case 'n':
        return '\n';
      case 't':
        return '\t';
      case 'r':
        return '\r';
      case 'b':
        return '\b';
      case 'f':
        return '\f';
      case 'v':
        return '\v';
      case '0':
        return '\u0000';
      case 'x':
        final h = s.substring(i, i + 2);
        i += 2;
        return String.fromCharCode(int.parse(h, radix: 16));
      case 'u':
        if (s[i] == '{') {
          final e = s.indexOf('}', i);
          final cp = int.parse(s.substring(i + 1, e), radix: 16);
          i = e + 1;
          return String.fromCharCode(cp);
        }
        final h = s.substring(i, i + 4);
        i += 4;
        return String.fromCharCode(int.parse(h, radix: 16));
      case '\r':
        if (i < s.length && s[i] == '\n') i++;
        return '';
      case '\n':
        return '';
      default:
        return c;
    }
  }

  while (true) {
    // whitespace and comments
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x0a || c == 0x0d || c == 0x2028 || c == 0x2029) {
        nl = true;
        i++;
      } else if (c == 0x20 || c == 0x09 || c == 0x0b || c == 0x0c || c == 0xa0 || c == 0xfeff || c == 0x3000) {
        i++;
      } else if (c == 0x2f && i + 1 < s.length && s.codeUnitAt(i + 1) == 0x2f) {
        while (i < s.length && s.codeUnitAt(i) != 0x0a && s.codeUnitAt(i) != 0x0d) {
          i++;
        }
      } else if (c == 0x2f && i + 1 < s.length && s.codeUnitAt(i + 1) == 0x2a) {
        final e = s.indexOf('*/', i + 2);
        final seg = e < 0 ? s.substring(i) : s.substring(i, e);
        if (seg.contains('\n')) nl = true;
        i = e < 0 ? s.length : e + 2;
      } else {
        break;
      }
    }
    if (i >= s.length) {
      out.add(Tok(T.eof, '', nl, i));
      return out;
    }
    final start = i;
    final c = s.codeUnitAt(i);
    if (isIdStart(c)) {
      while (i < s.length && isIdPart(s.codeUnitAt(i))) {
        i++;
      }
      out.add(Tok(T.name, s.substring(start, i), nl, start));
    } else if ((c >= 0x30 && c <= 0x39) || (c == 0x2e && i + 1 < s.length && s.codeUnitAt(i + 1) >= 0x30 && s.codeUnitAt(i + 1) <= 0x39)) {
      num v;
      if (c == 0x30 && i + 1 < s.length && (s[i + 1] == 'x' || s[i + 1] == 'X')) {
        i += 2;
        final b = i;
        while (i < s.length && RegExp(r'[0-9a-fA-F]').hasMatch(s[i])) {
          i++;
        }
        v = int.parse(s.substring(b, i), radix: 16);
      } else if (c == 0x30 && i + 1 < s.length && (s[i + 1] == 'b' || s[i + 1] == 'B')) {
        i += 2;
        final b = i;
        while (i < s.length && (s[i] == '0' || s[i] == '1')) {
          i++;
        }
        v = int.parse(s.substring(b, i), radix: 2);
      } else if (c == 0x30 && i + 1 < s.length && (s[i + 1] == 'o' || s[i + 1] == 'O')) {
        i += 2;
        final b = i;
        while (i < s.length && RegExp(r'[0-7]').hasMatch(s[i])) {
          i++;
        }
        v = int.parse(s.substring(b, i), radix: 8);
      } else {
        while (i < s.length && s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39) {
          i++;
        }
        if (i < s.length && s[i] == '.') {
          i++;
          while (i < s.length && s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39) {
            i++;
          }
        }
        if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
          var j = i + 1;
          if (j < s.length && (s[j] == '+' || s[j] == '-')) j++;
          if (j < s.length && s.codeUnitAt(j) >= 0x30 && s.codeUnitAt(j) <= 0x39) {
            while (j < s.length && s.codeUnitAt(j) >= 0x30 && s.codeUnitAt(j) <= 0x39) {
              j++;
            }
            i = j;
          }
        }
        final txt = s.substring(start, i);
        final d = double.parse(txt);
        v = (d == d.truncateToDouble() && d.abs() < 9007199254740992) ? d.toInt() : d;
      }
      out.add(Tok(T.num, s.substring(start, i), nl, start, n: v));
    } else if (c == 0x22 || c == 0x27) {
      final q = s[i];
      i++;
      final sb = StringBuffer();
      while (i < s.length && s[i] != q) {
        if (s[i] == '\\') {
          i++;
          sb.write(readEscape());
        } else {
          sb.write(s[i]);
          i++;
        }
      }
      if (i >= s.length) throw JsSyntaxError('unterminated string literal');
      i++;
      out.add(Tok(T.str, sb.toString(), nl, start));
    } else if (c == 0x60) {
      i++;
      final parts = <String>[];
      final exprs = <String>[];
      var sb = StringBuffer();
      while (i < s.length && s[i] != '`') {
        if (s[i] == '\\') {
          i++;
          sb.write(readEscape());
        } else if (s[i] == r'$' && i + 1 < s.length && s[i + 1] == '{') {
          parts.add(sb.toString());
          sb = StringBuffer();
          i += 2;
          var depth = 1;
          final b = i;
          while (i < s.length && depth > 0) {
            final ch = s[i];
            if (ch == '{') {
              depth++;
            } else if (ch == '}') {
              depth--;
              if (depth == 0) break;
            } else if (ch == '"' || ch == "'" || ch == '`') {
              final q = ch;
              i++;
              while (i < s.length && s[i] != q) {
                if (s[i] == '\\') i++;
                i++;
              }
            }
            i++;
          }
          exprs.add(s.substring(b, i));
          i++; // }
        } else {
          sb.write(s[i]);
          i++;
        }
      }
      if (i >= s.length) throw JsSyntaxError('unterminated template literal');
      i++;
      parts.add(sb.toString());
      out.add(Tok(T.tmpl, '`', nl, start, parts: parts, exprs: exprs));
    } else if (c == 0x2f && regexAllowed()) {
      i++;
      var inClass = false;
      final b = i;
      while (i < s.length) {
        final ch = s[i];
        if (ch == '\\') {
          i += 2;
          continue;
        }
        if (ch == '[') {
          inClass = true;
        } else if (ch == ']') {
          inClass = false;
        } else if (ch == '/' && !inClass) {
          break;
        } else if (ch == '\n') {
          throw JsSyntaxError('unterminated regular expression');
        }
        i++;
      }
      final body = s.substring(b, i);
      i++;
      final fb = i;
      while (i < s.length && isIdPart(s.codeUnitAt(i))) {
        i++;
      }
      out.add(Tok(T.regex, body, nl, start, flags: s.substring(fb, i)));
    } else {
      String? p;
      for (final pp in puncts) {
        if (s.startsWith(pp, i)) {
          p = pp;
          break;
        }
      }
      if (p == '?.' && i + 2 < s.length && s.codeUnitAt(i + 2) >= 0x30 && s.codeUnitAt(i + 2) <= 0x39) p = null;
      p ??= s[i];
      if (!'{}()[];,<>+-*/%&|^!~?:=.@#'.contains(p[0])) throw JsSyntaxError('unexpected character "${s[i]}"');
      i += p.length;
      out.add(Tok(T.punct, p, nl, start));
    }
    nl = false;
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------------------------------------------------------
class JsParser {
  final List<Tok> toks;
  int p = 0;
  JsParser(String src) : toks = tokenize(src);

  Tok get cur => toks[p];
  Tok peek([int n = 1]) => toks[(p + n) < toks.length ? p + n : toks.length - 1];
  bool isP(String v) => cur.t == T.punct && cur.v == v;
  bool isK(String v) => cur.t == T.name && cur.v == v;

  Never fail([String? msg]) => throw JsSyntaxError(msg ?? 'unexpected token ${cur.t == T.eof ? 'end of input' : '"${cur.v}"'}');

  void expectP(String v) {
    if (!isP(v)) fail('expected "$v" but found "${cur.v}"');
    p++;
  }

  bool eatP(String v) {
    if (isP(v)) {
      p++;
      return true;
    }
    return false;
  }

  bool eatK(String v) {
    if (isK(v)) {
      p++;
      return true;
    }
    return false;
  }

  List<Stmt> parseProgram() {
    final body = <Stmt>[];
    while (cur.t != T.eof) {
      body.add(parseStatement());
    }
    return body;
  }

  void _semi() {
    if (eatP(';')) return;
    if (isP('}') || cur.t == T.eof || cur.nl) return;
    fail();
  }

  Stmt parseStatement() {
    final t = cur;
    if (t.t == T.punct) {
      if (t.v == '{') return parseBlock();
      if (t.v == ';') {
        p++;
        return Empty();
      }
    }
    if (t.t == T.name) {
      switch (t.v) {
        case 'var':
        case 'const':
          {
            final d = _varDecl();
            _semi();
            return d;
          }
        case 'let':
          if (peek().t == T.name || (peek().t == T.punct && (peek().v == '[' || peek().v == '{'))) {
            final d = _varDecl();
            _semi();
            return d;
          }
          break;
        case 'function':
          if (peek().t == T.name) {
            p++;
            final name = cur.v;
            p++;
            return FuncDecl(_funcRest(name, false));
          }
          break;
        case 'if':
          {
            p++;
            expectP('(');
            final test = parseExpression();
            expectP(')');
            final a = parseStatement();
            Stmt? b;
            if (eatK('else')) b = parseStatement();
            return If(test, a, b);
          }
        case 'for':
          return _parseFor();
        case 'while':
          {
            p++;
            expectP('(');
            final test = parseExpression();
            expectP(')');
            return While(test, parseStatement());
          }
        case 'do':
          {
            p++;
            final body = parseStatement();
            if (!eatK('while')) fail('expected while');
            expectP('(');
            final test = parseExpression();
            expectP(')');
            eatP(';');
            return DoWhile(body, test);
          }
        case 'return':
          {
            p++;
            Expr? arg;
            if (!isP(';') && !isP('}') && cur.t != T.eof && !cur.nl) arg = parseExpression();
            _semi();
            return Return(arg);
          }
        case 'break':
        case 'continue':
          {
            p++;
            String? label;
            if (cur.t == T.name && !cur.nl) {
              label = cur.v;
              p++;
            }
            _semi();
            return t.v == 'break' ? Break(label) : Continue(label);
          }
        case 'throw':
          {
            p++;
            final e = parseExpression();
            _semi();
            return Throw(e);
          }
        case 'try':
          return _parseTry();
        case 'switch':
          return _parseSwitch();
      }
      if (peek().t == T.punct && peek().v == ':' && !const {'default', 'case'}.contains(t.v)) {
        p += 2;
        return Labeled(t.v, parseStatement());
      }
    }
    final e = parseExpression();
    _semi();
    return ExprStmt(e);
  }

  Block parseBlock() {
    expectP('{');
    final body = <Stmt>[];
    while (!isP('}')) {
      if (cur.t == T.eof) fail('unterminated block');
      body.add(parseStatement());
    }
    p++;
    return Block(body);
  }

  VarDecl _varDecl() {
    final kind = cur.v;
    p++;
    final decls = <(Pat, Expr?)>[];
    do {
      final target = parseBindingTarget();
      Expr? init;
      if (eatP('=')) init = parseAssign();
      decls.add((target, init));
    } while (eatP(','));
    return VarDecl(kind, decls);
  }

  Stmt _parseFor() {
    p++;
    expectP('(');
    Node? init;
    if (isP(';')) {
      // no init
    } else if (isK('var') || isK('const') || (isK('let') && (peek().t == T.name || peek().v == '[' || peek().v == '{'))) {
      final kind = cur.v;
      final save = p;
      p++;
      final target = parseBindingTarget();
      if (isK('of') || isK('in')) {
        final isOf = cur.v == 'of';
        p++;
        final right = isOf ? parseAssign() : parseExpression();
        expectP(')');
        return ForIn(kind, target, right, parseStatement(), isOf);
      }
      p = save;
      init = _varDecl();
    } else {
      final e = _parseExprNoIn();
      if (isK('of') || isK('in')) {
        final isOf = cur.v == 'of';
        p++;
        final right = isOf ? parseAssign() : parseExpression();
        expectP(')');
        return ForIn(null, _toPattern(e), right, parseStatement(), isOf);
      }
      init = e;
    }
    expectP(';');
    Expr? test;
    if (!isP(';')) test = parseExpression();
    expectP(';');
    Expr? update;
    if (!isP(')')) update = parseExpression();
    expectP(')');
    return For(init, test, update, parseStatement());
  }

  Expr _parseExprNoIn() {
    _noIn = true;
    try {
      return parseExpression();
    } finally {
      _noIn = false;
    }
  }

  bool _noIn = false;

  Stmt _parseTry() {
    p++;
    final block = parseBlock();
    Pat? param;
    Block? handler;
    Block? fin;
    if (eatK('catch')) {
      if (eatP('(')) {
        param = parseBindingTarget();
        expectP(')');
      }
      handler = parseBlock();
    }
    if (eatK('finally')) fin = parseBlock();
    if (handler == null && fin == null) fail('missing catch or finally after try');
    return Try(block, param, handler, fin);
  }

  Stmt _parseSwitch() {
    p++;
    expectP('(');
    final disc = parseExpression();
    expectP(')');
    expectP('{');
    final cases = <SwitchCase>[];
    while (!isP('}')) {
      Expr? test;
      if (eatK('case')) {
        test = parseExpression();
      } else if (eatK('default')) {
        test = null;
      } else {
        fail();
      }
      expectP(':');
      final body = <Stmt>[];
      while (!isP('}') && !isK('case') && !isK('default')) {
        body.add(parseStatement());
      }
      cases.add(SwitchCase(test, body));
    }
    p++;
    return Switch(disc, cases);
  }

  // functions -------------------------------------------------------------------------------------------------------------------
  FuncNode _funcRest(String? name, bool isExpr) {
    expectP('(');
    final params = _params();
    final body = parseBlock().body;
    return FuncNode(name, params, body, null, false);
  }

  List<Pat> _params() {
    final params = <Pat>[];
    while (!isP(')')) {
      if (eatP('...')) {
        params.add(RestPat(parseBindingTarget()));
      } else {
        var t = parseBindingTarget();
        if (eatP('=')) t = DefaultPat(t, parseAssign());
        params.add(t);
      }
      if (!eatP(',')) break;
    }
    expectP(')');
    return params;
  }

  Pat parseBindingTarget() {
    if (isP('[')) {
      p++;
      final els = <Pat?>[];
      while (!isP(']')) {
        if (isP(',')) {
          p++;
          els.add(null);
          continue;
        }
        if (eatP('...')) {
          els.add(RestPat(parseBindingTarget()));
        } else {
          var t = parseBindingTarget();
          if (eatP('=')) t = DefaultPat(t, parseAssign());
          els.add(t);
        }
        if (!eatP(',')) break;
      }
      expectP(']');
      return ArrayPat(els);
    }
    if (isP('{')) {
      p++;
      final props = <ObjPatProp>[];
      Pat? rest;
      while (!isP('}')) {
        if (eatP('...')) {
          rest = parseBindingTarget();
        } else {
          String? key;
          Expr? ck;
          if (isP('[')) {
            p++;
            ck = parseAssign();
            expectP(']');
          } else if (cur.t == T.name || cur.t == T.str || cur.t == T.num) {
            key = cur.t == T.num ? _numKey(cur.n!) : cur.v;
            p++;
          } else {
            fail();
          }
          Pat target;
          if (eatP(':')) {
            target = parseBindingTarget();
          } else {
            target = IdentPat(key!);
          }
          if (eatP('=')) target = DefaultPat(target, parseAssign());
          props.add(ObjPatProp(key, ck, target));
        }
        if (!eatP(',')) break;
      }
      expectP('}');
      return ObjectPat(props, rest);
    }
    if (cur.t != T.name) fail();
    final n = cur.v;
    p++;
    return IdentPat(n);
  }

  static String _numKey(num n) => n == n.truncate() ? n.toInt().toString() : n.toString();

  // expressions -----------------------------------------------------------------------------------------------------------------
  Expr parseExpression() {
    final e = parseAssign();
    if (isP(',')) {
      final list = [e];
      while (eatP(',')) {
        list.add(parseAssign());
      }
      return Seq(list);
    }
    return e;
  }

  bool _isArrowAhead() {
    if (cur.t == T.name && peek().t == T.punct && peek().v == '=>') return true;
    if (isP('(')) {
      var depth = 0;
      var i = p;
      while (i < toks.length) {
        final t = toks[i];
        if (t.t == T.punct) {
          if (t.v == '(' || t.v == '[' || t.v == '{') depth++;
          if (t.v == ')' || t.v == ']' || t.v == '}') {
            depth--;
            if (depth == 0) {
              final n = i + 1 < toks.length ? toks[i + 1] : null;
              return n != null && n.t == T.punct && n.v == '=>';
            }
          }
        } else if (t.t == T.eof) {
          return false;
        }
        i++;
      }
    }
    return false;
  }

  Expr parseAssign() {
    if (_isArrowAhead()) return _arrow();
    final left = _parseConditional();
    if (cur.t == T.punct) {
      final op = cur.v;
      if (op == '=' || (op.length >= 2 && op.endsWith('=') && !const {'==', '===', '!=', '!==', '<=', '>=', '=>'}.contains(op))) {
        p++;
        final value = parseAssign();
        if (op == '=' && (left is ArrayLit || left is ObjectLit)) return Assign(op, _toPattern(left), value);
        if (left is! Ident && left is! Member) throw JsSyntaxError('invalid assignment target');
        return Assign(op, left, value);
      }
    }
    return left;
  }

  Pat _toPattern(Expr e) {
    if (e is Ident) return IdentPat(e.name);
    if (e is Member) return ExprPat(e);
    if (e is Assign && e.op == '=' && e.target is Ident) return DefaultPat(IdentPat((e.target as Ident).name), e.value);
    if (e is ArrayLit) {
      return ArrayPat([
        for (final x in e.elements)
          x == null ? null : (x is Spread ? RestPat(_toPattern(x.arg)) : _toPattern(x))
      ]);
    }
    if (e is ObjectLit) {
      final props = <ObjPatProp>[];
      Pat? rest;
      for (final pd in e.props) {
        if (pd.kind == 'spread') {
          rest = _toPattern(pd.value!);
        } else {
          props.add(ObjPatProp(pd.key, pd.computedKey, _toPattern(pd.value!)));
        }
      }
      return ObjectPat(props, rest);
    }
    throw JsSyntaxError('invalid destructuring target');
  }

  Expr _arrow() {
    List<Pat> params;
    if (cur.t == T.name) {
      params = [IdentPat(cur.v)];
      p++;
    } else {
      expectP('(');
      params = _params();
    }
    expectP('=>');
    if (isP('{')) {
      final body = parseBlock().body;
      return FuncExpr(FuncNode(null, params, body, null, true));
    }
    final e = parseAssign();
    return FuncExpr(FuncNode(null, params, const [], e, true));
  }

  Expr _parseConditional() {
    final test = _binary(0);
    if (isP('?')) {
      p++;
      final saveNoIn = _noIn;
      _noIn = false;
      final a = parseAssign();
      _noIn = saveNoIn;
      expectP(':');
      final b = parseAssign();
      return Cond(test, a, b);
    }
    return test;
  }

  static const Map<String, int> _prec = {
    '??': 1, '||': 2, '&&': 3, '|': 4, '^': 5, '&': 6, '==': 7, '!=': 7, '===': 7, '!==': 7, '<': 8, '>': 8, '<=': 8, '>=': 8,
    'instanceof': 8, 'in': 8, '<<': 9, '>>': 9, '>>>': 9, '+': 10, '-': 10, '*': 11, '/': 11, '%': 11, '**': 12,
  };

  Expr _binary(int minPrec) {
    var left = _unary();
    while (true) {
      String? op;
      if (cur.t == T.punct && _prec.containsKey(cur.v)) {
        op = cur.v;
      } else if (cur.t == T.name && (cur.v == 'instanceof' || (cur.v == 'in' && !_noIn))) {
        op = cur.v;
      }
      if (op == null) return left;
      final prec = _prec[op]!;
      if (prec < minPrec || prec == 0) return left;
      if (prec < minPrec) return left;
      p++;
      final right = op == '**' ? _binary(prec) : _binary(prec + 1);
      if (op == '&&' || op == '||' || op == '??') {
        left = Logical(op, left, right);
      } else {
        left = Binary(op, left, right);
      }
    }
  }

  Expr _unary() {
    final t = cur;
    if (t.t == T.punct) {
      switch (t.v) {
        case '!':
        case '-':
        case '+':
        case '~':
          p++;
          return Unary(t.v, _unary());
        case '++':
        case '--':
          p++;
          return Update(t.v, true, _unary());
      }
    } else if (t.t == T.name) {
      if (t.v == 'typeof' || t.v == 'void' || t.v == 'delete') {
        p++;
        return Unary(t.v, _unary());
      }
    }
    return _postfix();
  }

  Expr _postfix() {
    final e = _leftHandSide();
    if (cur.t == T.punct && (cur.v == '++' || cur.v == '--') && !cur.nl) {
      final op = cur.v;
      p++;
      return Update(op, false, e);
    }
    return e;
  }

  List<Expr> _args() {
    final args = <Expr>[];
    while (!isP(')')) {
      if (eatP('...')) {
        args.add(Spread(parseAssign()));
      } else {
        args.add(parseAssign());
      }
      if (!eatP(',')) break;
    }
    expectP(')');
    return args;
  }

  Expr _leftHandSide() {
    Expr e;
    if (isK('new')) {
      p++;
      if (isP('.')) fail('new.target is not supported');
      var callee = _newCallee();
      var args = <Expr>[];
      if (isP('(')) {
        p++;
        args = _args();
      }
      e = NewExpr(callee, args);
    } else {
      e = _primary();
    }
    while (true) {
      if (isP('.')) {
        p++;
        if (cur.t != T.name) fail();
        e = Member(e, cur.v, null, false);
        p++;
      } else if (isP('?.')) {
        p++;
        if (isP('(')) {
          p++;
          e = Call(e, _args(), true);
        } else if (isP('[')) {
          p++;
          final k = parseExpression();
          expectP(']');
          e = Member(e, null, k, true);
        } else {
          if (cur.t != T.name) fail();
          e = Member(e, cur.v, null, true);
          p++;
        }
      } else if (isP('[')) {
        p++;
        final k = parseExpression();
        expectP(']');
        e = Member(e, null, k, false);
      } else if (isP('(')) {
        p++;
        e = Call(e, _args(), false);
      } else if (cur.t == T.tmpl) {
        fail('tagged templates are not supported');
      } else {
        return e;
      }
    }
  }

  Expr _newCallee() {
    Expr e;
    if (isK('new')) {
      p++;
      final c = _newCallee();
      var args = <Expr>[];
      if (isP('(')) {
        p++;
        args = _args();
      }
      e = NewExpr(c, args);
    } else {
      e = _primary();
    }
    while (true) {
      if (isP('.')) {
        p++;
        e = Member(e, cur.v, null, false);
        p++;
      } else if (isP('[')) {
        p++;
        final k = parseExpression();
        expectP(']');
        e = Member(e, null, k, false);
      } else {
        return e;
      }
    }
  }

  Expr _primary() {
    final t = cur;
    switch (t.t) {
      case T.num:
        p++;
        return NumLit(t.n!);
      case T.str:
        p++;
        return StrLit(t.v);
      case T.tmpl:
        p++;
        final exprs = <Expr>[];
        for (final src in t.exprs!) {
          final sub = JsParser(src);
          final e = sub.parseExpression();
          if (sub.cur.t != T.eof) throw JsSyntaxError('bad template expression');
          exprs.add(e);
        }
        return TemplateLit(t.parts!, exprs);
      case T.regex:
        p++;
        return RegexLit(t.v, t.flags ?? '');
      case T.name:
        switch (t.v) {
          case 'function':
            p++;
            String? name;
            if (cur.t == T.name) {
              name = cur.v;
              p++;
            }
            return FuncExpr(_funcRest(name, true));
          case 'this':
            p++;
            return ThisExpr();
          case 'true':
            p++;
            return Ident('true');
          case 'false':
            p++;
            return Ident('false');
          case 'null':
            p++;
            return Ident('null');
          case 'async':
          case 'await':
          case 'yield':
          case 'class':
            throw JsSyntaxError('"${t.v}" is not supported by the built-in interpreter');
        }
        p++;
        return Ident(t.v);
      case T.punct:
        if (t.v == '(') {
          p++;
          final saveNoIn = _noIn;
          _noIn = false;
          final e = parseExpression();
          _noIn = saveNoIn;
          expectP(')');
          return e;
        }
        if (t.v == '[') return _arrayLit();
        if (t.v == '{') return _objectLit();
        break;
      case T.eof:
        break;
    }
    fail();
  }

  Expr _arrayLit() {
    p++;
    final els = <Expr?>[];
    while (!isP(']')) {
      if (isP(',')) {
        p++;
        els.add(null);
        continue;
      }
      if (eatP('...')) {
        els.add(Spread(parseAssign()));
      } else {
        els.add(parseAssign());
      }
      if (!eatP(',')) break;
    }
    expectP(']');
    return ArrayLit(els);
  }

  Expr _objectLit() {
    p++;
    final props = <PropDef>[];
    while (!isP('}')) {
      if (eatP('...')) {
        props.add(PropDef(null, parseAssign(), 'spread'));
      } else {
        String? key;
        Expr? ck;
        var kind = 'init';
        if ((isK('get') || isK('set')) && peek().t != T.punct || ((isK('get') || isK('set')) && peek().t == T.punct && peek().v == '[')) {
          kind = cur.v;
          p++;
        }
        if (isP('[')) {
          p++;
          ck = parseAssign();
          expectP(']');
        } else if (cur.t == T.name || cur.t == T.str) {
          key = cur.v;
          p++;
        } else if (cur.t == T.num) {
          key = _numKey(cur.n!);
          p++;
        } else {
          fail();
        }
        if (kind == 'get' || kind == 'set') {
          expectP('(');
          final params = _params();
          final body = parseBlock().body;
          props.add(PropDef(key, FuncExpr(FuncNode(key, params, body, null, false)), kind, ck));
        } else if (isP('(')) {
          p++;
          final params = _params();
          final body = parseBlock().body;
          props.add(PropDef(key, FuncExpr(FuncNode(key, params, body, null, false)), 'init', ck));
        } else if (eatP(':')) {
          props.add(PropDef(key, parseAssign(), 'init', ck));
        } else {
          // shorthand `{a}` or `{a = 1}` (only valid as pattern)
          if (key == null) fail();
          Expr v = Ident(key);
          if (isP('=')) {
            p++;
            v = Assign('=', Ident(key), parseAssign());
          }
          props.add(PropDef(key, v, 'init'));
        }
      }
      if (!eatP(',')) break;
    }
    expectP('}');
    return ObjectLit(props);
  }
}
