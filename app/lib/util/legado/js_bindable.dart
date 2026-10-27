// util/legado/js_bindable.dart - what a Dart object must offer to be visible from rule JavaScript as `java`, `cache`, `source`,
// `cookie`, `book`, `chapter` (the original's `JsBindable` base class, function names `java.*` / `cache.*` ... in rule_engine.txt).
//
// Native functions are synchronous from JavaScript's point of view. Network and other asynchronous natives are bridged by
// *replay*: the native throws [JsPendingException] with a key and a loader; the runner awaits the loader, stores the result in
// the evaluation context and runs the script again, where the same call now answers from the stored result (see JsScriptRunner).

class _NoMember {
  const _NoMember();
  @override
  String toString() => '<no member>';
}

class JsNoSuchMethod implements Exception {
  final String name;
  JsNoSuchMethod(this.name);
  @override
  String toString() => 'TypeError: $name is not a function';
}

/// An error raised by a native function; surfaces in JavaScript as an exception (catchable with try/catch).
class JsHostError implements Exception {
  final String message;
  JsHostError(this.message);
  @override
  String toString() => message;
}

/// Thrown by a native that needs the result of an asynchronous operation (see file comment).
class JsPendingException implements Exception {
  final String key;
  final Future<Object?> Function() loader;
  JsPendingException(this.key, this.loader);
  @override
  String toString() => 'JsPendingException($key)';
}

abstract class JsBindable {
  /// Returned by [jsGet] for names that are not data properties.
  static const Object noMember = _NoMember();

  /// Names callable as `obj.name(...)`.
  Iterable<String> get jsMethods => const [];

  /// `obj.name` as a data property; [noMember] when [name] is not a property (it may still be a method).
  Object? jsGet(String name) => noMember;

  void jsSet(String name, Object? value) {}

  /// `obj.name(...args)`. Arguments and results are JSON-like values (null, bool, num, String, List, Map) or [JsBindable].
  Object? jsCall(String name, List<Object?> args) => throw JsNoSuchMethod(name);

  /// Data properties for engines that cannot call back synchronously for property reads (JavaScriptCore via flutter_js).
  Map<String, Object?> jsSnapshot() => const {};
}

/// Per-evaluation state shared between the runner and the natives (results of asynchronous natives, collected log lines).
class JsEvalContext {
  static JsEvalContext? current;

  final Map<String, Object?> results = {};
  final Map<String, String> errors = {};
  final List<String> logs = [];
}

/// Helper for natives: returns the stored result of the asynchronous operation [key] or throws [JsPendingException].
Object? jsAwait(String key, Future<Object?> Function() loader) {
  final ctx = JsEvalContext.current;
  if (ctx == null) throw StateError('asynchronous JS native "$key" called outside of a JsScriptRunner evaluation');
  if (ctx.errors.containsKey(key)) throw JsHostError(ctx.errors[key]!);
  if (ctx.results.containsKey(key)) return ctx.results[key];
  throw JsPendingException(key, loader);
}
