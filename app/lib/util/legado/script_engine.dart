// util/legado/script_engine.dart - a pure Dart JavaScript interpreter for rule scripts (the original ships one for HarmonyOS as
// `_ArkTsJsRunner`, ~290 functions). It implements [JsRuntime] as [DartJsRuntime]: used by unit tests (JavaScriptCore cannot run on the
// host) and as the fallback when `flutter_js` is unavailable. Supports the ES5 core plus the ES2015 pieces rule scripts use
// (let/const, arrows, template literals, destructuring, spread/rest, for-of, `?.`, `??`). The Java bridge objects (`java`, `cache`,
// `source`, `cookie`, `book`, `chapter`) are native host objects ([JsBindable]).
import 'dart:math' as math;

import 'js_bindable.dart';
import 'js_builtins.dart';
import 'js_parser.dart';
import 'java_compat.dart';
import 'js_runtime.dart';

class ScopeRef {
  Object? value;
  final bool isConst;
  ScopeRef(this.value, {this.isConst = false});
}

class Scope {
  final Map<String, ScopeRef> vars = {};
  final Scope? parent;
  final bool isFunction;
  Scope(this.parent, {this.isFunction = false});

  ScopeRef? find(String name) {
    for (Scope? s = this; s != null; s = s.parent) {
      final r = s.vars[name];
      if (r != null) return r;
    }
    return null;
  }

  Scope get functionScope {
    var s = this;
    while (!s.isFunction && s.parent != null) {
      s = s.parent!;
    }
    return s;
  }
}

class _Comp {
  final int k; // 1 break, 2 continue, 3 return
  final String? label;
  final Object? value;
  const _Comp(this.k, this.label, this.value);
}

const int _kBreak = 1, _kCont = 2, _kRet = 3;

/// Marker returned by an optional chain that hit null/undefined.
final Object _chainBreak = Object();

class ScriptInterpreter {
  final Scope global = Scope(null, isFunction: true);
  final JsObj globalObj = JsObj(null, 'global');
  Object? lastValue = undefinedValue;
  int _fnDepth = 0;
  int _callDepth = 0;
  int _steps = 0;

  static const int maxSteps = 4000000;
  static const int maxCallDepth = 180;

  ScriptInterpreter(Map<String, Object?> globals) {
    globals.forEach((k, v) {
      global.vars[k] = ScopeRef(v);
    });
    global.vars['this'] = ScopeRef(globalObj);
    global.vars['globalThis'] = ScopeRef(globalObj);
  }

  void define(String name, Object? value) {
    global.vars[name] = ScopeRef(value);
    globalObj.props[name] = value;
  }

  Object? run(List<Stmt> program) {
    _hoist(program, global);
    for (final s in program) {
      final c = _exec(s, global);
      if (c != null && c.k == _kRet) return c.value;
    }
    return lastValue;
  }

  // ---------------------------------------------------------------------------------------------------------------------------
  // hoisting
  // ---------------------------------------------------------------------------------------------------------------------------
  void _hoist(List<Stmt> body, Scope fnScope) {
    for (final s in body) {
      _hoistVars(s, fnScope);
    }
    for (final s in body) {
      if (s is FuncDecl) {
        fnScope.vars[s.fn.name!] = ScopeRef(_makeFunction(s.fn, fnScope));
      }
    }
  }

  void _declareVarName(Pat p, Scope fnScope) {
    if (p is IdentPat) {
      fnScope.vars.putIfAbsent(p.name, () => ScopeRef(undefinedValue));
    } else if (p is DefaultPat) {
      _declareVarName(p.target, fnScope);
    } else if (p is RestPat) {
      _declareVarName(p.target, fnScope);
    } else if (p is ArrayPat) {
      for (final e in p.elements) {
        if (e != null) _declareVarName(e, fnScope);
      }
    } else if (p is ObjectPat) {
      for (final pr in p.props) {
        _declareVarName(pr.target, fnScope);
      }
      if (p.rest != null) _declareVarName(p.rest!, fnScope);
    }
  }

  void _hoistVars(Stmt s, Scope fnScope) {
    if (s is VarDecl) {
      if (s.kind == 'var') {
        for (final d in s.decls) {
          _declareVarName(d.$1, fnScope);
        }
      }
    } else if (s is Block) {
      for (final x in s.body) {
        _hoistVars(x, fnScope);
      }
    } else if (s is If) {
      _hoistVars(s.a, fnScope);
      if (s.b != null) _hoistVars(s.b!, fnScope);
    } else if (s is For) {
      if (s.init is VarDecl) _hoistVars(s.init as VarDecl, fnScope);
      _hoistVars(s.body, fnScope);
    } else if (s is ForIn) {
      if (s.declKind == 'var') _declareVarName(s.target, fnScope);
      _hoistVars(s.body, fnScope);
    } else if (s is While) {
      _hoistVars(s.body, fnScope);
    } else if (s is DoWhile) {
      _hoistVars(s.body, fnScope);
    } else if (s is Try) {
      _hoistVars(s.block, fnScope);
      if (s.handler != null) _hoistVars(s.handler!, fnScope);
      if (s.finalizer != null) _hoistVars(s.finalizer!, fnScope);
    } else if (s is Switch) {
      for (final c in s.cases) {
        for (final x in c.body) {
          _hoistVars(x, fnScope);
        }
      }
    } else if (s is Labeled) {
      _hoistVars(s.body, fnScope);
    }
  }

  // ---------------------------------------------------------------------------------------------------------------------------
  // functions
  // ---------------------------------------------------------------------------------------------------------------------------
  JsFn _makeFunction(FuncNode fn, Scope closure, {String? nameHint}) {
    late JsFn f;
    var scope = closure;
    if (fn.name != null && !fn.isArrow) {
      // named function expressions can refer to themselves
      scope = Scope(closure);
    }
    f = JsFn(fn.name ?? nameHint ?? '', (thisV, args) => _callUser(fn, scope, thisV, args), arity: fn.params.length);
    if (scope != closure) scope.vars[fn.name!] = ScopeRef(f);
    return f;
  }

  Object? _callUser(FuncNode fn, Scope closure, Object? thisV, List<Object?> args) {
    if (_callDepth >= maxCallDepth) throw rangeError('Maximum call stack size exceeded');
    final s = Scope(closure, isFunction: true);
    if (!fn.isArrow) {
      s.vars['this'] = ScopeRef(thisV);
      s.vars['arguments'] = ScopeRef(List<Object?>.from(args));
    }
    _callDepth++;
    _fnDepth++;
    try {
      for (var i = 0; i < fn.params.length; i++) {
        final p = fn.params[i];
        if (p is RestPat) {
          _bind(p.target, i < args.length ? List<Object?>.from(args.sublist(i)) : <Object?>[], s, 'let');
        } else {
          _bind(p, i < args.length ? args[i] : undefinedValue, s, 'let');
        }
      }
      if (fn.exprBody != null) return _eval(fn.exprBody!, s);
      _hoist(fn.body, s);
      for (final st in fn.body) {
        final c = _exec(st, s);
        if (c != null && c.k == _kRet) return c.value;
      }
      return undefinedValue;
    } finally {
      _callDepth--;
      _fnDepth--;
    }
  }

  // ---------------------------------------------------------------------------------------------------------------------------
  // statements
  // ---------------------------------------------------------------------------------------------------------------------------
  void _tick() {
    if (++_steps > maxSteps) throw JsException('script execution limit exceeded (possible infinite loop)');
  }

  _Comp? _execList(List<Stmt> list, Scope s) {
    for (final st in list) {
      final c = _exec(st, s);
      if (c != null) return c;
    }
    return null;
  }

  _Comp? _exec(Stmt st, Scope s, [Set<String>? labels]) {
    _tick();
    if (st is ExprStmt) {
      final v = _eval(st.e, s);
      if (_fnDepth == 0) lastValue = v;
      return null;
    }
    if (st is VarDecl) {
      for (final d in st.decls) {
        if (d.$2 == null) {
          if (st.kind == 'var') {
            if (d.$1 is IdentPat && s.find((d.$1 as IdentPat).name) != null) continue;
            _bind(d.$1, undefinedValue, s, st.kind);
          } else {
            _bind(d.$1, undefinedValue, s, st.kind);
          }
        } else {
          var v = _eval(d.$2!, s);
          if (v is JsFn && v.name.isEmpty && d.$1 is IdentPat) v.name = (d.$1 as IdentPat).name;
          _bind(d.$1, v, s, st.kind);
        }
      }
      return null;
    }
    if (st is Return) return _Comp(_kRet, null, st.arg == null ? undefinedValue : _eval(st.arg!, s));
    if (st is If) {
      if (toBool(_eval(st.test, s))) return _exec(st.a, s);
      if (st.b != null) return _exec(st.b!, s);
      return null;
    }
    if (st is Block) {
      final bs = Scope(s);
      for (final x in st.body) {
        if (x is FuncDecl) bs.vars[x.fn.name!] = ScopeRef(_makeFunction(x.fn, bs));
      }
      return _execList(st.body, bs);
    }
    if (st is For) return _execFor(st, s, labels);
    if (st is ForIn) return _execForIn(st, s, labels);
    if (st is While) {
      while (toBool(_eval(st.test, s))) {
        _tick();
        final c = _exec(st.body, s);
        final r = _loopCtl(c, labels);
        if (r == 1) break;
        if (r == 3) return c;
      }
      return null;
    }
    if (st is DoWhile) {
      do {
        _tick();
        final c = _exec(st.body, s);
        final r = _loopCtl(c, labels);
        if (r == 1) break;
        if (r == 3) return c;
      } while (toBool(_eval(st.test, s)));
      return null;
    }
    if (st is Break) return _Comp(_kBreak, st.label, null);
    if (st is Continue) return _Comp(_kCont, st.label, null);
    if (st is Throw) throw JsThrow(_eval(st.arg, s));
    if (st is Try) return _execTry(st, s);
    if (st is Switch) return _execSwitch(st, s);
    if (st is FuncDecl) {
      s.vars[st.fn.name!] ??= ScopeRef(_makeFunction(st.fn, s));
      return null;
    }
    if (st is Empty) return null;
    if (st is Labeled) {
      final ls = <String>{st.label};
      Stmt body = st.body;
      while (body is Labeled) {
        ls.add(body.label);
        body = body.body;
      }
      final c = _exec(body, s, ls);
      if (c != null && c.k == _kBreak && c.label != null && ls.contains(c.label)) return null;
      return c;
    }
    throw JsException('unsupported statement ${st.runtimeType}');
  }

  /// 0 = continue normally, 1 = break the loop, 3 = propagate the completion.
  int _loopCtl(_Comp? c, Set<String>? labels) {
    if (c == null) return 0;
    if (c.k == _kBreak) {
      if (c.label == null) return 1;
      return labels != null && labels.contains(c.label) ? 1 : 3;
    }
    if (c.k == _kCont) {
      if (c.label == null) return 0;
      return labels != null && labels.contains(c.label) ? 0 : 3;
    }
    return 3;
  }

  _Comp? _execFor(For st, Scope s, Set<String>? labels) {
    var cur = Scope(s);
    final init = st.init;
    List<String> letNames = const [];
    if (init is VarDecl) {
      _exec(init, cur);
      if (init.kind != 'var') {
        letNames = [for (final d in init.decls) ..._patNames(d.$1)];
      }
    } else if (init is Expr) {
      _eval(init, cur);
    }
    while (true) {
      _tick();
      if (st.test != null && !toBool(_eval(st.test!, cur))) break;
      final c = _exec(st.body, cur);
      final r = _loopCtl(c, labels);
      if (r == 1) break;
      if (r == 3) return c;
      if (letNames.isNotEmpty) {
        final next = Scope(s);
        for (final n in letNames) {
          next.vars[n] = ScopeRef(cur.vars[n]?.value ?? undefinedValue);
        }
        cur = next;
      }
      if (st.update != null) _eval(st.update!, cur);
    }
    return null;
  }

  List<String> _patNames(Pat p) {
    if (p is IdentPat) return [p.name];
    if (p is DefaultPat) return _patNames(p.target);
    if (p is RestPat) return _patNames(p.target);
    if (p is ArrayPat) return [for (final e in p.elements) if (e != null) ..._patNames(e)];
    if (p is ObjectPat) return [for (final x in p.props) ..._patNames(x.target), if (p.rest != null) ..._patNames(p.rest!)];
    return const [];
  }

  List<Object?> _iterate(Object? v, {required bool of}) {
    if (!of) {
      // for-in: keys
      if (v is JsObj) {
        final keys = <Object?>[];
        for (JsObj? o = v; o != null; o = o.proto) {
          for (final k in o.props.keys) {
            if (!keys.contains(k) && o.props[k] is! JsFn) keys.add(k);
          }
        }
        return keys;
      }
      if (v is List) return [for (var i = 0; i < v.length; i++) '$i'];
      if (v is String) return [for (var i = 0; i < v.length; i++) '$i'];
      return const [];
    }
    if (v is List<Object?>) return List<Object?>.from(v);
    if (v is String) return v.runes.map<Object?>((r) => String.fromCharCode(r)).toList();
    if (v is JsObj) {
      if (v.cls == 'Map') return callMethod(v, 'entries', const []) as List<Object?>;
      if (v.cls == 'Set') return callMethod(v, 'values', const []) as List<Object?>;
      final len = v.props['length'];
      if (len is num) return [for (var i = 0; i < len; i++) v.props['$i'] ?? undefinedValue];
    }
    throw typeError('${describeValue(v)} is not iterable');
  }

  _Comp? _execForIn(ForIn st, Scope s, Set<String>? labels) {
    final right = _eval(st.right, s);
    for (final item in _iterate(right, of: st.isOf)) {
      _tick();
      final is_ = Scope(s);
      _bind(st.target, item, is_, st.declKind);
      final c = _exec(st.body, is_);
      final r = _loopCtl(c, labels);
      if (r == 1) break;
      if (r == 3) return c;
    }
    return null;
  }

  _Comp? _execSwitch(Switch st, Scope s) {
    final d = _eval(st.disc, s);
    final ss = Scope(s);
    var start = -1;
    for (var i = 0; i < st.cases.length; i++) {
      final t = st.cases[i].test;
      if (t != null && strictEq(d, _eval(t, ss))) {
        start = i;
        break;
      }
    }
    if (start < 0) start = st.cases.indexWhere((c) => c.test == null);
    if (start < 0) return null;
    for (var i = start; i < st.cases.length; i++) {
      final c = _execList(st.cases[i].body, ss);
      if (c != null) {
        if (c.k == _kBreak && c.label == null) return null;
        return c;
      }
    }
    return null;
  }

  Object? _errorValue(Object e) {
    if (e is JsThrow) return e.value;
    if (e is JsHostError) return makeError('Error', e.message);
    if (e is JsNoSuchMethod) return makeError('TypeError', e.toString());
    if (e is JsException) return makeError('Error', e.message);
    if (e is StackOverflowError) return makeError('RangeError', 'Maximum call stack size exceeded');
    return makeError('Error', e.toString());
  }

  _Comp? _execTry(Try st, Scope s) {
    _Comp? result;
    Object? pending;
    StackTrace? pendingSt;
    try {
      result = _exec(st.block, s);
    } on JsPendingException {
      rethrow;
    } on JsException {
      rethrow;
    } catch (e, stack) {
      if (st.handler != null) {
        final hs = Scope(s);
        if (st.param != null) _bind(st.param!, _errorValue(e), hs, 'let');
        try {
          result = _exec(st.handler!, hs);
        } on JsPendingException {
          rethrow;
        } catch (e2, st2) {
          pending = e2;
          pendingSt = st2;
        }
      } else {
        pending = e;
        pendingSt = stack;
      }
    }
    if (st.finalizer != null) {
      final fc = _exec(st.finalizer!, s);
      if (fc != null) return fc;
    }
    if (pending != null) Error.throwWithStackTrace(pending, pendingSt ?? StackTrace.current);
    return result;
  }

  // ---------------------------------------------------------------------------------------------------------------------------
  // bindings / assignment
  // ---------------------------------------------------------------------------------------------------------------------------
  void _declare(String kind, String name, Object? v, Scope s) {
    if (kind == 'var') {
      final ref = s.find(name);
      if (ref != null) {
        ref.value = v;
      } else {
        s.functionScope.vars[name] = ScopeRef(v);
      }
    } else {
      s.vars[name] = ScopeRef(v, isConst: kind == 'const');
    }
  }

  void _assignName(String name, Object? v, Scope s) {
    final ref = s.find(name);
    if (ref == null) {
      global.vars[name] = ScopeRef(v);
      globalObj.props[name] = v;
      return;
    }
    if (ref.isConst) throw typeError('Assignment to constant variable.');
    ref.value = v;
  }

  /// [kind] null = plain assignment to existing targets.
  void _bind(Pat p, Object? v, Scope s, String? kind) {
    if (p is IdentPat) {
      if (kind == null) {
        _assignName(p.name, v, s);
      } else {
        _declare(kind, p.name, v, s);
      }
    } else if (p is DefaultPat) {
      _bind(p.target, v is JsUndefined ? _eval(p.def, s) : v, s, kind);
    } else if (p is ArrayPat) {
      if (v == null || v is JsUndefined) throw typeError('${toStr(v)} is not iterable');
      final items = _iterate(v, of: true);
      for (var i = 0; i < p.elements.length; i++) {
        final e = p.elements[i];
        if (e == null) continue;
        if (e is RestPat) {
          _bind(e.target, i < items.length ? List<Object?>.from(items.sublist(i)) : <Object?>[], s, kind);
        } else {
          _bind(e, i < items.length ? items[i] : undefinedValue, s, kind);
        }
      }
    } else if (p is ObjectPat) {
      if (v == null || v is JsUndefined) throw typeError('Cannot destructure ${toStr(v)}');
      final used = <String>{};
      for (final pr in p.props) {
        final key = pr.key ?? toStr(_eval(pr.computedKey!, s));
        used.add(key);
        _bind(pr.target, getProp(v, key), s, kind);
      }
      if (p.rest != null) {
        final rest = JsObj(null, 'Object');
        if (v is JsObj) {
          v.props.forEach((k, val) {
            if (!used.contains(k)) rest.props[k] = val;
          });
        }
        _bind(p.rest!, rest, s, kind);
      }
    } else if (p is ExprPat) {
      _assignTo(p.expr, v, s);
    } else if (p is RestPat) {
      _bind(p.target, v, s, kind);
    }
  }

  void _assignTo(Node target, Object? v, Scope s) {
    if (target is Ident) {
      _assignName(target.name, v, s);
    } else if (target is Member) {
      final o = _eval(target.obj, s);
      setProp(o, target.name ?? _propKey(_eval(target.computed!, s)), v);
    } else if (target is Pat) {
      _bind(target, v, s, null);
    } else {
      throw JsException('invalid assignment target');
    }
  }

  String _propKey(Object? k) => k is String ? k : (k is num ? numToStr(k) : toStr(k));

  // ---------------------------------------------------------------------------------------------------------------------------
  // expressions
  // ---------------------------------------------------------------------------------------------------------------------------
  Object? _lookupName(String name, Scope s) {
    switch (name) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
    }
    final r = s.find(name);
    if (r != null) return r.value;
    final gp = globalObj.props[name];
    if (gp != null || globalObj.props.containsKey(name)) return gp;
    throw referenceError('$name is not defined');
  }

  Object? _eval(Expr e, Scope s) {
    if (e is Ident) return _lookupName(e.name, s);
    if (e is NumLit) return e.v;
    if (e is StrLit) return e.v;
    if (e is Member || e is Call) {
      final r = _evalChain(e, s);
      return identical(r, _chainBreak) ? undefinedValue : r;
    }
    if (e is Binary) return _binary(e.op, _eval(e.l, s), _eval(e.r, s));
    if (e is Assign) return _evalAssign(e, s);
    if (e is Logical) {
      final l = _eval(e.l, s);
      switch (e.op) {
        case '&&':
          return toBool(l) ? _eval(e.r, s) : l;
        case '||':
          return toBool(l) ? l : _eval(e.r, s);
        default:
          return (l == null || l is JsUndefined) ? _eval(e.r, s) : l;
      }
    }
    if (e is Cond) return toBool(_eval(e.test, s)) ? _eval(e.a, s) : _eval(e.b, s);
    if (e is Unary) return _unary(e, s);
    if (e is Update) return _update(e, s);
    if (e is ThisExpr) {
      final r = s.find('this');
      return r == null ? undefinedValue : r.value;
    }
    if (e is TemplateLit) {
      final sb = StringBuffer();
      for (var i = 0; i < e.quasis.length; i++) {
        sb.write(e.quasis[i]);
        if (i < e.exprs.length) sb.write(toStr(_eval(e.exprs[i], s)));
      }
      return sb.toString();
    }
    if (e is ArrayLit) {
      final out = <Object?>[];
      for (final x in e.elements) {
        if (x == null) {
          out.add(undefinedValue);
        } else if (x is Spread) {
          out.addAll(_iterate(_eval(x.arg, s), of: true));
        } else {
          out.add(_eval(x, s));
        }
      }
      return out;
    }
    if (e is ObjectLit) return _objectLit(e, s);
    if (e is FuncExpr) return _makeFunction(e.fn, s);
    if (e is NewExpr) return _new(e, s);
    if (e is RegexLit) return makeRegex(e.source, e.flags);
    if (e is Seq) {
      Object? v = undefinedValue;
      for (final x in e.list) {
        v = _eval(x, s);
      }
      return v;
    }
    if (e is Spread) throw JsException('unexpected spread');
    throw JsException('unsupported expression ${e.runtimeType}');
  }

  Object? _objectLit(ObjectLit e, Scope s) {
    final o = JsObj(null, 'Object');
    for (final pd in e.props) {
      if (pd.kind == 'spread') {
        final src = _eval(pd.value!, s);
        if (src is JsObj) {
          o.props.addAll(src.props);
        } else if (src is List) {
          for (var i = 0; i < src.length; i++) {
            o.props['$i'] = src[i];
          }
        } else if (src is String) {
          for (var i = 0; i < src.length; i++) {
            o.props['$i'] = src[i];
          }
        }
        continue;
      }
      final key = pd.key ?? _propKey(_eval(pd.computedKey!, s));
      if (pd.kind == 'get' || pd.kind == 'set') {
        final f = _eval(pd.value!, s) as JsFn;
        if (pd.kind == 'get') {
          (o.getters ??= {})[key] = f;
        } else {
          (o.setters ??= {})[key] = f;
        }
      } else {
        final v = _eval(pd.value!, s);
        if (v is JsFn && v.name.isEmpty) v.name = key;
        o.props[key] = v;
      }
    }
    return o;
  }

  Object? _new(NewExpr e, Scope s) {
    final c = _eval(e.callee, s);
    final args = _evalArgs(e.args, s);
    if (c is JsFn) {
      if (c.construct != null) return c.construct!(args);
      final protoV = getProp(c, 'prototype');
      final obj = JsObj(protoV is JsObj ? protoV : null, 'Object');
      final r = c.invoke(obj, args);
      return (r is JsObj || r is List) ? r : obj;
    }
    throw typeError('${describeValue(c)} is not a constructor');
  }

  List<Object?> _evalArgs(List<Expr> args, Scope s) {
    final out = <Object?>[];
    for (final a in args) {
      if (a is Spread) {
        out.addAll(_iterate(_eval(a.arg, s), of: true));
      } else {
        out.add(_eval(a, s));
      }
    }
    return out;
  }

  /// Evaluates member/call chains with optional-chaining short-circuit.
  Object? _evalChain(Expr e, Scope s) {
    if (e is Member) {
      final o = e.obj is Member || e.obj is Call ? _evalChain(e.obj, s) : _eval(e.obj, s);
      if (identical(o, _chainBreak)) return o;
      if (e.optional && (o == null || o is JsUndefined)) return _chainBreak;
      final key = e.name ?? _propKey(_eval(e.computed!, s));
      return getProp(o, key);
    }
    if (e is Call) {
      final callee = e.callee;
      if (callee is Member) {
        final o = callee.obj is Member || callee.obj is Call ? _evalChain(callee.obj, s) : _eval(callee.obj, s);
        if (identical(o, _chainBreak)) return o;
        if (callee.optional && (o == null || o is JsUndefined)) return _chainBreak;
        final key = callee.name ?? _propKey(_eval(callee.computed!, s));
        if (e.optional) {
          final f = getProp(o, key);
          if (f == null || f is JsUndefined) return _chainBreak;
        }
        final args = _evalArgs(e.args, s);
        _tick();
        return callMethod(o, key, args);
      }
      final f = callee is Call ? _evalChain(callee, s) : _eval(callee, s);
      if (identical(f, _chainBreak)) return f;
      if (e.optional && (f == null || f is JsUndefined)) return _chainBreak;
      final args = _evalArgs(e.args, s);
      _tick();
      if (f is JsFn) return f.invoke(undefinedValue, args);
      throw typeError('${callee is Ident ? callee.name : describeValue(f)} is not a function');
    }
    return _eval(e, s);
  }

  Object? _evalAssign(Assign e, Scope s) {
    final t = e.target;
    if (e.op == '=') {
      final v = _eval(e.value, s);
      if (t is Ident && v is JsFn && v.name.isEmpty) v.name = t.name;
      _assignTo(t, v, s);
      return v;
    }
    // compound
    Object? cur;
    Object? obj;
    String? key;
    if (t is Ident) {
      cur = _lookupName(t.name, s);
    } else if (t is Member) {
      obj = _eval(t.obj, s);
      key = t.name ?? _propKey(_eval(t.computed!, s));
      cur = getProp(obj, key);
    } else {
      throw JsException('invalid compound assignment');
    }
    Object? nv;
    switch (e.op) {
      case '&&=':
        if (!toBool(cur)) return cur;
        nv = _eval(e.value, s);
        break;
      case '||=':
        if (toBool(cur)) return cur;
        nv = _eval(e.value, s);
        break;
      case '??=':
        if (!(cur == null || cur is JsUndefined)) return cur;
        nv = _eval(e.value, s);
        break;
      default:
        nv = _binary(e.op.substring(0, e.op.length - 1), cur, _eval(e.value, s));
    }
    if (t is Ident) {
      _assignName(t.name, nv, s);
    } else {
      setProp(obj, key!, nv);
    }
    return nv;
  }

  Object? _update(Update e, Scope s) {
    final t = e.target;
    Object? obj;
    String? key;
    Object? cur;
    if (t is Ident) {
      cur = _lookupName(t.name, s);
    } else if (t is Member) {
      obj = _eval(t.obj, s);
      key = t.name ?? _propKey(_eval(t.computed!, s));
      cur = getProp(obj, key);
    } else {
      throw JsException('invalid update target');
    }
    final n = toNum(cur);
    final nv = normNum(e.op == '++' ? n + 1 : n - 1);
    if (t is Ident) {
      _assignName(t.name, nv, s);
    } else {
      setProp(obj, key!, nv);
    }
    return e.prefix ? nv : n;
  }

  Object? _unary(Unary e, Scope s) {
    switch (e.op) {
      case 'typeof':
        if (e.arg is Ident) {
          final n = (e.arg as Ident).name;
          if (n != 'true' && n != 'false' && n != 'null' && s.find(n) == null && !globalObj.props.containsKey(n)) return 'undefined';
        }
        final v = _eval(e.arg, s);
        if (v is HostObj) return 'object';
        return typeOf(v);
      case '!':
        return !toBool(_eval(e.arg, s));
      case '-':
        final v = toNum(_eval(e.arg, s));
        return v is int ? (v == 0 ? 0 : -v) : normNum(-v);
      case '+':
        return toNum(_eval(e.arg, s));
      case '~':
        return ~toInt32(_eval(e.arg, s));
      case 'void':
        _eval(e.arg, s);
        return undefinedValue;
      case 'delete':
        final a = e.arg;
        if (a is Member) {
          final o = _eval(a.obj, s);
          final key = a.name ?? _propKey(_eval(a.computed!, s));
          if (o is JsObj) {
            o.props.remove(key);
          } else if (o is List) {
            final i = int.tryParse(key);
            if (i != null && i >= 0 && i < o.length) o[i] = undefinedValue;
          }
          return true;
        }
        return true;
    }
    throw JsException('unsupported unary ${e.op}');
  }

  Object? _binary(String op, Object? a, Object? b) {
    switch (op) {
      case '+':
        if (a is num && b is num) return normNum(a + b);
        final pa = _prim(a), pb = _prim(b);
        if (pa is String || pb is String) return toStr(pa) + toStr(pb);
        return normNum(toNum(pa) + toNum(pb));
      case '-':
        return normNum(toNum(a) - toNum(b));
      case '*':
        return normNum(toNum(a) * toNum(b));
      case '/':
        final d = toNum(b);
        if (d == 0) {
          final n = toNum(a);
          if (n.isNaN || n == 0) return double.nan;
          return (n > 0) == (d is double && d.isNegative) ? double.negativeInfinity : double.infinity;
        }
        return normNum(toNum(a) / d);
      case '%':
        final d = toNum(b);
        if (d == 0) return double.nan;
        final n = toNum(a);
        if (n.isInfinite) return double.nan;
        return normNum(n.remainder(d));
      case '**':
        return normNum(_pow(toNum(a), toNum(b)));
      case '==':
        return looseEq(a, b);
      case '!=':
        return !looseEq(a, b);
      case '===':
        return strictEq(a, b);
      case '!==':
        return !strictEq(a, b);
      case '<':
      case '>':
      case '<=':
      case '>=':
        return _compare(op, a, b);
      case '&':
        return toInt32(a) & toInt32(b);
      case '|':
        return toInt32(a) | toInt32(b);
      case '^':
        return toInt32(a) ^ toInt32(b);
      case '<<':
        return (toInt32(a) << (toUint32(b) & 31)).toSigned(32);
      case '>>':
        return toInt32(a) >> (toUint32(b) & 31);
      case '>>>':
        return toUint32(a) >> (toUint32(b) & 31);
      case 'instanceof':
        return _instanceOf(a, b);
      case 'in':
        return _in(a, b);
    }
    throw JsException('unsupported operator $op');
  }

  num _pow(num a, num b) {
    if (b == 0) return 1;
    return math.pow(a, b);
  }

  Object? _prim(Object? v) {
    if (v is JsObj || v is List || v is HostObj) return toStr(v);
    return v;
  }

  bool _compare(String op, Object? a, Object? b) {
    final pa = _prim(a), pb = _prim(b);
    if (pa is String && pb is String) {
      final c = pa.compareTo(pb);
      switch (op) {
        case '<':
          return c < 0;
        case '>':
          return c > 0;
        case '<=':
          return c <= 0;
        default:
          return c >= 0;
      }
    }
    final x = toNum(pa), y = toNum(pb);
    if (x.isNaN || y.isNaN) return false;
    switch (op) {
      case '<':
        return x < y;
      case '>':
        return x > y;
      case '<=':
        return x <= y;
      default:
        return x >= y;
    }
  }

  bool _instanceOf(Object? a, Object? b) {
    if (b is! JsFn) throw typeError("Right-hand side of 'instanceof' is not callable");
    switch (b.kind) {
      case 'Array':
        return a is List;
      case 'Object':
        return a is JsObj || a is List || a is HostObj;
      case 'Error':
        return a is JsObj && a.cls == 'Error' && (b.name == 'Error' || a.props['name'] == b.name);
      case 'RegExp':
        return a is JsRegex;
      case 'Date':
        return a is JsDate;
      case 'Map':
        return a is JsObj && a.cls == 'Map';
      case 'Set':
        return a is JsObj && a.cls == 'Set';
      case 'String':
      case 'Number':
      case 'Boolean':
        return false;
    }
    if (a is! JsObj) return false;
    final proto = getProp(b, 'prototype');
    for (JsObj? p = a.proto; p != null; p = p.proto) {
      if (identical(p, proto)) return true;
    }
    return false;
  }

  bool _in(Object? key, Object? obj) {
    final k = _propKey(key);
    if (obj is JsObj) {
      for (JsObj? p = obj; p != null; p = p.proto) {
        if (p.props.containsKey(k) || (p.getters?.containsKey(k) ?? false)) return true;
      }
      return false;
    }
    if (obj is List) {
      final i = int.tryParse(k);
      return k == 'length' || (i != null && i >= 0 && i < obj.length);
    }
    if (obj is HostObj) return !identical(obj.b.jsGet(k), JsBindable.noMember) || obj.b.jsMethods.contains(k);
    throw typeError("Cannot use 'in' operator to search for '$k' in ${toStr(obj)}");
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// runtime
// ---------------------------------------------------------------------------------------------------------------------------

/// Pure Dart [JsRuntime]. Instantiable in host tests.
class DartJsRuntime extends JsRuntime {
  final Map<String, List<Stmt>> _astCache = {};
  late final Map<String, Object?> _baseGlobals = createGlobals((line) => JsEvalContext.current?.logs.add(line));

  List<Stmt> _parse(String code) {
    final hit = _astCache[code];
    if (hit != null) return hit;
    final ast = JsParser(code).parseProgram();
    if (_astCache.length > 200) _astCache.clear();
    _astCache[code] = ast;
    return ast;
  }

  @override
  Object? evaluateSync(String script, JsBindings bindings) {
    List<Stmt> ast;
    try {
      ast = _parse(script);
    } on JsSyntaxError catch (e) {
      throw JsException(e.toString());
    }
    final it = ScriptInterpreter(Map<String, Object?>.from(_baseGlobals));
    bindings.values.forEach((k, v) => it.define(k, fromHost(v)));
    bindings.objects.forEach((k, v) => it.define(k, HostObj(v)));
    try {
      final r = it.run(ast);
      return toHost(r);
    } on JsPendingException {
      rethrow;
    } on JsThrow catch (e) {
      throw JsException(describeError(e.value));
    } on JsHostError catch (e) {
      throw JsException(e.message);
    } on JsNoSuchMethod catch (e) {
      throw JsException(e.toString());
    } on StackOverflowError {
      throw JsException('RangeError: Maximum call stack size exceeded');
    }
  }
}
