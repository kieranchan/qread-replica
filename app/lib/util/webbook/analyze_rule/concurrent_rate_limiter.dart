// util/webbook/analyze_rule/concurrent_rate_limiter.dart - the source's `concurrentRate`: `"1000"` = at least 1000 ms between two
// requests, `"3/1000"` = at most 3 requests per 1000 ms. State is kept per source key.
import 'dart:async';

class _Record {
  int windowStart = 0;
  int count = 0;
  int lastStart = 0;
}

class ConcurrentRateLimiter {
  static final Map<String, _Record> _records = {};
  static final Map<String, Future<void>> _chains = {};

  final String sourceKey;
  final String? rate;

  ConcurrentRateLimiter(this.sourceKey, this.rate);

  /// Waits until a request may start (returns immediately when no rate is configured).
  Future<void> acquire() {
    final r = rate?.trim();
    if (r == null || r.isEmpty || r == '0') return Future.value();
    // serialise waiters per source so that the bookkeeping below sees them one after the other
    final prev = _chains[sourceKey] ?? Future.value();
    final next = prev.then((_) => _wait(r));
    _chains[sourceKey] = next.catchError((_) {});
    return next;
  }

  Future<void> _wait(String r) async {
    final slash = r.indexOf('/');
    final rec = _records.putIfAbsent(sourceKey, _Record.new);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (slash > 0) {
      final maxCount = int.tryParse(r.substring(0, slash).trim()) ?? 1;
      final window = int.tryParse(r.substring(slash + 1).trim()) ?? 1000;
      if (now - rec.windowStart >= window) {
        rec.windowStart = now;
        rec.count = 1;
        return;
      }
      if (rec.count < maxCount) {
        rec.count++;
        return;
      }
      final wait = rec.windowStart + window - now;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      rec.windowStart = DateTime.now().millisecondsSinceEpoch;
      rec.count = 1;
    } else {
      final interval = int.tryParse(r) ?? 0;
      final next = rec.lastStart + interval;
      if (now < next) await Future<void>.delayed(Duration(milliseconds: next - now));
      rec.lastStart = DateTime.now().millisecondsSinceEpoch;
    }
  }

  static void resetForTests() {
    _records.clear();
    _chains.clear();
  }
}
