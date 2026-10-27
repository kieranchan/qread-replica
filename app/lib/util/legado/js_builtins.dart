// util/legado/js_builtins.dart - the global objects of the pure Dart JavaScript interpreter: Math, JSON, Object, Array, String, Number,
// Boolean, Date, RegExp, Error types, Map, Set, console and the global functions (parseInt, encodeURIComponent, atob ...).
import 'dart:convert';
import 'dart:math' as math;

import '../webbook/analyze_rule/js_encode_utils.dart';
import 'java_compat.dart';

JsFn _fn(String name, NativeFn f, {int arity = 0, Object? Function(List<Object?>)? construct, String kind = ''}) =>
    JsFn(name, f, arity: arity, construct: construct, kind: kind);

Object? _a(List<Object?> a, int i) => i < a.length ? a[i] : undefinedValue;

JsObj _obj(Map<String, Object?> m) {
  final o = JsObj(null, 'Object');
  o.props.addAll(m);
  return o;
}

/// Creates the global scope values. [log] receives `console.log` lines.
Map<String, Object?> createGlobals(void Function(String line) log) {
  final g = <String, Object?>{};

  // ---- constants ----
  g['undefined'] = undefinedValue;
  g['NaN'] = double.nan;
  g['Infinity'] = double.infinity;

  // ---- global functions ----
  g['parseInt'] = _fn('parseInt', (t, a) => _parseInt(toStr(_a(a, 0)), a.length > 1 ? toNum(a[1]).toInt() : 10), arity: 2);
  g['parseFloat'] = _fn('parseFloat', (t, a) => _parseFloat(toStr(_a(a, 0))), arity: 1);
  g['isNaN'] = _fn('isNaN', (t, a) => toNum(_a(a, 0)).isNaN, arity: 1);
  g['isFinite'] = _fn('isFinite', (t, a) {
    final n = toNum(_a(a, 0));
    return !n.isNaN && !n.isInfinite;
  }, arity: 1);
  g['encodeURIComponent'] = _fn('encodeURIComponent', (t, a) => Uri.encodeComponent(toStr(_a(a, 0))).replaceAll('%20', '%20'), arity: 1);
  g['decodeURIComponent'] = _fn('decodeURIComponent', (t, a) => _decodeUri(toStr(_a(a, 0))), arity: 1);
  g['encodeURI'] = _fn('encodeURI', (t, a) => Uri.encodeFull(toStr(_a(a, 0))), arity: 1);
  g['decodeURI'] = _fn('decodeURI', (t, a) => _decodeUri(toStr(_a(a, 0))), arity: 1);
  g['escape'] = _fn('escape', (t, a) => JsEncodeUtils.escape(toStr(_a(a, 0))), arity: 1);
  g['unescape'] = _fn('unescape', (t, a) => JsEncodeUtils.unescape(toStr(_a(a, 0))), arity: 1);
  g['btoa'] = _fn('btoa', (t, a) => base64.encode(latin1.encode(toStr(_a(a, 0)))), arity: 1);
  g['atob'] = _fn('atob', (t, a) => latin1.decode(JsEncodeUtils.base64DecodeBytes(toStr(_a(a, 0)))), arity: 1);

  // ---- console ----
  JsFn logFn(String n) => _fn(n, (t, a) {
        log(a.map((e) => e is String ? e : (e is List || e is JsObj) ? _stringify(e, '') ?? toStr(e) : toStr(e)).join(' '));
        return undefinedValue;
      });
  g['console'] = _obj({'log': logFn('log'), 'info': logFn('info'), 'warn': logFn('warn'), 'error': logFn('error'), 'debug': logFn('debug')});

  // ---- Math ----
  final rnd = math.Random();
  num m1(List<Object?> a, double Function(double) f) => normNum(f(toNum(_a(a, 0)).toDouble()));
  g['Math'] = _obj({
    'PI': math.pi,
    'E': math.e,
    'LN2': math.ln2,
    'LN10': math.ln10,
    'SQRT2': math.sqrt2,
    'abs': _fn('abs', (t, a) => toNum(_a(a, 0)).abs()),
    'ceil': _fn('ceil', (t, a) => m1(a, (x) => x.ceilToDouble())),
    'floor': _fn('floor', (t, a) => m1(a, (x) => x.floorToDouble())),
    'round': _fn('round', (t, a) => m1(a, (x) => (x + 0.5).floorToDouble())),
    'trunc': _fn('trunc', (t, a) => m1(a, (x) => x.truncateToDouble())),
    'sign': _fn('sign', (t, a) {
      final n = toNum(_a(a, 0));
      return n.isNaN ? n : (n > 0 ? 1 : (n < 0 ? -1 : 0));
    }),
    'sqrt': _fn('sqrt', (t, a) => m1(a, math.sqrt)),
    'cbrt': _fn('cbrt', (t, a) => m1(a, (x) => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble())),
    'exp': _fn('exp', (t, a) => m1(a, math.exp)),
    'log': _fn('log', (t, a) => m1(a, math.log)),
    'log2': _fn('log2', (t, a) => m1(a, (x) => math.log(x) / math.ln2)),
    'log10': _fn('log10', (t, a) => m1(a, (x) => math.log(x) / math.ln10)),
    'sin': _fn('sin', (t, a) => m1(a, math.sin)),
    'cos': _fn('cos', (t, a) => m1(a, math.cos)),
    'tan': _fn('tan', (t, a) => m1(a, math.tan)),
    'atan': _fn('atan', (t, a) => m1(a, math.atan)),
    'atan2': _fn('atan2', (t, a) => normNum(math.atan2(toNum(_a(a, 0)).toDouble(), toNum(_a(a, 1)).toDouble()))),
    'pow': _fn('pow', (t, a) => normNum(math.pow(toNum(_a(a, 0)), toNum(_a(a, 1))))),
    'random': _fn('random', (t, a) => rnd.nextDouble()),
    'max': _fn('max', (t, a) {
      num r = double.negativeInfinity;
      for (final x in a) {
        final n = toNum(x);
        if (n.isNaN) return n;
        if (n > r) r = n;
      }
      return r;
    }, arity: 2),
    'min': _fn('min', (t, a) {
      num r = double.infinity;
      for (final x in a) {
        final n = toNum(x);
        if (n.isNaN) return n;
        if (n < r) r = n;
      }
      return r;
    }, arity: 2),
  });

  // ---- JSON ----
  g['JSON'] = _obj({
    'parse': _fn('parse', (t, a) {
      try {
        return fromHost(jsonDecode(toStr(_a(a, 0))));
      } on FormatException catch (e) {
        throw JsThrow(makeError('SyntaxError', 'Unexpected token in JSON: ${e.message}'));
      }
    }, arity: 2),
    'stringify': _fn('stringify', (t, a) {
      final ind = _a(a, 2);
      final indent = ind is num ? ' ' * ind.toInt().clamp(0, 10) : (ind is String ? ind : '');
      final r = _stringify(_a(a, 0), indent);
      return r ?? undefinedValue;
    }, arity: 3),
  });

  // ---- Object ----
  final objectCtor = _fn('Object', (t, a) => a.isEmpty || a[0] == null || a[0] is JsUndefined ? JsObj(null, 'Object') : a[0],
      construct: (a) => a.isEmpty || a[0] == null || a[0] is JsUndefined ? JsObj(null, 'Object') : a[0], kind: 'Object');
  List<Object?> keysOf(Object? o) {
    if (o is JsObj) return o.props.keys.toList();
    if (o is List) return [for (var i = 0; i < o.length; i++) '$i'];
    if (o is String) return [for (var i = 0; i < o.length; i++) '$i'];
    return <Object?>[];
  }

  objectCtor.props.addAll({
    'keys': _fn('keys', (t, a) => keysOf(_a(a, 0)), arity: 1),
    'values': _fn('values', (t, a) => [for (final k in keysOf(_a(a, 0))) getProp(_a(a, 0), '$k')], arity: 1),
    'entries': _fn('entries', (t, a) => [for (final k in keysOf(_a(a, 0))) <Object?>[k, getProp(_a(a, 0), '$k')]], arity: 1),
    'assign': _fn('assign', (t, a) {
      final target = _a(a, 0);
      for (final src in a.skip(1)) {
        if (src is JsObj) {
          src.props.forEach((k, v) => setProp(target, k, v));
        }
      }
      return target;
    }, arity: 2),
    'freeze': _fn('freeze', (t, a) => _a(a, 0)),
    'isFrozen': _fn('isFrozen', (t, a) => false),
    'seal': _fn('seal', (t, a) => _a(a, 0)),
    'fromEntries': _fn('fromEntries', (t, a) {
      final o = JsObj(null, 'Object');
      final src = _a(a, 0);
      if (src is List) {
        for (final e in src) {
          if (e is List && e.isNotEmpty) o.props[toStr(e[0])] = e.length > 1 ? e[1] : undefinedValue;
        }
      }
      return o;
    }),
    'getOwnPropertyNames': _fn('getOwnPropertyNames', (t, a) => keysOf(_a(a, 0))),
    'create': _fn('create', (t, a) {
      final o = JsObj(_a(a, 0) is JsObj ? _a(a, 0) as JsObj : null, 'Object');
      return o;
    }),
    'getPrototypeOf': _fn('getPrototypeOf', (t, a) => (_a(a, 0) is JsObj ? (_a(a, 0) as JsObj).proto : null)),
    'setPrototypeOf': _fn('setPrototypeOf', (t, a) {
      if (_a(a, 0) is JsObj) (_a(a, 0) as JsObj).proto = _a(a, 1) is JsObj ? _a(a, 1) as JsObj : null;
      return _a(a, 0);
    }),
    'defineProperty': _fn('defineProperty', (t, a) {
      final o = _a(a, 0);
      final key = toStr(_a(a, 1));
      final d = _a(a, 2);
      if (o is JsObj && d is JsObj) {
        final get = d.props['get'];
        final set = d.props['set'];
        if (get is JsFn) (o.getters ??= {})[key] = get;
        if (set is JsFn) (o.setters ??= {})[key] = set;
        if (d.props.containsKey('value')) o.props[key] = d.props['value'];
      }
      return o;
    }),
  });
  g['Object'] = objectCtor;

  // ---- Array ----
  final arrayCtor = _fn('Array', (t, a) => _newArray(a), construct: _newArray, kind: 'Array');
  arrayCtor.props.addAll({
    'isArray': _fn('isArray', (t, a) => _a(a, 0) is List),
    'of': _fn('of', (t, a) => List<Object?>.from(a)),
    'from': _fn('from', (t, a) {
      final src = _a(a, 0);
      final f = _a(a, 1);
      List<Object?> base;
      if (src is List) {
        base = List<Object?>.from(src);
      } else if (src is String) {
        base = src.runes.map<Object?>((r) => String.fromCharCode(r)).toList();
      } else if (src is JsObj && src.props['length'] is num) {
        final n = (src.props['length'] as num).toInt();
        base = [for (var i = 0; i < n; i++) src.props['$i'] ?? undefinedValue];
      } else {
        base = [];
      }
      if (f is JsFn) return [for (var i = 0; i < base.length; i++) f.invoke(undefinedValue, [base[i], i])];
      return base;
    }, arity: 1),
  });
  g['Array'] = arrayCtor;

  // ---- String / Number / Boolean ----
  final stringCtor = _fn('String', (t, a) => a.isEmpty ? '' : toStr(a[0]), construct: (a) => a.isEmpty ? '' : toStr(a[0]), kind: 'String');
  stringCtor.props['fromCharCode'] = _fn('fromCharCode', (t, a) => String.fromCharCodes(a.map((e) => toNum(e).toInt() & 0xffff)));
  stringCtor.props['fromCodePoint'] = _fn('fromCodePoint', (t, a) => String.fromCharCodes(a.map((e) => toNum(e).toInt())));
  g['String'] = stringCtor;

  final numberCtor = _fn('Number', (t, a) => a.isEmpty ? 0 : toNum(a[0]), construct: (a) => a.isEmpty ? 0 : toNum(a[0]), kind: 'Number');
  numberCtor.props.addAll({
    'MAX_SAFE_INTEGER': 9007199254740991,
    'MIN_SAFE_INTEGER': -9007199254740991,
    'MAX_VALUE': double.maxFinite,
    'MIN_VALUE': 5e-324,
    'EPSILON': 2.220446049250313e-16,
    'POSITIVE_INFINITY': double.infinity,
    'NEGATIVE_INFINITY': double.negativeInfinity,
    'NaN': double.nan,
    'isInteger': _fn('isInteger', (t, a) => _a(a, 0) is num && (_a(a, 0) as num).isFinite && (_a(a, 0) as num) == (_a(a, 0) as num).truncate()),
    'isFinite': _fn('isFinite', (t, a) => _a(a, 0) is num && (_a(a, 0) as num).isFinite),
    'isNaN': _fn('isNaN', (t, a) => _a(a, 0) is num && (_a(a, 0) as num).isNaN),
    'parseFloat': g['parseFloat'],
    'parseInt': g['parseInt'],
  });
  g['Number'] = numberCtor;
  g['Boolean'] = _fn('Boolean', (t, a) => toBool(_a(a, 0)), construct: (a) => toBool(_a(a, 0)), kind: 'Boolean');

  // ---- Date ----
  JsDate newDate(List<Object?> a) {
    if (a.isEmpty) return JsDate(DateTime.now().millisecondsSinceEpoch);
    if (a.length == 1) {
      final v = a[0];
      if (v is JsDate) return JsDate(v.ms);
      if (v is num) return JsDate(v.toInt());
      return JsDate(_parseDate(toStr(v)) ?? 0);
    }
    final p = [for (var i = 0; i < 7; i++) i < a.length ? toNum(a[i]).toInt() : (i == 2 ? 1 : 0)];
    return JsDate(DateTime(p[0], p[1] + 1, p[2], p[3], p[4], p[5], p[6]).millisecondsSinceEpoch);
  }

  final dateCtor = _fn('Date', (t, a) => dateToString(DateTime.now().millisecondsSinceEpoch), construct: newDate, kind: 'Date');
  dateCtor.props.addAll({
    'now': _fn('now', (t, a) => DateTime.now().millisecondsSinceEpoch),
    'parse': _fn('parse', (t, a) => _parseDate(toStr(_a(a, 0))) ?? double.nan),
    'UTC': _fn('UTC', (t, a) {
      final p = [for (var i = 0; i < 7; i++) i < a.length ? toNum(a[i]).toInt() : (i == 2 ? 1 : 0)];
      return DateTime.utc(p[0], p[1] + 1, p[2], p[3], p[4], p[5], p[6]).millisecondsSinceEpoch;
    }),
  });
  g['Date'] = dateCtor;

  // ---- RegExp ----
  JsRegex newRegex(List<Object?> a) {
    final p = _a(a, 0);
    final f = _a(a, 1);
    if (p is JsRegex) return makeRegex(p.source, f is JsUndefined ? p.flags : toStr(f));
    return makeRegex(p is JsUndefined ? '(?:)' : toStr(p), f is JsUndefined ? '' : toStr(f));
  }

  g['RegExp'] = _fn('RegExp', (t, a) => newRegex(a), construct: newRegex, kind: 'RegExp');

  // ---- Errors ----
  for (final name in const ['Error', 'TypeError', 'RangeError', 'SyntaxError', 'ReferenceError', 'EvalError', 'URIError']) {
    JsObj make(List<Object?> a) {
      final e = makeError(name, a.isEmpty || a[0] is JsUndefined ? '' : toStr(a[0]));
      return e;
    }

    final ctor = _fn(name, (t, a) => make(a), construct: make, kind: 'Error');
    ctor.props['prototype'] = errorProto;
    g[name] = ctor;
  }
  errorProto.props['toString'] = _fn('toString', (t, a) => describeError(t));

  // ---- Map / Set ----
  g['Map'] = _fn('Map', (t, a) => _newMap(a, false), construct: (a) => _newMap(a, false), kind: 'Map');
  g['Set'] = _fn('Set', (t, a) => _newMap(a, true), construct: (a) => _newMap(a, true), kind: 'Set');

  return g;
}

List<Object?> _newArray(List<Object?> a) {
  if (a.length == 1 && a[0] is num) {
    return List<Object?>.filled((a[0] as num).toInt(), undefinedValue, growable: true);
  }
  return List<Object?>.from(a);
}

Object _mapKey(Object? k) {
  if (k is num) return k is double && k == k.truncateToDouble() ? k.toInt() : k;
  if (k == null) return 'null:';
  if (k is JsUndefined) return 'undefined:';
  if (k is String) return 's:$k';
  if (k is bool) return 'b:$k';
  return k;
}

JsObj _newMap(List<Object?> init, bool isSet) {
  final data = <Object, List<Object?>>{}; // key -> [key, value]
  final o = JsObj(null, isSet ? 'Set' : 'Map');
  o.getters = {'size': _fn('size', (t, a) => data.length)};
  void put(Object? k, Object? v) => data[_mapKey(k)] = [k, v];
  if (init.isNotEmpty && init[0] is List) {
    for (final e in init[0] as List) {
      if (isSet) {
        put(e, e);
      } else if (e is List && e.isNotEmpty) {
        put(e[0], e.length > 1 ? e[1] : undefinedValue);
      }
    }
  }
  o.props['has'] = _fn('has', (t, a) => data.containsKey(_mapKey(_a(a, 0))));
  o.props['delete'] = _fn('delete', (t, a) => data.remove(_mapKey(_a(a, 0))) != null);
  o.props['clear'] = _fn('clear', (t, a) {
    data.clear();
    return undefinedValue;
  });
  if (isSet) {
    o.props['add'] = _fn('add', (t, a) {
      put(_a(a, 0), _a(a, 0));
      return o;
    });
  } else {
    o.props['get'] = _fn('get', (t, a) => data[_mapKey(_a(a, 0))]?[1] ?? undefinedValue);
    o.props['set'] = _fn('set', (t, a) {
      put(_a(a, 0), _a(a, 1));
      return o;
    });
  }
  o.props['keys'] = _fn('keys', (t, a) => [for (final e in data.values) e[0]]);
  o.props['values'] = _fn('values', (t, a) => [for (final e in data.values) e[1]]);
  o.props['entries'] = _fn('entries', (t, a) => [for (final e in data.values) <Object?>[e[0], e[1]]]);
  o.props['forEach'] = _fn('forEach', (t, a) {
    final f = _a(a, 0);
    for (final e in data.values.toList()) {
      callValue(f, undefinedValue, [e[1], e[0], o]);
    }
    return undefinedValue;
  });
  return o;
}

Object? _parseInt(String s, int radix) {
  var t = s.trim();
  var neg = false;
  if (t.startsWith('-')) {
    neg = true;
    t = t.substring(1);
  } else if (t.startsWith('+')) {
    t = t.substring(1);
  }
  var r = radix;
  if ((r == 16 || r == 0) && (t.startsWith('0x') || t.startsWith('0X'))) {
    t = t.substring(2);
    r = 16;
  }
  if (r == 0) r = 10;
  if (r < 2 || r > 36) return double.nan;
  var end = 0;
  while (end < t.length) {
    final d = int.tryParse(t[end], radix: r);
    if (d == null) break;
    end++;
  }
  if (end == 0) return double.nan;
  final v = int.parse(t.substring(0, end), radix: r);
  return neg ? -v : v;
}

Object? _parseFloat(String s) {
  final m = RegExp(r'^\s*([+-]?(?:Infinity|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?))').firstMatch(s);
  if (m == null) return double.nan;
  final t = m.group(1)!;
  if (t.endsWith('Infinity')) return t.startsWith('-') ? double.negativeInfinity : double.infinity;
  return normNum(double.parse(t));
}

String _decodeUri(String s) {
  try {
    return Uri.decodeComponent(s);
  } on ArgumentError {
    throw JsThrow(makeError('URIError', 'URI malformed'));
  }
}

int? _parseDate(String s) {
  final t = s.trim();
  var d = DateTime.tryParse(t);
  d ??= DateTime.tryParse(t.replaceAll('/', '-'));
  if (d == null) {
    final m = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$').firstMatch(t);
    if (m != null) {
      d = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), int.parse(m.group(4) ?? '0'), int.parse(m.group(5) ?? '0'), int.parse(m.group(6) ?? '0'));
    }
  }
  return d?.millisecondsSinceEpoch;
}

/// `JSON.stringify` of a JS value; null when the value is `undefined`/a function (the caller turns that into `undefined`).
String? _stringify(Object? v, String indent) => _ser(v, indent, '', 0);

String? _ser(Object? v, String indent, String cur, int depth) {
  if (depth > 100) return null;
  if (v is JsUndefined || v is JsFn) return null;
  if (v == null) return 'null';
  if (v is bool) return v.toString();
  if (v is num) return v.isNaN || v.isInfinite ? 'null' : numToStr(v);
  if (v is String) return jsonEncode(v);
  if (v is JsDate) return jsonEncode(DateTime.fromMillisecondsSinceEpoch(v.ms, isUtc: true).toIso8601String());
  if (v is HostObj) return jsonEncode(toHost(v));
  final inner = indent.isEmpty ? '' : '$cur$indent';
  final nl = indent.isEmpty ? '' : '\n';
  final sep = indent.isEmpty ? ',' : ',\n';
  if (v is List) {
    if (v.isEmpty) return '[]';
    final parts = [for (final e in v) _ser(e, indent, inner, depth + 1) ?? 'null'];
    return '[$nl${parts.map((p) => '$inner$p').join(sep)}$nl${indent.isEmpty ? '' : cur}]';
  }
  if (v is JsObj) {
    final toJson = v.props['toJSON'];
    if (toJson is JsFn) return _ser(toJson.invoke(v, const []), indent, cur, depth + 1);
    final parts = <String>[];
    v.props.forEach((k, val) {
      final s = _ser(val, indent, inner, depth + 1);
      if (s != null) parts.add('$inner${jsonEncode(k)}:${indent.isEmpty ? '' : ' '}$s');
    });
    if (parts.isEmpty) return '{}';
    return '{$nl${parts.join(sep)}$nl${indent.isEmpty ? '' : cur}}';
  }
  return null;
}
