// util/webbook/debug.dart - step log of a source run (the source debugger page shows it). `DebugLog` collects lines; the flows write the
// same stage markers Legado uses (`┌`/`└`/`◇`/`≡`/`⇒`).
class DebugLog {
  final List<String> lines = [];
  final void Function(String line)? onLine;

  DebugLog({this.onLine});

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
