// util/legado/set_cookie_parser.dart - parses `Set-Cookie` header values (name=value; Domain; Path; Expires; Max-Age; Secure; HttpOnly).
import 'dart:io' show HttpDate;

class SetCookie {
  final String name;
  final String value;
  final String? domain;
  final String? path;
  final DateTime? expires;
  final int? maxAge;
  final bool secure;
  final bool httpOnly;

  const SetCookie(this.name, this.value, {this.domain, this.path, this.expires, this.maxAge, this.secure = false, this.httpOnly = false});

  /// True when the server asks to delete the cookie (Max-Age <= 0 or Expires in the past).
  bool get isDeletion {
    if (maxAge != null) return maxAge! <= 0;
    final e = expires;
    return e != null && e.isBefore(DateTime.now().toUtc());
  }

  @override
  String toString() => '$name=$value';
}

class SetCookieParser {
  /// Returns null when [header] carries no `name=value` pair.
  static SetCookie? parse(String header) {
    final parts = header.split(';');
    if (parts.isEmpty) return null;
    final first = parts.first;
    final eq = first.indexOf('=');
    if (eq <= 0) return null;
    final name = first.substring(0, eq).trim();
    var value = first.substring(eq + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
    if (name.isEmpty) return null;
    String? domain, path;
    DateTime? expires;
    int? maxAge;
    var secure = false, httpOnly = false;
    for (final raw in parts.skip(1)) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      final i = p.indexOf('=');
      final k = (i < 0 ? p : p.substring(0, i)).trim().toLowerCase();
      final v = i < 0 ? '' : p.substring(i + 1).trim();
      switch (k) {
        case 'domain':
          domain = v.startsWith('.') ? v.substring(1) : v;
          break;
        case 'path':
          path = v;
          break;
        case 'expires':
          try {
            expires = HttpDate.parse(v);
          } catch (_) {
            expires = null;
          }
          break;
        case 'max-age':
          maxAge = int.tryParse(v);
          break;
        case 'secure':
          secure = true;
          break;
        case 'httponly':
          httpOnly = true;
          break;
      }
    }
    return SetCookie(name, value, domain: domain, path: path, expires: expires, maxAge: maxAge, secure: secure, httpOnly: httpOnly);
  }

  static List<SetCookie> parseAll(Iterable<String> headers) {
    final out = <SetCookie>[];
    for (final h in headers) {
      final c = parse(h);
      if (c != null) out.add(c);
    }
    return out;
  }
}
