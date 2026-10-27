import 'package:flutter_test/flutter_test.dart';
import 'package:newread/util/legado/js_bindable.dart';
import 'package:newread/util/legado/js_runtime.dart';
import 'package:newread/util/legado/script_engine.dart';

class _Host extends JsBindable {
  final List<String> calls = [];
  final Map<String, Object?> store = {};

  @override
  Iterable<String> get jsMethods => const ['echo', 'put', 'get', 'boom', 'list'];

  @override
  Object? jsGet(String name) => name == 'tag' ? 'host-tag' : JsBindable.noMember;

  @override
  Object? jsCall(String name, List<Object?> args) {
    calls.add(name);
    switch (name) {
      case 'echo':
        return args.isEmpty ? null : args[0];
      case 'put':
        store['${args[0]}'] = args[1];
        return args[1];
      case 'get':
        return store['${args[0]}'];
      case 'boom':
        throw JsHostError('host exploded');
      case 'list':
        return [1, 2, 3];
    }
    return super.jsCall(name, args);
  }
}

Object? js(String code, {Map<String, Object?> values = const {}, Map<String, JsBindable> objects = const {}}) {
  final rt = DartJsRuntime();
  return rt.evaluateSync(code, JsBindings(values: Map.of(values), objects: Map.of(objects)));
}

void main() {
  group('expressions and statements', () {
    test('arithmetic and string concat', () {
      expect(js('1 + 2 * 3'), 7);
      expect(js('"a" + 1 + 2'), 'a12');
      expect(js('1 + 2 + "a"'), '3a');
      expect(js('10 / 4'), 2.5);
      expect(js('7 % 3'), 1);
      expect(js('2 ** 10'), 1024);
      expect(js('(1 + 2) * 3'), 9);
      expect(js('-5 + +"3"'), -2);
    });

    test('variables, let/const, blocks, hoisting', () {
      expect(js('var a = 1; { let a = 2; } a'), 1);
      expect(js('function f(){ return g(); } function g(){ return 42; } f()'), 42);
      expect(js('x = 5; x'), 5);
      expect(js('var a = 1, b = 2; a + b'), 3);
      expect(() => js('const c = 1; c = 2;'), throwsA(isA<JsException>()));
    });

    test('functions, closures, arrows, default and rest params', () {
      expect(js('var add = function(a, b){ return a + b }; add(2, 3)'), 5);
      expect(js('const mk = n => () => n++; const c = mk(5); c(); c()'), 6);
      expect(js('function f(a, b = 10){ return a + b } f(1)'), 11);
      expect(js('function f(...r){ return r.length } f(1,2,3)'), 3);
      expect(js('((a, b) => a * b)(6, 7)'), 42);
      expect(js('function fact(n){ return n <= 1 ? 1 : n * fact(n - 1) } fact(10)'), 3628800);
    });

    test('control flow', () {
      expect(js('var s = 0; for (var i = 0; i < 5; i++) { s += i } s'), 10);
      expect(js('var s = 0; for (let i = 0; i < 10; i++) { if (i == 3) continue; if (i == 6) break; s += i } s'), 12);
      expect(js('var i = 0; while (i < 5) i++; i'), 5);
      expect(js('var i = 0; do { i++ } while (i < 3); i'), 3);
      expect(js('var r = []; for (var k in {a:1,b:2}) r.push(k); r.join()'), 'a,b');
      expect(js('var r = 0; for (const v of [1,2,3]) r += v; r'), 6);
      expect(js('switch (2) { case 1: "one"; break; case 2: "two"; break; default: "x" }'), 'two');
      expect(js('outer: for (var i=0;i<3;i++){ for (var j=0;j<3;j++){ if (j==1) continue outer; if (i==2) break outer; } } i'), 2);
    });

    test('try/catch/finally and throw', () {
      expect(js('try { throw new Error("boom") } catch (e) { e.message }'), 'boom');
      expect(js('var r = ""; try { r += "a" } finally { r += "b" } r'), 'ab');
      expect(js('try { null.x } catch (e) { e.name }'), 'TypeError');
      expect(js('try { undefinedVar } catch (e) { e.name }'), 'ReferenceError');
      expect(() => js('throw new Error("x")'), throwsA(isA<JsException>()));
    });

    test('operators: typeof, ??, ?., ternary, in, instanceof', () {
      expect(js('typeof 1'), 'number');
      expect(js('typeof "s"'), 'string');
      expect(js('typeof undefined'), 'undefined');
      expect(js('typeof notDefinedAnywhere'), 'undefined');
      expect(js('typeof null'), 'object');
      expect(js('typeof function(){}'), 'function');
      expect(js('null ?? "d"'), 'd');
      expect(js('0 ?? "d"'), 0);
      expect(js('var o = null; o?.a.b'), null);
      expect(js('var o = {a:{b:3}}; o?.a?.b'), 3);
      expect(js('"a" in {a:1}'), true);
      expect(js('[] instanceof Array'), true);
      expect(js('1 == "1"'), true);
      expect(js('1 === "1"'), false);
      expect(js('null == undefined'), true);
      expect(js('"b" > "a"'), true);
      expect(js('5 & 3'), 1);
      expect(js('1 << 3'), 8);
      expect(js('-1 >>> 28'), 15);
    });

    test('template literals, destructuring, spread', () {
      expect(js(r'const n = 3; `v=${n * 2} ${"x"}`'), 'v=6 x');
      expect(js('const {a, b: {c}} = {a: 1, b: {c: 2}}; a + c'), 3);
      expect(js('const [x, , y = 9] = [1, 2]; x + y'), 10);
      expect(js('var a = 1, b = 2; [a, b] = [b, a]; a * 10 + b'), 21);
      expect(js('Math.max(...[1, 5, 3])'), 5);
      expect(js('[...[1,2], ...[3]].length'), 3);
      expect(js('const o = {...{a:1}, b:2}; o.a + o.b'), 3);
      expect(js('function f({a, b}){ return a + b } f({a:1,b:2})'), 3);
    });

    test('objects, getters, prototypes, new', () {
      expect(js('var o = {a:1, get b(){ return this.a + 1 }}; o.b'), 2);
      expect(js('function P(n){ this.n = n } P.prototype.get = function(){ return this.n }; new P(7).get()'), 7);
      expect(js('var o = {f(){ return this.k }, k: 4}; o.f()'), 4);
      expect(js('var o = {a:1}; delete o.a; "a" in o'), false);
      expect(js('JSON.stringify({a:[1,{b:2}], c:"x"})'), '{"a":[1,{"b":2}],"c":"x"}');
      expect(js('JSON.parse("{\\"a\\":[1,2]}").a[1]'), 2);
      expect(js('var o = {}; o["k" + 1] = 5; o.k1'), 5);
      expect(js('this.toString()'), '[object Object]');
    });

    test('completion value is the last expression statement', () {
      expect(js('var a = 1; a + 1'), 2);
      expect(js('if (true) { "yes" } else { "no" }'), 'yes');
      expect(js('1; 2; 3'), 3);
      expect(js('var x = 5;'), null);
    });

    test('infinite loops are stopped', () {
      expect(() => js('while (true) {}'), throwsA(isA<JsException>()));
    });
  });

  group('builtins', () {
    test('string methods', () {
      expect(js('"Hello".toUpperCase()'), 'HELLO');
      expect(js('"a,b,c".split(",").length'), 3);
      expect(js('"abc".replace("b", "X")'), 'aXc');
      expect(js('"a1b22".replace(/\\d+/g, "#")'), 'a#b#');
      expect(js('"John Smith".replace(/(\\w+)\\s(\\w+)/, "\$2, \$1")'), 'Smith, John');
      expect(js('"x-y-z".replaceAll("-", "+")'), 'x+y+z');
      expect(js('"abc".substring(1)'), 'bc');
      expect(js('"abc".slice(-2)'), 'bc');
      expect(js('"abc".indexOf("c")'), 2);
      expect(js('"  pad ".trim()'), 'pad');
      expect(js('"5".padStart(3, "0")'), '005');
      expect(js('"abc".charAt(1)'), 'b');
      expect(js('"abc".charCodeAt(0)'), 97);
      expect(js('"abc".includes("bc")'), true);
      expect(js('"a1b2".match(/\\d/g).join("")'), '12');
      expect(js('"abc".match(/(b)(c)/)[2]'), 'c');
      expect(js('"a  b".split(/\\s+/).join("|")'), 'a|b');
      expect(js('"abc".split("").reverse().join("")'), 'cba');
      expect(js('"x".repeat(3)'), 'xxx');
      expect(js('"abc".length'), 3);
    });

    test('java-style string methods', () {
      expect(js('"abc".equals("abc")'), true);
      expect(js('"abc".contains("b")'), true);
      expect(js('"".isEmpty()'), true);
      expect(js('"abc".length()'), 3);
      expect(js('"AbC".equalsIgnoreCase("abc")'), true);
      expect(js('"é".getBytes().length'), 2);
    });

    test('array methods', () {
      expect(js('[3,1,2].sort().join()'), '1,2,3');
      expect(js('[3,1,10].sort().join()'), '1,10,3');
      expect(js('[3,1,10].sort(function(a,b){return a-b}).join()'), '1,3,10');
      expect(js('[1,2,3].map(x => x * 2).join()'), '2,4,6');
      expect(js('[1,2,3,4].filter(x => x % 2 == 0).length'), 2);
      expect(js('[1,2,3].reduce((a, b) => a + b, 0)'), 6);
      expect(js('[1,2,3].indexOf(2)'), 1);
      expect(js('[1,[2,[3]]].flat(2).length'), 3);
      expect(js('[1,2,3].slice(1).join()'), '2,3');
      expect(js('var a=[1,2,3,4]; a.splice(1,2); a.join()'), '1,4');
      expect(js('[1,2,3].find(x => x > 1)'), 2);
      expect(js('[1,2,3].some(x => x > 2)'), true);
      expect(js('[1,2,3].every(x => x > 2)'), false);
      expect(js('Array.from({length: 3}, (v, i) => i * 2).join()'), '0,2,4');
      expect(js('[1,2].concat([3], 4).length'), 4);
      expect(js('Array.isArray([])'), true);
      expect(js('var a=[]; a.push(1,2); a.length'), 2);
      expect(js('[1,2,3].includes(2)'), true);
    });

    test('Math, Number, JSON, Date, RegExp', () {
      expect(js('Math.floor(3.7)'), 3);
      expect(js('Math.round(2.5)'), 3);
      expect(js('Math.round(-2.5)'), -2);
      expect(js('Math.abs(-4)'), 4);
      expect(js('Math.min(3, 1, 2)'), 1);
      expect(js('Math.pow(2, 8)'), 256);
      expect(js('parseInt("42px")'), 42);
      expect(js('parseInt("ff", 16)'), 255);
      expect(js('parseFloat("3.5abc")'), 3.5);
      expect(js('(1.005).toFixed(2)'), '1.00');
      expect(js('(255).toString(16)'), 'ff');
      expect(js('Number("12")'), 12);
      expect(js('isNaN("abc")'), true);
      expect(js('Number.isInteger(5)'), true);
      expect(js('new Date(0).getTime()'), 0);
      expect(js('new Date(2020, 0, 15).getFullYear()'), 2020);
      expect(js('/a(b)/.exec("xab")[1]'), 'b');
      expect(js('/^\\d+\$/.test("123")'), true);
      expect(js('encodeURIComponent("a b&c")'), 'a%20b%26c');
      expect(js('decodeURIComponent("%E4%BD%A0")'), '你');
      expect(js('var m = new Map(); m.set("a", 1); m.get("a") + m.size'), 2);
      expect(js('var s = new Set([1,1,2]); s.size'), 2);
    });
  });

  group('host bridge', () {
    test('values and objects', () {
      final host = _Host();
      expect(js('java.echo("hi")', objects: {'java': host}), 'hi');
      expect(js('java.tag', objects: {'java': host}), 'host-tag');
      expect(js('result + 1', values: {'result': 41}), 42);
      expect(js('result.a + result.b[1]', values: {'result': {'a': 1, 'b': [5, 6]}}), 7);
      expect(js('java.list().length', objects: {'java': host}), 3);
      expect(js('java.put("k", "v"); java.get("k")', objects: {'java': host}), 'v');
      expect(host.calls, containsAll(['put', 'get']));
    });

    test('host errors are catchable', () {
      final host = _Host();
      expect(js('try { java.boom() } catch (e) { e.message }', objects: {'java': host}), 'host exploded');
      expect(() => js('java.boom()', objects: {'java': host}), throwsA(isA<JsException>()));
      expect(() => js('java.nope()', objects: {'java': host}), throwsA(isA<JsException>()));
    });

    test('this exposes the bindings (destructuring as the original runtime supports)', () {
      final host = _Host();
      expect(js('const {java, result} = this; java.echo(result)', values: {'result': 'r'}, objects: {'java': host}), 'r');
    });

    test('JsScriptRunner replays scripts for asynchronous natives', () async {
      final rt = DartJsRuntime();
      var loads = 0;
      final async = _AsyncHost(() => loads++);
      final r = await JsScriptRunner.run('var a = java.fetch("x"); var b = java.fetch("y"); a + b', JsBindings(objects: {'java': async}), runtimeOverride: rt);
      expect(r, 'X!Y!');
      expect(loads, 2);
    });
  });
}

class _AsyncHost extends JsBindable {
  final void Function() onLoad;
  _AsyncHost(this.onLoad);

  @override
  Iterable<String> get jsMethods => const ['fetch'];

  @override
  Object? jsCall(String name, List<Object?> args) {
    if (name == 'fetch') {
      final u = '${args[0]}';
      return jsAwait('fetch:$u', () async {
        onLoad();
        return '${u.toUpperCase()}!';
      });
    }
    return super.jsCall(name, args);
  }
}
