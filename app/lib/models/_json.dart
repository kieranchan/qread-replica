// Tolerant JSON readers used by the model classes (the original stores numbers/booleans as strings in places).
String jStr(Object? v, [String def = '']) => v == null ? def : v.toString();

int jInt(Object? v, [int def = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is bool) return v ? 1 : 0;
  return int.tryParse('${v ?? ''}') ?? double.tryParse('${v ?? ''}')?.toInt() ?? def;
}

double jDouble(Object? v, [double def = 0.0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? def;
}

bool jBool(Object? v, [bool def = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return def;
}

List<dynamic> jList(Object? v) => v is List ? List<dynamic>.from(v) : <dynamic>[];

Map<String, dynamic> jMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
