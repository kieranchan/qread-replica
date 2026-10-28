// util/webbook/debug.dart - step log of a source run (the source debugger page shows it). `DebugLog` collects lines; the flows write the
// same stage markers Legado uses (`┌`/`└`/`◇`/`≡`/`⇒`).
class DebugLog {
  final List<String> lines = [];
  final void Function(String line)? onLine;

  /// The response body of each step of the run (`search` / `explore` / `book` / `toc` / `content`; the first page of a step), kept
  /// like the original debugger does (0xfc20b0) so the source views show what the run itself received (POST bodies included).
  final Map<String, String> bodies = {};
  final void Function(String step, String body)? onBody;

  DebugLog({this.onLine, this.onBody});

  void body(String step, String? text) {
    if (text == null || bodies.containsKey(step)) return;
    bodies[step] = text;
    onBody?.call(step, text);
  }

  void log(String message) {
    final t = '${DateTime.now().toIso8601String().substring(11, 23)} $message';
    lines.add(t);
    onLine?.call(t);
  }

  void clear() => lines.clear();

  @override
  String toString() => lines.join('\n');
}

/// A failure inside a source flow with a message meant for the user (`NoStackTraceException` in Legado).
class WebBookException implements Exception {
  final String message;
  WebBookException(this.message);
  @override
  String toString() => message;
}
