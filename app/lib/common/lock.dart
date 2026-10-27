// common/lock.dart — a minimal mutex with the shape of `package:synchronized`'s `Lock` that the original uses
// (`static final Lock _lock` in every data manager; `await _lock.synchronized(() async { ... })`).
//
// The replica keeps its own 20-line version so no new dependency is needed. Calls run strictly one after another in the
// order they were requested; an exception inside a body is delivered to that caller only and does not block later calls.
import 'dart:async';

class Lock {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// Runs [body] once every earlier call has finished.
  ///
  /// An idle lock runs [body] at once instead of chaining onto the last (already completed) future: listeners of a completed
  /// future are scheduled in the zone that created it, and when that zone is gone (a finished widget test's fake-async zone)
  /// the chained call would never run.
  Future<T> synchronized<T>(FutureOr<T> Function() body) {
    final done = Completer<void>();
    final previous = _pending == 0 ? null : _tail;
    _pending++;
    _tail = done.future;
    Future<T> run() async {
      try {
        return await body();
      } finally {
        _pending--;
        done.complete();
      }
    }

    return previous == null ? run() : previous.then((_) => run());
  }
}
