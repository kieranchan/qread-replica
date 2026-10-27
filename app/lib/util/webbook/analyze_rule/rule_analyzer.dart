// util/webbook/analyze_rule/rule_analyzer.dart - Legado `RuleAnalyzer`: splits a rule on `&&` / `||` / `%%` / `@` without breaking
// bracket groups, and replaces inline sub-rules (`{$.x}`, `{{js}}`).
//
// Behaviour follows Legado's implementation (balanced `[]`/`()` groups, quotes, `\` escapes); the original app's class has the same
// members (`trim` is the only one that survived as a named function in the AOT snapshot, 0xe2fd90).

class RuleAnalyzer {
  final String queue;
  int pos = 0;
  int start = 0;
  int startX = 0;
  List<String> rule = [];
  int step = 0;
  String elementsType = '';
  final bool code;

  RuleAnalyzer(this.queue, [this.code = false]);

  /// Skips `@` and whitespace in front of the current rule.
  void trim() {
    if (pos >= queue.length) return;
    if (queue.codeUnitAt(pos) == 0x40 || queue.codeUnitAt(pos) < 0x21) {
      pos++;
      while (pos < queue.length && (queue.codeUnitAt(pos) == 0x40 || queue.codeUnitAt(pos) < 0x21)) {
        pos++;
      }
      start = pos;
      startX = pos;
    }
  }

  void reSetPos() {
    pos = 0;
    startX = 0;
  }

  bool _consumeTo(String seq) {
    start = pos;
    final offset = queue.indexOf(seq, pos);
    if (offset != -1) {
      pos = offset;
      return true;
    }
    return false;
  }

  bool _consumeToAny(List<String> seqs) {
    var p = pos;
    while (p != queue.length) {
      for (final s in seqs) {
        if (queue.startsWith(s, p)) {
          step = s.length;
          pos = p;
          return true;
        }
      }
      p++;
    }
    return false;
  }

  int _findToAny(List<String> chars) {
    var p = pos;
    while (p != queue.length) {
      for (final c in chars) {
        if (queue[p] == c) return p;
      }
      p++;
    }
    return -1;
  }

  bool _chompBalanced(String open, String close) => code ? _chompCodeBalanced(open, close) : _chompRuleBalanced(open, close);

  bool _chompCodeBalanced(String open, String close) {
    var p = pos;
    var depth = 0;
    var otherDepth = 0;
    var inSingle = false;
    var inDouble = false;
    do {
      if (p == queue.length) break;
      final c = queue[p++];
      if (c != r'\') {
        if (c == "'" && !inDouble) {
          inSingle = !inSingle;
        } else if (c == '"' && !inSingle) {
          inDouble = !inDouble;
        }
        if (inSingle || inDouble) continue;
        if (c == '[') {
          depth++;
        } else if (c == ']') {
          depth--;
        } else if (depth == 0) {
          if (c == open) {
            otherDepth++;
          } else if (c == close) {
            otherDepth--;
          }
        }
      } else {
        p++;
      }
    } while (depth > 0 || otherDepth > 0);
    if (depth > 0 || otherDepth > 0) return false;
    pos = p;
    return true;
  }

  bool _chompRuleBalanced(String open, String close) {
    var p = pos;
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    do {
      if (p == queue.length) break;
      final c = queue[p++];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      }
      if (inSingle || inDouble) {
        continue;
      } else if (c == r'\') {
        p++;
        continue;
      }
      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
      }
    } while (depth > 0);
    if (depth > 0) return false;
    pos = p;
    return true;
  }

  /// Splits the rule on one of [split] (e.g. `['&&', '||', '%%']`); [elementsType] receives the separator that was found.
  List<String> splitRule(List<String> split) {
    while (true) {
      if (split.length == 1) {
        elementsType = split[0];
        if (!_consumeTo(elementsType)) {
          rule.add(queue.substring(startX));
          return rule;
        }
        step = elementsType.length;
        return _splitRuleNext();
      } else if (!_consumeToAny(split)) {
        rule.add(queue.substring(startX));
        return rule;
      }
      final end = pos;
      pos = start;
      do {
        final st = _findToAny(['[', '(']);
        if (st == -1) {
          rule = [queue.substring(startX, end)];
          elementsType = queue.substring(end, end + step);
          pos = end + step;
          while (_consumeTo(elementsType)) {
            rule.add(queue.substring(start, pos));
            pos += step;
          }
          rule.add(queue.substring(pos));
          return rule;
        }
        if (st > end) {
          rule = [queue.substring(startX, end)];
          elementsType = queue.substring(end, end + step);
          pos = end + step;
          while (_consumeTo(elementsType) && pos < st) {
            rule.add(queue.substring(start, pos));
            pos += step;
          }
          if (pos > st) {
            startX = start;
            return _splitRuleNext();
          }
          rule.add(queue.substring(pos));
          return rule;
        }
        pos = st;
        final next = queue[pos] == '[' ? ']' : ')';
        if (!_chompBalanced(queue[pos], next)) {
          throw FormatException('${queue.substring(0, start)}后未平衡');
        }
      } while (end > pos);
      start = pos;
    }
  }

  List<String> _splitRuleNext() {
    while (true) {
      final end = pos;
      pos = start;
      var again = false;
      do {
        final st = _findToAny(['[', '(']);
        if (st == -1) {
          rule.add(queue.substring(startX, end));
          pos = end + step;
          while (_consumeTo(elementsType)) {
            rule.add(queue.substring(start, pos));
            pos += step;
          }
          rule.add(queue.substring(pos));
          return rule;
        }
        if (st > end) {
          rule.add(queue.substring(startX, end));
          pos = end + step;
          while (_consumeTo(elementsType) && pos < st) {
            rule.add(queue.substring(start, pos));
            pos += step;
          }
          if (pos > st) {
            startX = start;
            again = true;
            break;
          }
          rule.add(queue.substring(pos));
          return rule;
        }
        pos = st;
        final next = queue[pos] == '[' ? ']' : ')';
        if (!_chompBalanced(queue[pos], next)) {
          throw FormatException('${queue.substring(0, start)}后未平衡');
        }
      } while (end > pos);
      if (again) continue;
      start = pos;
    }
  }

  /// Replaces inline rules introduced by [inner] (e.g. `{$.`) which are closed by the balancing `}`; [fr] maps the body (without the
  /// outermost `{`/`}`) to its replacement. Returns "" when nothing was replaced (Legado returns "" in that case).
  String innerRule(String inner, String? Function(String) fr, {int startStep = 1, int endStep = 1}) {
    final st = StringBuffer();
    while (_consumeTo(inner)) {
      final posPre = pos;
      if (_chompCodeBalanced('{', '}')) {
        final frv = fr(queue.substring(posPre + startStep, pos - endStep));
        if (frv != null && frv.isNotEmpty) {
          st.write(queue.substring(startX, posPre) + frv);
          startX = pos;
          continue;
        }
      }
      pos += inner.length;
    }
    if (startX == 0) return '';
    st.write(queue.substring(startX));
    return st.toString();
  }

  /// `innerRule(startStr, endStr)` variant (used for `{{ }}` templates), asynchronous because evaluating the body may run JS.
  Future<String> innerRuleAsync(String startStr, String endStr, Future<String?> Function(String) fr) async {
    final st = StringBuffer();
    while (_consumeTo(startStr)) {
      pos += startStr.length;
      final posPre = pos;
      if (_consumeTo(endStr)) {
        final frv = await fr(queue.substring(posPre, pos));
        st.write(queue.substring(startX, posPre - startStr.length) + (frv ?? 'null'));
        pos += endStr.length;
        startX = pos;
      }
    }
    if (startX == 0) return queue;
    st.write(queue.substring(startX));
    return st.toString();
  }
}
