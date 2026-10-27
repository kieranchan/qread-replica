// util/legado/js_runtime.dart - the JS runtime seam. `JsRuntime` evaluates one script synchronously; `JsScriptRunner` adds the
// replay loop for asynchronous natives and the `jsLib` prefix. Implementations: DartJsRuntime (util/legado/script_engine.dart, pure
// Dart, used in tests and as fallback), FlutterJsRuntime (util/legado/flutter_js_runtime.dart, JavaScriptCore/QuickJS via flutter_js),
// FakeJsRuntime (below, scripted answers for unit tests).
import 'dart:async';

import 'js_bindable.dart';

class JsException implements Exception {
  final String message;
  JsException(this.message);
  @override
  String toString() => 'JsException: $message';
}

/// Everything a script can see: plain values (`result`, `baseUrl`, `key`, `page`, `src` ...) and native objects.
class JsBindings {
  final Map<String, Object?> values;
  final Map<String, JsBindable> objects;
  JsBindings({Map<String, Object?>? values, Map<String, JsBindable>? objects})
      : values = values ?? {},
        objects = objects ?? {};
}

abstract class JsRuntime {
  /// Evaluates [script] and returns its completion value converted to a JSON-like Dart value (`undefined` becomes null).
  /// Must propagate [JsPendingException] thrown by natives and throw [JsException] for script errors.
  Object? evaluateSync(String script, JsBindings bindings);

  void dispose() {}
}

/// Scripted runtime for unit tests: answers [handler] (or a map keyed by exact script text) instead of running JavaScript.
class FakeJsRuntime extends JsRuntime {
  final Map<String, Object? Function(JsBindings)> scripts;
  final Object? Function(String script, JsBindings bindings)? fallback;
  final List<String> evaluated = [];

  FakeJsRuntime({Map<String, Object? Function(JsBindings)>? scripts, this.fallback}) : scripts = scripts ?? {};

  @override
  Object? evaluateSync(String script, JsBindings bindings) {
    evaluated.add(script);
    final h = scripts[script.trim()];
    if (h != null) return h(bindings);
    if (fallback != null) return fallback!(script, bindings);
    throw JsException('FakeJsRuntime: no answer for script: $script');
  }
}

typedef JsLogSink = void Function(String line);

class JsScriptRunner {
  /// The runtime used by every rule evaluation. Set at start-up (`FlutterJsRuntime` on devices); defaults to the pure Dart one when
  /// [factory] is installed by `ScriptEngineRegistry`.
  static JsRuntime? runtime;

  /// Where `java.log` / `console.log` output goes (the original forwards it to `Debug.log`).
  static JsLogSink? logSink;

  static const int maxRounds = 60;

  /// Evaluates [script] (preceded by [jsLib]) and returns the JSON-like completion value. Asynchronous natives are resolved by replaying
  /// the script after each awaited result.
  static Future<Object?> run(String script, JsBindings bindings, {String? jsLib, JsRuntime? runtimeOverride}) async {
    final rt = runtimeOverride ?? runtime;
    if (rt == null) throw JsException('no JS runtime installed (JsScriptRunner.runtime)');
    final code = (jsLib == null || jsLib.trim().isEmpty) ? script : '$jsLib\n;\n$script';
    final ctx = JsEvalContext();
    for (var round = 0; round < maxRounds; round++) {
      ctx.logs.clear();
      JsEvalContext.current = ctx;
      try {
        final r = rt.evaluateSync(code, bindings);
        final sink = logSink;
        if (sink != null) {
          for (final l in ctx.logs) {
            sink(l);
          }
        }
        return r;
      } on JsPendingException catch (p) {
        JsEvalContext.current = null;
        try {
          ctx.results[p.key] = await p.loader();
        } catch (e) {
          ctx.errors[p.key] = e.toString();
        }
      } finally {
        JsEvalContext.current = null;
      }
    }
    throw JsException('script needs too many asynchronous results (> $maxRounds)');
  }
}
