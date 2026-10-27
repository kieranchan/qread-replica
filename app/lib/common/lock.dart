// common/lock.dart — a minimal mutex with the shape of `package:synchronized`'s `Lock` that the original uses
// (`static final Lock _lock` in every data manager; `await _lock.synchronized(() async { ... })`).
//
// The replica keeps its own 20-line version so no new dependency is needed. Calls run strictly one after another in the
// order they were requested; an exception inside a body is delivered to that caller only and does not block later calls.
import 'dart:async';

class Lock {
  Future<void> _tail = Future<void>.value();

  /// Runs [body] once every earlier call has finished.
  Future<T> synchronized<T>(FutureOr<T> Function() body) {
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    return previous.then((_) async {
      try {
        return await body();
      } finally {
        done.complete();
      }
    });
  }
}
