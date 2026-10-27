// util/legado/js_bindable_compat.dart - small value helpers shared by the JS natives: conversion of JS values to Dart strings the way
// Rhino's `toString()` does (integral doubles print without ".0"), list/map coercion and date formatting.
import 'dart:convert';

String jsToString(Object? v) {
  if (v == null) return 'null';
  if (v is String) return v;
  if (v is double) {
    if (v.isNaN) return 'NaN';
    if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
    if (v == v.truncateToDouble() && v.abs() < 1e21) return v.toInt().toString();
    return v.toString();
  }
  if (v is num || v is bool) return v.toString();
  if (v is List) return v.map((e) => e == null ? '' : jsToString(e)).join(',');
  if (v is Map) return '[object Object]';
  return v.toString();
}

/// Rhino/Kotlin `"$value"` for values placed into rule strings (`{{ }}` results): null prints as "null".
String jsToRuleString(Object? v) {
  if (v == null) return 'null';
  if (v is String) return v;
  if (v is double && v == v.truncateToDouble() && v.abs() < 1e15) return v.toInt().toString();
  if (v is List || v is Map) return jsonEncode(v);
  return v.toString();
}

List<int> jsToBytes(Object? v, [List<int> Function(String)? encode]) {
  if (v is List) return v.map((e) => (e as num).toInt() & 0xff).toList();
  final s = v?.toString() ?? '';
  return encode != null ? encode(s) : utf8.encode(s);
}

/// Formats [t] with a `SimpleDateFormat`-style [pattern] (`yyyy MM dd HH mm ss SSS`, other characters literal).
String formatDate(DateTime t, String pattern) {
  String p(int v, int w) => v.toString().padLeft(w, '0');
  final sb = StringBuffer();
  var i = 0;
  while (i < pattern.length) {
    final c = pattern[i];
    var j = i;
    while (j < pattern.length && pattern[j] == c) {
      j++;
    }
    final n = j - i;
    switch (c) {
      case 'y':
        sb.write(n == 2 ? p(t.year % 100, 2) : p(t.year, n));
        break;
      case 'M':
        sb.write(p(t.month, n));
        break;
      case 'd':
        sb.write(p(t.day, n));
        break;
      case 'H':
        sb.write(p(t.hour, n));
        break;
      case 'h':
        sb.write(p(t.hour % 12 == 0 ? 12 : t.hour % 12, n));
        break;
      case 'm':
        sb.write(p(t.minute, n));
        break;
      case 's':
        sb.write(p(t.second, n));
        break;
      case 'S':
        sb.write(p(t.millisecond, n));
        break;
      default:
        sb.write(pattern.substring(i, j));
    }
    i = j;
  }
  return sb.toString();
}
