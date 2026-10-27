// util/webbook/analyze_rule/rule_data.dart - the variable store behind `@put:{k:rule}` / `@get:{k}` and `book.putVariable()`.
import 'dart:convert';

abstract class RuleDataInterface {
  Map<String, String> get variableMap;
  bool putVariable(String key, String? value);
  String? getVariable(String key);
}

/// Plain variable holder (search/explore requests that have no book yet).
class RuleData implements RuleDataInterface {
  @override
  final Map<String, String> variableMap = {};

  /// Longest accepted value (Legado refuses larger ones to keep the book row small).
  static const int maxValueLength = 10000;

  @override
  bool putVariable(String key, String? value) {
    if (value == null) {
      variableMap.remove(key);
      return true;
    }
    if (value.length > maxValueLength) return false;
    variableMap[key] = value;
    return true;
  }

  @override
  String? getVariable(String key) => variableMap[key];

  /// JSON of the variable map as persisted in `Book.variable` (null when empty).
  String? get variableJson => variableMap.isEmpty ? null : jsonEncode(variableMap);

  void loadVariableJson(String? json) {
    variableMap.clear();
    if (json == null || json.isEmpty) return;
    try {
      final d = jsonDecode(json);
      if (d is Map) {
        d.forEach((k, v) => variableMap['$k'] = '$v');
      }
    } catch (_) {
      // ignore malformed
    }
  }
}
