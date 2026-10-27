// util/legado/js_engines.dart - picks the JavaScript runtime used by [JsScriptRunner]. The app calls `JsEngines.install()` once at start
// (init); on iOS/Android that is the flutter_js runtime (JavaScriptCore/QuickJS), everywhere else (desktop, tests) the pure Dart one.
import 'dart:io' show Platform;

import 'flutter_js_runtime.dart';
import 'js_runtime.dart';
import 'script_engine.dart';

abstract class JsEngines {
  /// Installs [JsScriptRunner.runtime] if none is set. [preferNative] false forces the pure Dart interpreter (e.g. if the native one
  /// misbehaves on a device); the choice can be made persistent by the caller.
  static void install({bool preferNative = true}) {
    if (JsScriptRunner.runtime != null) return;
    var native = false;
    try {
      native = preferNative && (Platform.isIOS || Platform.isAndroid);
    } catch (_) {
      native = false;
    }
    JsScriptRunner.runtime = native ? FlutterJsRuntime() : DartJsRuntime();
  }

  /// Replaces the runtime (tests install a [DartJsRuntime] or a `FakeJsRuntime`).
  static void use(JsRuntime rt) {
    JsScriptRunner.runtime?.dispose();
    JsScriptRunner.runtime = rt;
  }

  static void useDart() => use(DartJsRuntime());
}
