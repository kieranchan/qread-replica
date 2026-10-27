// util/legado/flutter_js_runtime.dart - production [JsRuntime] on `flutter_js` (JavaScriptCore on iOS, QuickJS on Android). NEVER
// instantiate it in host unit tests (it loads native code); tests use DartJsRuntime / FakeJsRuntime.
//
// Bridge protocol: the prelude defines `__call(object, method, args)` which sends `{"o","m","a"}` through the single `NR` channel of
// flutter_js; the Dart handler answers with a JSON string `{"v": value}` / `{"e": message}` / `{"p": 1}` (asynchronous native: the
// call is recorded in [_pending], the script is aborted and re-run by JsScriptRunner once the result is known). Native objects are
// exposed as `Proxy` objects: properties come from `JsBindable.jsSnapshot()`, everything else is a method call through the bridge.
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

import 'java_compat.dart' show toHost;
import 'js_bindable.dart';
import 'js_runtime.dart';

class FlutterJsRuntime extends JsRuntime {
  JavascriptRuntime? _rt;
  JsBindings? _bindings;
  JsPendingException? _pending;
  final Map<String, JsBindable> _handles = {};
  int _handleSeq = 0;

  static const String _prelude = r'''
var __NR_PENDING = '__NR_PENDING__';
function __nrWrap(v) {
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) { for (var i = 0; i < v.length; i++) v[i] = __nrWrap(v[i]); return v; }
  if (v.__nr === 'StrResponse') {
    var r = {};
    r.body = function() { return v.body; };
    r.url = function() { return v.url; };
    r.code = function() { return v.code; };
    r.message = function() { return v.message; };
    r.headers = function() { return v.headers; };
    r.header = function(n) { return v.headers ? v.headers[String(n).toLowerCase()] : null; };
    r.isSuccessful = function() { return v.code >= 200 && v.code < 300; };
    r.raw = function() { return r; };
    r.toString = function() { return v.body == null ? '' : String(v.body); };
    return r;
  }
  if (v.__nrh !== undefined) return __nrHost('#' + v.__nrh, v.props || {}, v.methods || []);
  for (var k in v) { if (Object.prototype.hasOwnProperty.call(v, k)) v[k] = __nrWrap(v[k]); }
  return v;
}
function __call(o, m, a) {
  var r = sendMessage('NR', JSON.stringify({o: o, m: m, a: a}));
  if (typeof r === 'string') r = JSON.parse(r);
  if (r && r.p) throw new Error(__NR_PENDING);
  if (r && r.e !== undefined) throw new Error(r.e);
  return __nrWrap(r ? r.v : null);
}
function __nrHost(name, props, methods) {
  var ms = {};
  for (var i = 0; i < methods.length; i++) ms[methods[i]] = true;
  return new Proxy({}, {
    get: function(t, k) {
      if (typeof k === 'symbol') return undefined;
      if (Object.prototype.hasOwnProperty.call(props, k)) return props[k];
      if (ms[k] || k === 'toString') return function() { return __call(name, k, Array.prototype.slice.call(arguments)); };
      return undefined;
    },
    set: function(t, k, v) { props[k] = v; __call(name, '$set', [k, v]); return true; },
    has: function(t, k) { return Object.prototype.hasOwnProperty.call(props, k) || !!ms[k]; }
  });
}
function __nrOut(v) {
  if (v === undefined || typeof v === 'function') return null;
  return v;
}
console.log = function() { __call('$console', 'log', Array.prototype.slice.call(arguments).map(String)); };
console.info = console.warn = console.error = console.debug = console.log;
1;
''';

  JavascriptRuntime _runtime() {
    final existing = _rt;
    if (existing != null) return existing;
    final rt = getJavascriptRuntime(xhr: false);
    rt.onMessage('NR', _onMessage);
    final r = rt.evaluate(_prelude);
    if (r.isError) throw JsException('JS prelude failed: ${r.stringResult}');
    return _rt = rt;
  }

  dynamic _onMessage(dynamic args) {
    try {
      final o = '${args['o']}';
      final m = '${args['m']}';
      final a = (args['a'] as List?) ?? const [];
      if (o == r'$console') {
        JsEvalContext.current?.logs.add(a.join(' '));
        return jsonEncode({'v': null});
      }
      final target = o.startsWith('#') ? _handles[o.substring(1)] : _bindings?.objects[o];
      if (target == null) return jsonEncode({'e': 'ReferenceError: $o is not defined'});
      if (m == r'$set') {
        target.jsSet('${a[0]}', a.length > 1 ? a[1] : null);
        return jsonEncode({'v': null});
      }
      final r = target.jsCall(m, List<Object?>.from(a));
      return jsonEncode({'v': _encode(r)});
    } on JsPendingException catch (p) {
      _pending = p;
      return jsonEncode({'p': 1});
    } on JsHostError catch (e) {
      return jsonEncode({'e': e.message});
    } on JsNoSuchMethod catch (e) {
      return jsonEncode({'e': e.toString()});
    } catch (e) {
      return jsonEncode({'e': e.toString()});
    }
  }

  /// Dart value -> JSON-able. Native objects become handles the prelude wraps in proxies again.
  Object? _encode(Object? v) {
    if (v == null || v is String || v is num || v is bool) return v;
    if (v is JsBindable) {
      final id = '${_handleSeq++}';
      _handles[id] = v;
      return {'__nrh': id, 'props': v.jsSnapshot(), 'methods': v.jsMethods.toList()};
    }
    if (v is Map) return v.map((k, val) => MapEntry('$k', _encode(val)));
    if (v is Iterable) return v.map(_encode).toList();
    return v.toString();
  }

  @override
  Object? evaluateSync(String script, JsBindings bindings) {
    final rt = _runtime();
    _bindings = bindings;
    _pending = null;
    _handles.clear();
    final sb = StringBuffer('(function(){try{\n');
    bindings.objects.forEach((name, obj) {
      sb.write('var $name = __nrHost(${jsonEncode(name)}, ${jsonEncode(_encode(obj.jsSnapshot()))}, ${jsonEncode(obj.jsMethods.toList())});\n');
    });
    bindings.values.forEach((name, value) {
      sb.write('var $name = JSON.parse(${jsonEncode(jsonEncode(toHost(value)))});\n');
    });
    sb.write('var __r = eval(${jsonEncode(script)});\n');
    sb.write('return JSON.stringify({ok: __nrOut(__r)});\n');
    sb.write('}catch(e){return JSON.stringify({err: String(e && e.message !== undefined ? e.message : e)});}})()');
    final res = rt.evaluate(sb.toString());
    final pending = _pending;
    _pending = null;
    _bindings = null;
    if (pending != null) throw pending;
    if (res.isError) throw JsException(res.stringResult);
    final text = res.stringResult;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw JsException('unexpected JS result: $text');
    }
    if (decoded is Map) {
      if (decoded.containsKey('err')) throw JsException('${decoded['err']}');
      return decoded['ok'];
    }
    return null;
  }

  @override
  void dispose() {
    _rt?.dispose();
    _rt = null;
  }
}
