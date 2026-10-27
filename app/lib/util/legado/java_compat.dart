// util/legado/java_compat.dart - value model and builtin methods of the pure Dart JavaScript interpreter (script_engine.dart), including
// the Java-flavoured string/list methods that Rhino exposes to book-source scripts (`equals`, `contains`, `getBytes`, `isEmpty`, `size()`,
// `length()` ...; rule_engine.txt section 2). Values: undefined = [undefinedValue], null = Dart null, numbers = int/double, strings,
// bools, arrays = `List<Object?>`, objects = [JsObj], functions = [JsFn], host objects = [HostObj] (a [JsBindable]).
import 'dart:convert';
import 'dart:typed_data';

import '../http.dart';
import 'js_bindable.dart';

class JsUndefined {
  const JsUndefined();
  @override
  String toString() => 'undefined';
}

const JsUndefined undefinedValue = JsUndefined();

/// A thrown JavaScript value.
class JsThrow implements Exception {
  final Object? value;
  JsThrow(this.value);
  @override
  String toString() => describeError(value);
}

typedef NativeFn = Object? Function(Object? thisV, List<Object?> args);

class JsObj {
  final Map<String, Object?> props = {};
  JsObj? proto;
  String cls;
  Map<String, JsFn>? getters;
  Map<String, JsFn>? setters;
  JsObj([this.proto, this.cls = 'Object']);
}

class JsFn extends JsObj {
  String name;
  int arity;
  final NativeFn invoke;

  /// Constructor behaviour for builtins (`new Date()`); null = ordinary function used with `new`.
  Object? Function(List<Object?> args)? construct;

  /// Builtin constructor tag used by `instanceof` (Array, Error, ...).
  String kind;

  JsFn(this.name, this.invoke, {this.arity = 0, this.construct, this.kind = ''}) : super(null, 'Function');
}

class JsRegex extends JsObj {
  final RegExp re;
  final String source;
  final String flags;
  int lastIndex = 0;
  JsRegex(this.re, this.source, this.flags) : super(null, 'RegExp');
  bool get global => flags.contains('g');
  bool get sticky => flags.contains('y');
}

class JsDate extends JsObj {
  int ms;
  JsDate(this.ms) : super(null, 'Date');
}

class HostObj {
  final JsBindable b;
  HostObj(this.b);
  @override
  bool operator ==(Object other) => other is HostObj && identical(other.b, b);
  @override
  int get hashCode => identityHashCode(b);
}

// ---------------------------------------------------------------------------------------------------------------------------
// errors
// ---------------------------------------------------------------------------------------------------------------------------
final JsObj errorProto = JsObj(null, 'Error');

JsObj makeError(String name, String message) {
  final e = JsObj(errorProto, 'Error');
  e.props['name'] = name;
  e.props['message'] = message;
  e.props['stack'] = '$name: $message';
  return e;
}

JsThrow typeError(String msg) => JsThrow(makeError('TypeError', msg));
JsThrow rangeError(String msg) => JsThrow(makeError('RangeError', msg));
JsThrow referenceError(String msg) => JsThrow(makeError('ReferenceError', msg));

String describeError(Object? v) {
  if (v is JsObj && v.cls == 'Error') {
    final n = v.props['name'] ?? 'Error';
    final m = v.props['message'] ?? '';
    return '$n: $m';
  }
  return toStr(v);
}

// ---------------------------------------------------------------------------------------------------------------------------
// conversions
// ---------------------------------------------------------------------------------------------------------------------------
num normNum(num d) {
  if (d is int) return d;
  if (d.isNaN || d.isInfinite) return d;
  if (d == d.truncateToDouble() && d.abs() < 9007199254740992) {
    if (d == 0) return 0;
    return d.toInt();
  }
  return d;
}

String numToStr(num n) {
  if (n is int) return n.toString();
  final d = n.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  if (d == d.truncateToDouble() && d.abs() < 1e21) return d.toInt().toString();
  var s = d.toString();
  // Dart: 1.0e-7 / 1e+21 forms are close to JS; normalise "e+" and trailing ".0e"
  s = s.replaceAll('.0e', 'e');
  return s;
}

final Expando<Map<String, Object?>> _listProps = Expando('listProps');

void setListProp(List<Object?> l, String key, Object? v) {
  (_listProps[l] ??= {})[key] = v;
}

String toStr(Object? v) {
  if (v == null) return 'null';
  if (v is String) return v;
  if (v is JsUndefined) return 'undefined';
  if (v is num) return numToStr(v);
  if (v is bool) return v ? 'true' : 'false';
  if (v is List) return v.map((e) => (e == null || e is JsUndefined) ? '' : toStr(e)).join(',');
  if (v is JsFn) return 'function ${v.name}() { [native code] }';
  if (v is JsRegex) return '/${v.source}/${v.flags}';
  if (v is JsDate) return dateToString(v.ms);
  if (v is JsObj) {
    final ts = _lookup(v, 'toString');
    if (ts is JsFn && ts.kind != 'objectToString') {
      final r = ts.invoke(v, const []);
      if (r is! JsObj) return toStr(r);
    }
    if (v.cls == 'Error') return describeError(v);
    return '[object Object]';
  }
  if (v is HostObj) {
    if (v.b.jsMethods.contains('toString')) {
      try {
        return toStr(fromHost(v.b.jsCall('toString', const [])));
      } on JsNoSuchMethod {
        // fall through
      }
    }
    return '[object Object]';
  }
  return v.toString();
}

num toNum(Object? v) {
  if (v is num) return v;
  if (v == null) return 0;
  if (v is JsUndefined) return double.nan;
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    if (t.startsWith('0x') || t.startsWith('0X')) return int.tryParse(t.substring(2), radix: 16) ?? double.nan;
    if (t == 'Infinity' || t == '+Infinity') return double.infinity;
    if (t == '-Infinity') return double.negativeInfinity;
    if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(t)) return double.nan;
    return normNum(double.parse(t));
  }
  if (v is List) {
    if (v.isEmpty) return 0;
    if (v.length == 1) return toNum(v[0]);
    return double.nan;
  }
  if (v is JsDate) return v.ms;
  if (v is JsObj) {
    final vo = _lookup(v, 'valueOf');
    if (vo is JsFn && vo.kind != 'objectValueOf') {
      final r = vo.invoke(v, const []);
      if (r is! JsObj) return toNum(r);
    }
    return double.nan;
  }
  return double.nan;
}

int toInt32(Object? v) {
  final n = toNum(v);
  if (n is int) return n.toSigned(32);
  if (n.isNaN || n.isInfinite) return 0;
  return n.truncate().toSigned(32);
}

int toUint32(Object? v) {
  final n = toNum(v);
  if (n is int) return n.toUnsigned(32);
  if (n.isNaN || n.isInfinite) return 0;
  return n.truncate().toUnsigned(32);
}

bool toBool(Object? v) {
  if (v == null || v is JsUndefined) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

String typeOf(Object? v) {
  if (v is JsUndefined) return 'undefined';
  if (v == null) return 'object';
  if (v is num) return 'number';
  if (v is String) return 'string';
  if (v is bool) return 'boolean';
  if (v is JsFn) return 'function';
  return 'object';
}

bool strictEq(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  if (a is HostObj && b is HostObj) return a == b;
  return identical(a, b);
}

bool looseEq(Object? a, Object? b) {
  if ((a == null || a is JsUndefined) && (b == null || b is JsUndefined)) return true;
  if (a == null || a is JsUndefined || b == null || b is JsUndefined) return false;
  if (a is num && b is num) return a == b;
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  if ((a is num && b is String) || (a is String && b is num)) return toNum(a) == toNum(b);
  if (a is bool) return looseEq(toNum(a), b);
  if (b is bool) return looseEq(a, toNum(b));
  if ((a is String || a is num) && (b is JsObj || b is List)) return looseEq(a, toStr(b));
  if ((b is String || b is num) && (a is JsObj || a is List)) return looseEq(toStr(a), b);
  if (a is HostObj && b is HostObj) return a == b;
  return identical(a, b);
}

// ---------------------------------------------------------------------------------------------------------------------------
// host <-> JS value conversion
// ---------------------------------------------------------------------------------------------------------------------------
Object? fromHost(Object? v) {
  if (v == null || v is String || v is bool) return v;
  if (v is JsUndefined) return v;
  if (v is num) return normNum(v);
  if (v is JsBindable) return HostObj(v);
  if (v is Uint8List) return v.toList();
  if (v is Map) {
    if (v['__nr'] == 'StrResponse') return _makeResponse(v);
    final o = JsObj(null, 'Object');
    v.forEach((k, val) => o.props['$k'] = fromHost(val));
    return o;
  }
  if (v is List) return v.map(fromHost).toList();
  if (v is Iterable) return v.map(fromHost).toList();
  return v.toString();
}

JsObj _makeResponse(Map v) {
  final o = JsObj(null, 'Response');
  final body = v['body'];
  final headers = fromHost(v['headers']);
  JsFn fn(String n, Object? Function(List<Object?> a) f) => JsFn(n, (t, a) => f(a));
  o.props['body'] = fn('body', (a) => body);
  o.props['url'] = fn('url', (a) => v['url']);
  o.props['code'] = fn('code', (a) => normNum(v['code'] as num? ?? 0));
  o.props['message'] = fn('message', (a) => v['message']);
  o.props['headers'] = fn('headers', (a) => headers);
  o.props['header'] = fn('header', (a) {
    final h = headers is JsObj ? headers.props : const <String, Object?>{};
    final k = a.isEmpty ? '' : toStr(a[0]).toLowerCase();
    return h[k];
  });
  o.props['isSuccessful'] = fn('isSuccessful', (a) => ((v['code'] as num?) ?? 0) >= 200 && ((v['code'] as num?) ?? 0) < 300);
  o.props['raw'] = fn('raw', (a) => o);
  o.props['toString'] = fn('toString', (a) => body ?? '');
  return o;
}

/// JS value -> JSON-like Dart value (host objects stay [JsBindable]).
Object? toHost(Object? v, [int depth = 0]) {
  if (v is JsUndefined || v == null) return null;
  if (v is String || v is bool) return v;
  if (v is num) return v;
  if (v is HostObj) return v.b;
  if (depth > 40) return null;
  if (v is List) return v.map((e) => toHost(e, depth + 1)).toList();
  if (v is JsFn) return null;
  if (v is JsDate) return v.ms;
  if (v is JsRegex) return v.source;
  if (v is JsObj) {
    final m = <String, Object?>{};
    v.props.forEach((k, val) {
      if (val is! JsFn) m[k] = toHost(val, depth + 1);
    });
    return m;
  }
  return v.toString();
}

// ---------------------------------------------------------------------------------------------------------------------------
// property access
// ---------------------------------------------------------------------------------------------------------------------------
Object? _lookup(JsObj o, String key) {
  for (JsObj? p = o; p != null; p = p.proto) {
    final g = p.getters?[key];
    if (g != null) return g.invoke(o, const []);
    if (p.props.containsKey(key)) return p.props[key];
  }
  return undefinedValue;
}

JsFn _bound(String name, Object? self, Object? Function(Object? self, List<Object?> args) m) => JsFn(name, (t, a) => m(self, a));

Object? getProp(Object? o, String key) {
  if (o is String) {
    if (key == 'length') return o.length;
    final idx = int.tryParse(key);
    if (idx != null) return idx >= 0 && idx < o.length ? o[idx] : undefinedValue;
    final m = stringMethods[key];
    return m == null ? undefinedValue : _bound(key, o, m);
  }
  if (o is List<Object?>) {
    if (key == 'length') return o.length;
    final idx = int.tryParse(key);
    if (idx != null) return idx >= 0 && idx < o.length ? o[idx] : undefinedValue;
    final extra = _listProps[o];
    if (extra != null && extra.containsKey(key)) return extra[key];
    final m = arrayMethods[key];
    return m == null ? undefinedValue : _bound(key, o, m);
  }
  if (o is num) {
    final m = numberMethods[key];
    return m == null ? undefinedValue : _bound(key, o, m);
  }
  if (o is bool) {
    if (key == 'toString') return _bound(key, o, (s, a) => toStr(s));
    if (key == 'valueOf') return _bound(key, o, (s, a) => s);
    return undefinedValue;
  }
  if (o is JsFn) {
    switch (key) {
      case 'name':
        return o.name;
      case 'length':
        return o.arity;
      case 'prototype':
        return o.props.putIfAbsent('prototype', () {
          final p = JsObj(null, 'Object');
          p.props['constructor'] = o;
          return p;
        });
      case 'call':
        return JsFn('call', (t, a) => o.invoke(a.isEmpty ? undefinedValue : a[0], a.length > 1 ? a.sublist(1) : const []));
      case 'apply':
        return JsFn('apply', (t, a) => o.invoke(a.isEmpty ? undefinedValue : a[0], a.length > 1 && a[1] is List ? List<Object?>.from(a[1] as List) : const []));
      case 'bind':
        return JsFn('bound ${o.name}', (t, a) {
          final bt = a.isEmpty ? undefinedValue : a[0];
          final pre = a.length > 1 ? a.sublist(1) : <Object?>[];
          return JsFn(o.name, (t2, a2) => o.invoke(bt, [...pre, ...a2]));
        });
      case 'toString':
        return JsFn('toString', (t, a) => toStr(o));
    }
    if (o.props.containsKey(key)) return o.props[key];
    return undefinedValue;
  }
  if (o is JsRegex) {
    switch (key) {
      case 'lastIndex':
        return o.lastIndex;
      case 'source':
        return o.source;
      case 'flags':
        return o.flags;
      case 'global':
        return o.global;
      case 'ignoreCase':
        return o.flags.contains('i');
      case 'multiline':
        return o.flags.contains('m');
      case 'exec':
        return _bound(key, o, (s, a) => regexExec(o, toStr(a.isEmpty ? undefinedValue : a[0])));
      case 'test':
        return _bound(key, o, (s, a) => regexExec(o, toStr(a.isEmpty ? undefinedValue : a[0])) != null);
      case 'toString':
        return _bound(key, o, (s, a) => toStr(o));
    }
    return undefinedValue;
  }
  if (o is JsDate) {
    final m = dateMethods[key];
    if (m != null) return _bound(key, o, m);
    return undefinedValue;
  }
  if (o is JsObj) {
    final v = _lookup(o, key);
    if (v is! JsUndefined) return v;
    switch (key) {
      case 'hasOwnProperty':
        return JsFn('hasOwnProperty', (t, a) => o.props.containsKey(a.isEmpty ? '' : toStr(a[0])));
      case 'toString':
        return JsFn('toString', (t, a) => toStr(o), kind: 'objectToString');
      case 'valueOf':
        return JsFn('valueOf', (t, a) => o, kind: 'objectValueOf');
      case 'toJSON':
        return undefinedValue;
    }
    return undefinedValue;
  }
  if (o is HostObj) {
    final v = o.b.jsGet(key);
    if (!identical(v, JsBindable.noMember)) return fromHost(v);
    if (key == 'toString' || o.b.jsMethods.contains(key)) {
      return JsFn(key, (t, a) => hostCall(o.b, key, a));
    }
    return undefinedValue;
  }
  if (o == null) throw typeError("Cannot read properties of null (reading '$key')");
  if (o is JsUndefined) throw typeError("Cannot read properties of undefined (reading '$key')");
  return undefinedValue;
}

void setProp(Object? o, String key, Object? v) {
  if (o is List<Object?>) {
    if (key == 'length') {
      final n = toNum(v).toInt();
      if (n < o.length) {
        o.removeRange(n, o.length);
      } else {
        while (o.length < n) {
          o.add(undefinedValue);
        }
      }
      return;
    }
    final idx = int.tryParse(key);
    if (idx != null && idx >= 0) {
      while (o.length <= idx) {
        o.add(undefinedValue);
      }
      o[idx] = v;
      return;
    }
    setListProp(o, key, v);
    return;
  }
  if (o is JsObj) {
    for (JsObj? p = o; p != null; p = p.proto) {
      final s = p.setters?[key];
      if (s != null) {
        s.invoke(o, [v]);
        return;
      }
    }
    if (o is JsRegex && key == 'lastIndex') {
      o.lastIndex = toNum(v).toInt();
      return;
    }
    o.props[key] = v;
    return;
  }
  if (o is HostObj) {
    o.b.jsSet(key, toHost(v));
    return;
  }
  if (o == null) throw typeError("Cannot set properties of null (setting '$key')");
  if (o is JsUndefined) throw typeError("Cannot set properties of undefined (setting '$key')");
}

Object? hostCall(JsBindable b, String key, List<Object?> args) {
  final hostArgs = args.map((a) => toHost(a)).toList();
  try {
    return fromHost(b.jsCall(key, hostArgs));
  } on JsNoSuchMethod {
    throw typeError('${b.runtimeType}.$key is not a function');
  } on JsHostError catch (e) {
    throw JsThrow(makeError('Error', e.message));
  }
}

/// `o.key(...args)`.
Object? callMethod(Object? o, String key, List<Object?> args) {
  if (o is String) {
    final m = stringMethods[key];
    if (m != null) return m(o, args);
    if (key == 'length' && args.isEmpty) return o.length; // Rhino java.lang.String#length()
  } else if (o is List<Object?>) {
    final m = arrayMethods[key];
    if (m != null) return m(o, args);
    if (key == 'length' && args.isEmpty) return o.length;
    final extra = _listProps[o];
    if (extra != null && extra[key] is JsFn) return (extra[key] as JsFn).invoke(o, args);
  } else if (o is num) {
    final m = numberMethods[key];
    if (m != null) return m(o, args);
  } else if (o is HostObj) {
    if (o.b.jsMethods.contains(key) || key == 'toString') return hostCall(o.b, key, args);
    final p = o.b.jsGet(key);
    if (!identical(p, JsBindable.noMember)) {
      final f = fromHost(p);
      if (f is JsFn) return f.invoke(o, args);
    }
    throw typeError('${o.b.runtimeType}.$key is not a function');
  } else if (o is JsDate) {
    final m = dateMethods[key];
    if (m != null) return m(o, args);
  } else if (o == null) {
    throw typeError("Cannot read properties of null (reading '$key')");
  } else if (o is JsUndefined) {
    throw typeError("Cannot read properties of undefined (reading '$key')");
  }
  final f = getProp(o, key);
  if (f is JsFn) return f.invoke(o, args);
  throw typeError('${describeValue(o)}.$key is not a function');
}

String describeValue(Object? o) {
  if (o is String) return '"$o"';
  if (o is List) return 'array';
  if (o is JsObj) return 'object';
  return toStr(o);
}

Object? callValue(Object? f, Object? thisV, List<Object?> args) {
  if (f is JsFn) return f.invoke(thisV, args);
  throw typeError('${describeValue(f)} is not a function');
}

// ---------------------------------------------------------------------------------------------------------------------------
// regex
// ---------------------------------------------------------------------------------------------------------------------------
JsRegex makeRegex(String source, String flags) {
  try {
    final re = RegExp(source,
        caseSensitive: !flags.contains('i'), multiLine: flags.contains('m'), dotAll: flags.contains('s'), unicode: flags.contains('u'));
    return JsRegex(re, source, flags);
  } on FormatException catch (e) {
    throw JsThrow(makeError('SyntaxError', 'Invalid regular expression: /$source/: ${e.message}'));
  }
}

List<Object?> matchToArray(RegExpMatch m, String input) {
  final l = <Object?>[];
  for (var i = 0; i <= m.groupCount; i++) {
    l.add(m.group(i) ?? undefinedValue);
  }
  setListProp(l, 'index', m.start);
  setListProp(l, 'input', input);
  return l;
}

/// `RegExp.prototype.exec` (honours `lastIndex` for global/sticky); returns null when there is no match.
List<Object?>? regexExec(JsRegex r, String s) {
  final useLast = r.global || r.sticky;
  final start = useLast ? r.lastIndex : 0;
  if (start > s.length) {
    r.lastIndex = 0;
    return null;
  }
  final RegExpMatch? m = r.sticky ? r.re.matchAsPrefix(s, start) as RegExpMatch? : _matchFrom(r.re, s, start);
  if (m == null) {
    if (useLast) r.lastIndex = 0;
    return null;
  }
  if (useLast) r.lastIndex = m.end == m.start ? m.end + 1 : m.end;
  return matchToArray(m, s);
}

RegExpMatch? _matchFrom(RegExp re, String s, int start) {
  for (final m in re.allMatches(s, start)) {
    return m;
  }
  return null;
}

String _expandReplacement(String rep, RegExpMatch m, String input) {
  if (!rep.contains(r'$')) return rep;
  final sb = StringBuffer();
  var i = 0;
  while (i < rep.length) {
    final c = rep[i];
    if (c == r'$' && i + 1 < rep.length) {
      final n = rep[i + 1];
      if (n == r'$') {
        sb.write(r'$');
        i += 2;
        continue;
      }
      if (n == '&') {
        sb.write(m.group(0));
        i += 2;
        continue;
      }
      if (n == '`') {
        sb.write(input.substring(0, m.start));
        i += 2;
        continue;
      }
      if (n == "'") {
        sb.write(input.substring(m.end));
        i += 2;
        continue;
      }
      if (n == '<') {
        final close = rep.indexOf('>', i);
        if (close > 0) {
          try {
            sb.write(m.namedGroup(rep.substring(i + 2, close)) ?? '');
          } catch (_) {}
          i = close + 1;
          continue;
        }
      }
      final d1 = n.codeUnitAt(0) - 0x30;
      if (d1 >= 0 && d1 <= 9) {
        var idx = d1;
        var len = 2;
        if (i + 2 < rep.length) {
          final d2 = rep.codeUnitAt(i + 2) - 0x30;
          if (d2 >= 0 && d2 <= 9 && d1 * 10 + d2 <= m.groupCount && d1 * 10 + d2 > 0) {
            idx = d1 * 10 + d2;
            len = 3;
          }
        }
        if (idx >= 1 && idx <= m.groupCount) {
          sb.write(m.group(idx) ?? '');
          i += len;
          continue;
        }
      }
    }
    sb.write(c);
    i++;
  }
  return sb.toString();
}

String _strReplace(String s, List<Object?> a, bool all) {
  final pat = a.isNotEmpty ? a[0] : undefinedValue;
  final rep = a.length > 1 ? a[1] : undefinedValue;
  String expand(RegExpMatch m) {
    if (rep is JsFn) {
      final args = <Object?>[for (var i = 0; i <= m.groupCount; i++) m.group(i) ?? undefinedValue, m.start, s];
      return toStr(rep.invoke(undefinedValue, args));
    }
    return _expandReplacement(toStr(rep), m, s);
  }

  if (pat is JsRegex) {
    final global = pat.global || all;
    final matches = global ? pat.re.allMatches(s).toList() : [if (pat.re.firstMatch(s) != null) pat.re.firstMatch(s)!];
    if (matches.isEmpty) return s;
    final sb = StringBuffer();
    var last = 0;
    for (final m in matches) {
      sb.write(s.substring(last, m.start));
      sb.write(expand(m));
      last = m.end;
    }
    sb.write(s.substring(last));
    if (pat.global) pat.lastIndex = 0;
    return sb.toString();
  }
  final sp = toStr(pat);
  final re = RegExp(RegExp.escape(sp));
  final matches = all ? re.allMatches(s).toList() : [if (re.firstMatch(s) != null) re.firstMatch(s)!];
  if (matches.isEmpty) return s;
  final sb = StringBuffer();
  var last = 0;
  for (final m in matches) {
    sb.write(s.substring(last, m.start));
    sb.write(expand(m));
    last = m.end;
  }
  sb.write(s.substring(last));
  return sb.toString();
}

List<Object?> _strSplit(String s, List<Object?> a) {
  final sep = a.isNotEmpty ? a[0] : undefinedValue;
  final limit = a.length > 1 && a[1] is! JsUndefined ? toNum(a[1]).toInt() : 1 << 30;
  List<Object?> out;
  if (sep is JsUndefined) {
    out = [s];
  } else if (sep is JsRegex) {
    // ECMAScript split: try a sticky match at every position q; a match ending at the previous split point does not count.
    out = [];
    if (s.isEmpty) return sep.re.matchAsPrefix(s, 0) != null ? <Object?>[] : <Object?>[s];
    var p = 0;
    var q = 0;
    while (q < s.length) {
      final m = sep.re.matchAsPrefix(s, q);
      if (m == null || m.end == p) {
        q++;
        continue;
      }
      out.add(s.substring(p, q));
      for (var g = 1; g <= m.groupCount; g++) {
        out.add(m.group(g) ?? undefinedValue);
      }
      p = m.end;
      q = p == q ? q + 1 : p;
    }
    out.add(s.substring(p));
  } else {
    final sp = toStr(sep);
    if (sp.isEmpty) {
      out = s.codeUnits.map<Object?>((c) => String.fromCharCode(c)).toList();
    } else {
      out = s.split(sp);
    }
  }
  return out.length > limit ? out.sublist(0, limit) : out;
}

// ---------------------------------------------------------------------------------------------------------------------------
// String methods
// ---------------------------------------------------------------------------------------------------------------------------
typedef Method = Object? Function(Object? self, List<Object?> args);

Object? _arg(List<Object?> a, int i) => i < a.length ? a[i] : undefinedValue;
int _intArg(List<Object?> a, int i, int def) => i < a.length && a[i] is! JsUndefined ? toNum(a[i]).toInt() : def;

int _clampIndex(int v, int len) {
  if (v < 0) {
    v += len;
    if (v < 0) v = 0;
  }
  return v > len ? len : v;
}

final Map<String, Method> stringMethods = {
  'charAt': (s, a) {
    final str = s as String;
    final i = _intArg(a, 0, 0);
    return i >= 0 && i < str.length ? str[i] : '';
  },
  'charCodeAt': (s, a) {
    final str = s as String;
    final i = _intArg(a, 0, 0);
    return i >= 0 && i < str.length ? str.codeUnitAt(i) : double.nan;
  },
  'codePointAt': (s, a) {
    final str = s as String;
    final i = _intArg(a, 0, 0);
    if (i < 0 || i >= str.length) return undefinedValue;
    return str.runes.length == str.length ? str.codeUnitAt(i) : String.fromCharCodes(str.codeUnits.sublist(i)).runes.first;
  },
  'indexOf': (s, a) => (s as String).indexOf(toStr(_arg(a, 0)), _clampIndex(_intArg(a, 1, 0), s.length)),
  'lastIndexOf': (s, a) {
    final str = s as String;
    final from = a.length > 1 && a[1] is! JsUndefined && !toNum(a[1]).isNaN ? toNum(a[1]).toInt() : null;
    return str.lastIndexOf(toStr(_arg(a, 0)), from);
  },
  'includes': (s, a) => (s as String).contains(toStr(_arg(a, 0)), _clampIndex(_intArg(a, 1, 0), s.length)),
  'contains': (s, a) => (s as String).contains(toStr(_arg(a, 0))),
  'startsWith': (s, a) => (s as String).startsWith(toStr(_arg(a, 0)), _clampIndex(_intArg(a, 1, 0), s.length)),
  'endsWith': (s, a) {
    final str = s as String;
    final end = a.length > 1 && a[1] is! JsUndefined ? _clampIndex(toNum(a[1]).toInt(), str.length) : str.length;
    return str.substring(0, end).endsWith(toStr(_arg(a, 0)));
  },
  'slice': (s, a) {
    final str = s as String;
    final b = _clampIndex(_intArg(a, 0, 0), str.length);
    final e = _clampIndex(_intArg(a, 1, str.length), str.length);
    return b >= e ? '' : str.substring(b, e);
  },
  'substring': (s, a) {
    final str = s as String;
    var b = _intArg(a, 0, 0).clamp(0, str.length);
    var e = _intArg(a, 1, str.length).clamp(0, str.length);
    if (b > e) {
      final t = b;
      b = e;
      e = t;
    }
    return str.substring(b, e);
  },
  'substr': (s, a) {
    final str = s as String;
    final b = _clampIndex(_intArg(a, 0, 0), str.length);
    final len = _intArg(a, 1, str.length - b);
    final e = (b + len).clamp(b, str.length);
    return str.substring(b, e);
  },
  'toUpperCase': (s, a) => (s as String).toUpperCase(),
  'toLowerCase': (s, a) => (s as String).toLowerCase(),
  'toLocaleUpperCase': (s, a) => (s as String).toUpperCase(),
  'toLocaleLowerCase': (s, a) => (s as String).toLowerCase(),
  'trim': (s, a) => _jsTrim(s as String, true, true),
  'trimStart': (s, a) => _jsTrim(s as String, true, false),
  'trimEnd': (s, a) => _jsTrim(s as String, false, true),
  'trimLeft': (s, a) => _jsTrim(s as String, true, false),
  'trimRight': (s, a) => _jsTrim(s as String, false, true),
  'padStart': (s, a) {
    final str = s as String;
    final n = _intArg(a, 0, 0);
    final fill = a.length > 1 && a[1] is! JsUndefined ? toStr(a[1]) : ' ';
    return _pad(str, n, fill, true);
  },
  'padEnd': (s, a) {
    final str = s as String;
    final n = _intArg(a, 0, 0);
    final fill = a.length > 1 && a[1] is! JsUndefined ? toStr(a[1]) : ' ';
    return _pad(str, n, fill, false);
  },
  'repeat': (s, a) {
    final n = _intArg(a, 0, 0);
    if (n < 0) throw rangeError('Invalid count value: $n');
    return (s as String) * n;
  },
  'replace': (s, a) => _strReplace(s as String, a, false),
  'replaceAll': (s, a) => _strReplace(s as String, a, true),
  'replaceFirst': (s, a) {
    final p = _arg(a, 0);
    final re = p is JsRegex ? p.re : RegExp(RegExp.escape(toStr(p)));
    return JsReplaceFirst.apply(s as String, re, toStr(_arg(a, 1)));
  },
  'split': (s, a) => _strSplit(s as String, a),
  'concat': (s, a) => (s as String) + a.map(toStr).join(),
  'at': (s, a) {
    final str = s as String;
    var i = _intArg(a, 0, 0);
    if (i < 0) i += str.length;
    return i >= 0 && i < str.length ? str[i] : undefinedValue;
  },
  'localeCompare': (s, a) {
    final c = (s as String).compareTo(toStr(_arg(a, 0)));
    return c < 0 ? -1 : (c > 0 ? 1 : 0);
  },
  'normalize': (s, a) => s,
  'toString': (s, a) => s,
  'valueOf': (s, a) => s,
  'match': (s, a) {
    final str = s as String;
    final p = _arg(a, 0);
    final r = p is JsRegex ? p : makeRegex(p is JsUndefined ? '(?:)' : toStr(p), '');
    if (r.global) {
      final all = r.re.allMatches(str).map((m) => m.group(0)).toList();
      r.lastIndex = 0;
      return all.isEmpty ? null : all;
    }
    final m = r.re.firstMatch(str);
    return m == null ? null : matchToArray(m, str);
  },
  'matchAll': (s, a) {
    final str = s as String;
    final p = _arg(a, 0);
    final r = p is JsRegex ? p : makeRegex(toStr(p), 'g');
    return r.re.allMatches(str).map<Object?>((m) => matchToArray(m, str)).toList();
  },
  'search': (s, a) {
    final p = _arg(a, 0);
    final r = p is JsRegex ? p : makeRegex(toStr(p), '');
    final m = r.re.firstMatch(s as String);
    return m == null ? -1 : m.start;
  },
  // Java String API as exposed by Rhino
  'equals': (s, a) => s == _arg(a, 0),
  'equalsIgnoreCase': (s, a) => (s as String).toLowerCase() == toStr(_arg(a, 0)).toLowerCase(),
  'isEmpty': (s, a) => (s as String).isEmpty,
  'isBlank': (s, a) => (s as String).trim().isEmpty,
  'intern': (s, a) => s,
  'toCharArray': (s, a) => (s as String).codeUnits.map<Object?>((c) => String.fromCharCode(c)).toList(),
  'getBytes': (s, a) {
    final cs = a.isEmpty || a[0] is JsUndefined ? 'utf-8' : toStr(a[0]);
    return AppHttp.encodeWith(s as String, cs).map<Object?>((b) => b > 127 ? b - 256 : b).toList();
  },
  'compareTo': (s, a) => (s as String).compareTo(toStr(_arg(a, 0))),
};

class JsReplaceFirst {
  static String apply(String s, RegExp re, String rep) => s.replaceFirstMapped(re, (m) => _expandReplacement(rep, m as RegExpMatch, s));
}

String _jsTrim(String s, bool start, bool end) {
  bool ws(int c) => c == 0x20 || (c >= 0x09 && c <= 0x0d) || c == 0xa0 || c == 0xfeff || c == 0x2028 || c == 0x2029 || c == 0x3000 || (c >= 0x2000 && c <= 0x200a) || c == 0x1680 || c == 0x202f || c == 0x205f;
  var b = 0;
  var e = s.length;
  if (start) {
    while (b < e && ws(s.codeUnitAt(b))) {
      b++;
    }
  }
  if (end) {
    while (e > b && ws(s.codeUnitAt(e - 1))) {
      e--;
    }
  }
  return s.substring(b, e);
}

String _pad(String s, int n, String fill, bool atStart) {
  if (n <= s.length || fill.isEmpty) return s;
  final need = n - s.length;
  final sb = StringBuffer();
  while (sb.length < need) {
    sb.write(fill);
  }
  final p = sb.toString().substring(0, need);
  return atStart ? p + s : s + p;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Array methods
// ---------------------------------------------------------------------------------------------------------------------------
List<Object?> _list(Object? s) => s as List<Object?>;

Object? _cb(Object? f, List<Object?> a) => callValue(f, undefinedValue, a);

List<Object?> stableSort(List<Object?> list, Object? cmp) {
  int compare(Object? x, Object? y) {
    if (x is JsUndefined) return y is JsUndefined ? 0 : 1;
    if (y is JsUndefined) return -1;
    if (cmp is JsFn) {
      final r = toNum(cmp.invoke(undefinedValue, [x, y]));
      return r.isNaN ? 0 : (r < 0 ? -1 : (r > 0 ? 1 : 0));
    }
    return toStr(x).compareTo(toStr(y));
  }

  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((p, q) {
    final c = compare(p.$2, q.$2);
    return c != 0 ? c : p.$1.compareTo(q.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
  return list;
}

List<Object?> _flat(List<Object?> l, int depth) {
  final out = <Object?>[];
  for (final e in l) {
    if (e is List<Object?> && depth > 0) {
      out.addAll(_flat(e, depth - 1));
    } else {
      out.add(e);
    }
  }
  return out;
}

bool _sameValueZero(Object? a, Object? b) => (a is num && b is num && a.isNaN && b.isNaN) || strictEq(a, b);

final Map<String, Method> arrayMethods = {
  'push': (s, a) {
    _list(s).addAll(a);
    return _list(s).length;
  },
  'pop': (s, a) => _list(s).isEmpty ? undefinedValue : _list(s).removeLast(),
  'shift': (s, a) => _list(s).isEmpty ? undefinedValue : _list(s).removeAt(0),
  'unshift': (s, a) {
    _list(s).insertAll(0, a);
    return _list(s).length;
  },
  'slice': (s, a) {
    final l = _list(s);
    final b = _clampIndex(_intArg(a, 0, 0), l.length);
    final e = _clampIndex(_intArg(a, 1, l.length), l.length);
    return b >= e ? <Object?>[] : l.sublist(b, e);
  },
  'splice': (s, a) {
    final l = _list(s);
    final start = _clampIndex(_intArg(a, 0, 0), l.length);
    final del = a.length > 1 ? _intArg(a, 1, 0).clamp(0, l.length - start) : l.length - start;
    final removed = l.sublist(start, start + del);
    l.removeRange(start, start + del);
    if (a.length > 2) l.insertAll(start, a.sublist(2));
    return removed;
  },
  'concat': (s, a) {
    final out = List<Object?>.from(_list(s));
    for (final x in a) {
      if (x is List<Object?>) {
        out.addAll(x);
      } else {
        out.add(x);
      }
    }
    return out;
  },
  'join': (s, a) {
    final sep = a.isEmpty || a[0] is JsUndefined ? ',' : toStr(a[0]);
    return _list(s).map((e) => (e == null || e is JsUndefined) ? '' : toStr(e)).join(sep);
  },
  'reverse': (s, a) {
    final l = _list(s);
    final r = l.reversed.toList();
    for (var i = 0; i < l.length; i++) {
      l[i] = r[i];
    }
    return l;
  },
  'sort': (s, a) => stableSort(_list(s), _arg(a, 0)),
  'indexOf': (s, a) {
    final l = _list(s);
    for (var i = _clampIndex(_intArg(a, 1, 0), l.length); i < l.length; i++) {
      if (strictEq(l[i], _arg(a, 0))) return i;
    }
    return -1;
  },
  'lastIndexOf': (s, a) {
    final l = _list(s);
    for (var i = l.length - 1; i >= 0; i--) {
      if (strictEq(l[i], _arg(a, 0))) return i;
    }
    return -1;
  },
  'includes': (s, a) => _list(s).any((e) => _sameValueZero(e, _arg(a, 0))),
  'contains': (s, a) => _list(s).any((e) => looseEq(e, _arg(a, 0))),
  'map': (s, a) {
    final l = _list(s);
    final f = _arg(a, 0);
    return [for (var i = 0; i < l.length; i++) _cb(f, [l[i], i, l])];
  },
  'filter': (s, a) {
    final l = _list(s);
    final f = _arg(a, 0);
    return [for (var i = 0; i < l.length; i++) if (toBool(_cb(f, [l[i], i, l]))) l[i]];
  },
  'forEach': (s, a) {
    final l = _list(s);
    final f = _arg(a, 0);
    for (var i = 0; i < l.length; i++) {
      _cb(f, [l[i], i, l]);
    }
    return undefinedValue;
  },
  'reduce': (s, a) {
    final l = _list(s);
    final f = _arg(a, 0);
    var i = 0;
    Object? acc;
    if (a.length > 1) {
      acc = a[1];
    } else {
      if (l.isEmpty) throw typeError('Reduce of empty array with no initial value');
      acc = l[0];
      i = 1;
    }
    for (; i < l.length; i++) {
      acc = _cb(f, [acc, l[i], i, l]);
    }
    return acc;
  },
  'reduceRight': (s, a) {
    final l = _list(s);
    final f = _arg(a, 0);
    var i = l.length - 1;
    Object? acc;
    if (a.length > 1) {
      acc = a[1];
    } else {
      if (l.isEmpty) throw typeError('Reduce of empty array with no initial value');
      acc = l[i];
      i--;
    }
    for (; i >= 0; i--) {
      acc = _cb(f, [acc, l[i], i, l]);
    }
    return acc;
  },
  'find': (s, a) {
    final l = _list(s);
    for (var i = 0; i < l.length; i++) {
      if (toBool(_cb(_arg(a, 0), [l[i], i, l]))) return l[i];
    }
    return undefinedValue;
  },
  'findIndex': (s, a) {
    final l = _list(s);
    for (var i = 0; i < l.length; i++) {
      if (toBool(_cb(_arg(a, 0), [l[i], i, l]))) return i;
    }
    return -1;
  },
  'findLast': (s, a) {
    final l = _list(s);
    for (var i = l.length - 1; i >= 0; i--) {
      if (toBool(_cb(_arg(a, 0), [l[i], i, l]))) return l[i];
    }
    return undefinedValue;
  },
  'some': (s, a) {
    final l = _list(s);
    for (var i = 0; i < l.length; i++) {
      if (toBool(_cb(_arg(a, 0), [l[i], i, l]))) return true;
    }
    return false;
  },
  'every': (s, a) {
    final l = _list(s);
    for (var i = 0; i < l.length; i++) {
      if (!toBool(_cb(_arg(a, 0), [l[i], i, l]))) return false;
    }
    return true;
  },
  'flat': (s, a) => _flat(_list(s), _intArg(a, 0, 1)),
  'flatMap': (s, a) {
    final l = _list(s);
    final f = _arg(a, 0);
    return _flat([for (var i = 0; i < l.length; i++) _cb(f, [l[i], i, l])], 1);
  },
  'fill': (s, a) {
    final l = _list(s);
    final b = _clampIndex(_intArg(a, 1, 0), l.length);
    final e = _clampIndex(_intArg(a, 2, l.length), l.length);
    for (var i = b; i < e; i++) {
      l[i] = _arg(a, 0);
    }
    return l;
  },
  'keys': (s, a) => [for (var i = 0; i < _list(s).length; i++) i],
  'values': (s, a) => List<Object?>.from(_list(s)),
  'entries': (s, a) => [for (var i = 0; i < _list(s).length; i++) <Object?>[i, _list(s)[i]]],
  'at': (s, a) {
    final l = _list(s);
    var i = _intArg(a, 0, 0);
    if (i < 0) i += l.length;
    return i >= 0 && i < l.length ? l[i] : undefinedValue;
  },
  'toString': (s, a) => toStr(s),
  // java.util.List
  'add': (s, a) {
    if (a.length == 2) {
      _list(s).insert(_intArg(a, 0, 0), a[1]);
    } else {
      _list(s).add(_arg(a, 0));
    }
    return true;
  },
  'addAll': (s, a) {
    final x = _arg(a, 0);
    if (x is List<Object?>) _list(s).addAll(x);
    return true;
  },
  'get': (s, a) {
    final l = _list(s);
    final i = _intArg(a, 0, 0);
    if (i < 0 || i >= l.length) throw rangeError('Index: $i, Size: ${l.length}');
    return l[i];
  },
  'size': (s, a) => _list(s).length,
  'isEmpty': (s, a) => _list(s).isEmpty,
  'clear': (s, a) {
    _list(s).clear();
    return undefinedValue;
  },
};

// ---------------------------------------------------------------------------------------------------------------------------
// Number methods
// ---------------------------------------------------------------------------------------------------------------------------
final Map<String, Method> numberMethods = {
  'toFixed': (s, a) {
    final n = toNum(s);
    final d = _intArg(a, 0, 0);
    if (n.isNaN || n.isInfinite) return numToStr(n);
    return n.toDouble().toStringAsFixed(d);
  },
  'toString': (s, a) {
    final n = toNum(s);
    final radix = _intArg(a, 0, 10);
    if (radix == 10 || n.isNaN || n.isInfinite) return numToStr(n);
    if (n == n.truncate()) return n.toInt().toRadixString(radix);
    return numToStr(n);
  },
  'toPrecision': (s, a) {
    final n = toNum(s);
    if (a.isEmpty || a[0] is JsUndefined) return numToStr(n);
    return n.toDouble().toStringAsPrecision(_intArg(a, 0, 1));
  },
  'toLocaleString': (s, a) {
    final n = toNum(s);
    final str = n is int ? n.toString() : n.toString();
    final parts = str.split('.');
    final neg = parts[0].startsWith('-');
    final digits = neg ? parts[0].substring(1) : parts[0];
    final sb = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) sb.write(',');
      sb.write(digits[i]);
    }
    return '${neg ? '-' : ''}$sb${parts.length > 1 ? '.${parts[1]}' : ''}';
  },
  'valueOf': (s, a) => s,
};

// ---------------------------------------------------------------------------------------------------------------------------
// Date
// ---------------------------------------------------------------------------------------------------------------------------
String _p2(int v) => v.toString().padLeft(2, '0');

String dateToString(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final off = d.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final oh = off.inHours.abs(), om = off.inMinutes.abs() % 60;
  return '${days[d.weekday - 1]} ${months[d.month - 1]} ${_p2(d.day)} ${d.year} ${_p2(d.hour)}:${_p2(d.minute)}:${_p2(d.second)} GMT$sign${_p2(oh)}${_p2(om)}';
}

DateTime _dt(Object? self) => DateTime.fromMillisecondsSinceEpoch((self as JsDate).ms);
DateTime _dtu(Object? self) => DateTime.fromMillisecondsSinceEpoch((self as JsDate).ms, isUtc: true);

Object? _setDate(Object? self, DateTime Function(DateTime d) f, {bool utc = false}) {
  final d = f(utc ? _dtu(self) : _dt(self));
  (self as JsDate).ms = d.millisecondsSinceEpoch;
  return self.ms;
}

final Map<String, Method> dateMethods = {
  'getTime': (s, a) => (s as JsDate).ms,
  'valueOf': (s, a) => (s as JsDate).ms,
  'getFullYear': (s, a) => _dt(s).year,
  'getMonth': (s, a) => _dt(s).month - 1,
  'getDate': (s, a) => _dt(s).day,
  'getDay': (s, a) => _dt(s).weekday % 7,
  'getHours': (s, a) => _dt(s).hour,
  'getMinutes': (s, a) => _dt(s).minute,
  'getSeconds': (s, a) => _dt(s).second,
  'getMilliseconds': (s, a) => _dt(s).millisecond,
  'getUTCFullYear': (s, a) => _dtu(s).year,
  'getUTCMonth': (s, a) => _dtu(s).month - 1,
  'getUTCDate': (s, a) => _dtu(s).day,
  'getUTCDay': (s, a) => _dtu(s).weekday % 7,
  'getUTCHours': (s, a) => _dtu(s).hour,
  'getUTCMinutes': (s, a) => _dtu(s).minute,
  'getUTCSeconds': (s, a) => _dtu(s).second,
  'getTimezoneOffset': (s, a) => -_dt(s).timeZoneOffset.inMinutes,
  'setTime': (s, a) {
    (s as JsDate).ms = toNum(_arg(a, 0)).toInt();
    return s.ms;
  },
  'setFullYear': (s, a) => _setDate(s, (d) => DateTime(_intArg(a, 0, d.year), d.month, d.day, d.hour, d.minute, d.second, d.millisecond)),
  'setMonth': (s, a) => _setDate(s, (d) => DateTime(d.year, _intArg(a, 0, 0) + 1, d.day, d.hour, d.minute, d.second, d.millisecond)),
  'setDate': (s, a) => _setDate(s, (d) => DateTime(d.year, d.month, _intArg(a, 0, 1), d.hour, d.minute, d.second, d.millisecond)),
  'setHours': (s, a) => _setDate(s, (d) => DateTime(d.year, d.month, d.day, _intArg(a, 0, 0), d.minute, d.second, d.millisecond)),
  'setMinutes': (s, a) => _setDate(s, (d) => DateTime(d.year, d.month, d.day, d.hour, _intArg(a, 0, 0), d.second, d.millisecond)),
  'setSeconds': (s, a) => _setDate(s, (d) => DateTime(d.year, d.month, d.day, d.hour, d.minute, _intArg(a, 0, 0), d.millisecond)),
  'toISOString': (s, a) => _dtu(s).toIso8601String(),
  'toJSON': (s, a) => _dtu(s).toIso8601String(),
  'toString': (s, a) => dateToString((s as JsDate).ms),
  'toUTCString': (s, a) => _dtu(s).toString(),
  'toDateString': (s, a) => '${_dt(s).year}-${_p2(_dt(s).month)}-${_p2(_dt(s).day)}',
  'toLocaleDateString': (s, a) => '${_dt(s).year}/${_dt(s).month}/${_dt(s).day}',
  'toLocaleTimeString': (s, a) => '${_p2(_dt(s).hour)}:${_p2(_dt(s).minute)}:${_p2(_dt(s).second)}',
  'toLocaleString': (s, a) {
    final d = _dt(s);
    return '${d.year}/${d.month}/${d.day} ${_p2(d.hour)}:${_p2(d.minute)}:${_p2(d.second)}';
  },
};

/// UTF-8 bytes of [s] as signed Java bytes (what `String.getBytes()` returns in Rhino).
List<int> utf8SignedBytes(String s) => utf8.encode(s).map((b) => b > 127 ? b - 256 : b).toList();
