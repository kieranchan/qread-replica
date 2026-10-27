// util/webbook/analyze_rule/info_map.dart - `InfoMap`: the login-info map of a source (what `source.getLoginInfoMap()` returns and the
// login form `loginUi` fills); a thin Map<String,String> wrapper with JSON (de)serialisation.
import 'dart:convert';

class InfoMap {
  final Map<String, String> map;

  InfoMap([Map<String, String>? m]) : map = m ?? {};

  factory InfoMap.fromJsonString(String? json) {
    final r = InfoMap();
    if (json == null || json.trim().isEmpty) return r;
    try {
      final d = jsonDecode(json);
      if (d is Map) {
        d.forEach((k, v) => r.map['$k'] = '$v');
      }
    } catch (_) {
      // not a JSON object: no entries
    }
    return r;
  }

  String? operator [](String key) => map[key];
  void operator []=(String key, String value) => map[key] = value;
  bool get isEmpty => map.isEmpty;
  String toJsonString() => jsonEncode(map);
}
