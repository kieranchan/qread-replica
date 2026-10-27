// util/json.dart - JSON helpers (`jsonutil` in the original: encode / decode / decode from bytes) plus tolerant readers used by the
// engine's model classes (book-source JSON in the wild stores numbers and booleans as strings).
// ignore_for_file: camel_case_types
import 'dart:convert';
import 'dart:typed_data';

abstract class jsonutil {
  static String encode(Object? v) => jsonEncode(v, toEncodable: (o) => o is DateTime ? o.toIso8601String() : o.toString());

  static dynamic decode(String s) => jsonDecode(s);

  /// Decodes UTF-8 JSON bytes (BOM tolerant).
  static dynamic decodeBytes(Uint8List bytes) {
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) b = Uint8List.sublistView(b, 3);
    return jsonDecode(utf8.decode(b));
  }

  /// null when [s] is not valid JSON.
  static dynamic tryDecode(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// Lenient decode like Gson's `fromJson` in lenient mode: single-quoted strings, unquoted keys, trailing commas, comments, `=`/`:`
  /// as key separators are accepted. Returns null on failure.
  static dynamic tryDecodeLenient(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      // fall through to the lenient parser
    }
    try {
      final p = _LenientParser(s);
      final v = p.parseValue();
      p.skipWs();
      return v;
    } catch (_) {
      return null;
    }
  }

  /// `isJson()` of Legado: `{...}` or `[...]` after trimming.
  static bool isJson(String s) {
    final t = s.trim();
    return (t.startsWith('{') && t.endsWith('}')) || (t.startsWith('[') && t.endsWith(']'));
  }

  static bool isJsonObject(String s) {
    final t = s.trim();
    return t.startsWith('{') && t.endsWith('}');
  }

  static bool isJsonArray(String s) {
    final t = s.trim();
    return t.startsWith('[') && t.endsWith(']');
  }

  // tolerant readers -------------------------------------------------------------------------------------------------------
  static String? optString(Object? v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is Map || v is List) return jsonEncode(v);
    return v.toString();
  }

  static String asString(Object? v, [String def = '']) => optString(v) ?? def;

  static int asInt(Object? v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt() ?? def;
    return def;
  }

  static double asDouble(Object? v, [double def = 0]) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? def;
    return def;
  }

  static bool asBool(Object? v, [bool def = false]) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final t = v.trim().toLowerCase();
      if (t == 'true' || t == '1') return true;
      if (t == 'false' || t == '0' || t.isEmpty) return false;
    }
    return def;
  }

  /// A JSON object that may itself be stored as a JSON string.
  static Map<String, dynamic>? asMap(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.trim().startsWith('{')) {
      final d = tryDecodeLenient(v);
      if (d is Map) return Map<String, dynamic>.from(d);
    }
    return null;
  }

  static List<dynamic>? asList(Object? v) {
    if (v is List) return List<dynamic>.from(v);
    if (v is String && v.trim().startsWith('[')) {
      final d = tryDecode(v);
      if (d is List) return List<dynamic>.from(d);
    }
    return null;
  }
}

class _LenientParser {
  final String s;
  int i = 0;
  _LenientParser(this.s);

  static const String _delims = ',}]:= \n\r\t';

  void skipWs() {
    while (i < s.length) {
      final c = s[i];
      if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
        i++;
      } else if (s.startsWith('//', i)) {
        while (i < s.length && s[i] != '\n') {
          i++;
        }
      } else if (s.startsWith('/*', i)) {
        final e = s.indexOf('*/', i + 2);
        i = e < 0 ? s.length : e + 2;
      } else {
        break;
      }
    }
  }

  Object? parseValue() {
    skipWs();
    if (i >= s.length) throw const FormatException('unexpected end');
    final c = s[i];
    if (c == '{') return _object();
    if (c == '[') return _array();
    if (c == '"' || c == "'") return _string(c);
    final start = i;
    while (i < s.length && !_delims.contains(s[i])) {
      i++;
    }
    final w = s.substring(start, i);
    if (w == 'true') return true;
    if (w == 'false') return false;
    if (w == 'null') return null;
    return num.tryParse(w) ?? w;
  }

  Map<String, Object?> _object() {
    i++;
    final m = <String, Object?>{};
    while (true) {
      skipWs();
      if (i >= s.length) throw const FormatException('unterminated object');
      if (s[i] == '}') {
        i++;
        return m;
      }
      if (s[i] == ',' || s[i] == ';') {
        i++;
        continue;
      }
      final k = (s[i] == '"' || s[i] == "'") ? _string(s[i]) : _bareKey();
      skipWs();
      if (i < s.length && (s[i] == ':' || s[i] == '=')) {
        i++;
        if (i < s.length && s[i] == '>') i++;
      }
      m[k] = parseValue();
    }
  }

  String _bareKey() {
    final start = i;
    while (i < s.length && !':= \n\r\t,}'.contains(s[i])) {
      i++;
    }
    return s.substring(start, i);
  }

  List<Object?> _array() {
    i++;
    final l = <Object?>[];
    while (true) {
      skipWs();
      if (i >= s.length) throw const FormatException('unterminated array');
      if (s[i] == ']') {
        i++;
        return l;
      }
      if (s[i] == ',' || s[i] == ';') {
        i++;
        continue;
      }
      l.add(parseValue());
    }
  }

  String _string(String q) {
    i++;
    final sb = StringBuffer();
    while (i < s.length && s[i] != q) {
      if (s[i] == '\\' && i + 1 < s.length) {
        i++;
        switch (s[i]) {
          case 'n':
            sb.write('\n');
            break;
          case 't':
            sb.write('\t');
            break;
          case 'r':
            sb.write('\r');
            break;
          case 'b':
            sb.write('\b');
            break;
          case 'f':
            sb.write('\f');
            break;
          case 'u':
            if (i + 4 < s.length) {
              sb.writeCharCode(int.parse(s.substring(i + 1, i + 5), radix: 16));
              i += 4;
            }
            break;
          default:
            sb.write(s[i]);
        }
      } else {
        sb.write(s[i]);
      }
      i++;
    }
    if (i >= s.length) throw const FormatException('unterminated string');
    i++;
    return sb.toString();
  }
}
