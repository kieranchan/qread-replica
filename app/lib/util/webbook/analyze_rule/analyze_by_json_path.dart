// util/webbook/analyze_rule/analyze_by_json_path.dart - `$.a.b[*]` / `@json:` rules. Also holds `AnalyzeByRegex` (the `:` all-in-one
// regex mode of Legado's rule engine), which has no file of its own in the original snapshot's file list.
import 'dart:convert';

import '../../legado/java_regex.dart';
import '../../legado/json_path.dart';
import 'rule_analyzer.dart';

class AnalyzeByJSonPath {
  final Object? _json;

  AnalyzeByJSonPath(Object json) : _json = JsonPath.parseJson(json);

  Object? _read(String rule) => JsonPath.compile(rule).read(_json);

  String? getString(String rule) {
    if (rule.isEmpty) return null;
    String result;
    final ruleAnalyzes = RuleAnalyzer(rule, true);
    final rules = ruleAnalyzes.splitRule(['&&', '||']);
    if (rules.length == 1) {
      ruleAnalyzes.reSetPos();
      result = ruleAnalyzes.innerRule(r'{$.', (it) => getString(it));
      if (result.isEmpty) {
        try {
          final ob = _read(rule);
          if (ob is List) {
            result = ob.map(_str).join('\n');
          } else {
            result = _str(ob);
          }
        } on JsonPathException {
          // like Legado: an invalid/absent path yields an empty result
        }
      }
      return result;
    } else {
      final textList = <String>[];
      for (final rl in rules) {
        final temp = getString(rl);
        if (temp != null && temp.isNotEmpty) {
          textList.add(temp);
          if (ruleAnalyzes.elementsType == '||') break;
        }
      }
      return textList.join('\n');
    }
  }

  List<String> getStringList(String rule) {
    final result = <String>[];
    if (rule.isEmpty) return result;
    final ruleAnalyzes = RuleAnalyzer(rule, true);
    final rules = ruleAnalyzes.splitRule(['&&', '||', '%%']);
    if (rules.length == 1) {
      ruleAnalyzes.reSetPos();
      final st = ruleAnalyzes.innerRule(r'{$.', (it) => getString(it));
      if (st.isEmpty) {
        try {
          final obj = _read(rule);
          if (obj is List) {
            for (final o in obj) {
              result.add(_str(o));
            }
          } else {
            result.add(_str(obj));
          }
        } on JsonPathException {
          // ignore
        }
      } else {
        result.add(st);
      }
      return result;
    } else {
      final results = <List<String>>[];
      for (final rl in rules) {
        final temp = getStringList(rl);
        if (temp.isNotEmpty) {
          results.add(temp);
          if (ruleAnalyzes.elementsType == '||') break;
        }
      }
      if (results.isNotEmpty) {
        if (ruleAnalyzes.elementsType == '%%') {
          for (var i = 0; i < results[0].length; i++) {
            for (final t in results) {
              if (i < t.length) result.add(t[i]);
            }
          }
        } else {
          for (final t in results) {
            result.addAll(t);
          }
        }
      }
      return result;
    }
  }

  /// `getObject`: the raw value at [rule] (throws [JsonPathException] when absent).
  Object? getObject(String rule) => _read(rule);

  /// `getList`: the matches of [rule] as list of elements (maps for objects).
  List<Object?>? getList(String rule) {
    final result = <Object?>[];
    if (rule.isEmpty) return result;
    final ruleAnalyzes = RuleAnalyzer(rule, true);
    final rules = ruleAnalyzes.splitRule(['&&', '||', '%%']);
    if (rules.length == 1) {
      try {
        final v = _read(rules[0]);
        if (v is List) return List<Object?>.from(v);
        return [v];
      } on JsonPathException {
        return null;
      }
    } else {
      final results = <List<Object?>>[];
      for (final rl in rules) {
        final temp = getList(rl);
        if (temp != null && temp.isNotEmpty) {
          results.add(temp);
          if (ruleAnalyzes.elementsType == '||') break;
        }
      }
      if (results.isNotEmpty) {
        if (ruleAnalyzes.elementsType == '%%') {
          for (var i = 0; i < results[0].length; i++) {
            for (final t in results) {
              if (i < t.length) result.add(t[i]);
            }
          }
        } else {
          for (final t in results) {
            result.addAll(t);
          }
        }
      }
    }
    return result;
  }

  /// Java/Rhino `toString` of a JSON value (`null` prints as "null", maps/lists as JSON text like Gson).
  static String _str(Object? o) {
    if (o == null) return 'null';
    if (o is String) return o;
    if (o is num) return o is double && o == o.truncateToDouble() && o.abs() < 1e15 ? o.toInt().toString() : o.toString();
    if (o is bool) return o.toString();
    return jsonEncode(o);
  }
}

/// `:` all-in-one regex rules: `rule.split("&&")` are applied one after the other, each narrowing the text; the last one's capture
/// groups are the result (index 0 = whole match).
class AnalyzeByRegex {
  static List<String>? getElement(String res, List<String> regs, [int index = 0]) {
    final re = JavaRegex.compile(regs[index]);
    final m = re.firstMatch(res);
    if (m == null) return null;
    if (index + 1 == regs.length) {
      final info = <String>[];
      for (var g = 0; g <= m.groupCount; g++) {
        info.add(m.group(g) ?? 'null');
      }
      return info;
    }
    final result = StringBuffer();
    for (final mm in re.allMatches(res)) {
      result.write(mm.group(0));
    }
    return getElement(result.toString(), regs, index + 1);
  }

  static List<List<String>> getElements(String res, List<String> regs, [int index = 0]) {
    final re = JavaRegex.compile(regs[index]);
    final all = re.allMatches(res).toList();
    if (all.isEmpty) return [];
    if (index + 1 == regs.length) {
      final books = <List<String>>[];
      for (final m in all) {
        final info = <String>[];
        for (var g = 0; g <= m.groupCount; g++) {
          info.add(m.group(g) ?? '');
        }
        books.add(info);
      }
      return books;
    }
    final result = StringBuffer();
    for (final mm in all) {
      result.write(mm.group(0));
    }
    return getElements(result.toString(), regs, index + 1);
  }
}
