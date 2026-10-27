// util/legado/cookie_jar.dart - Legado's `CookieStore`: one cookie string per registrable domain (`a=1;b=2`), merged on every
// response, readable/writable from JS as `cookie.*` and sent with every request of a source that has `enabledCookieJar`.
import '../webbook/util/network_utils.dart';
import 'js_bindable.dart';
import 'set_cookie_parser.dart';

class CookieStore {
  static final Map<String, String> _cookies = {};

  /// Persistence hooks for the data layer.
  static void Function(String domainKey, String cookie)? onSave;
  static void Function(String domainKey)? onRemove;

  static String _key(String url) => NetworkUtils.getSubDomain(url);

  static void load(Map<String, String> items) => _cookies.addAll(items);

  /// All stored cookies by domain key (for persistence/diagnostics).
  static Map<String, String> get all => Map.unmodifiable(_cookies);

  static String getCookie(String url) => _cookies[_key(url)] ?? '';

  static String getKey(String url, String key) => cookieToMap(getCookie(url))[key] ?? '';

  /// Replaces the stored cookie string of [url]'s domain.
  static void setCookie(String url, String? cookie) {
    if (url.isEmpty) return;
    final k = _key(url);
    if (cookie == null || cookie.isEmpty) {
      removeCookie(url);
      return;
    }
    _cookies[k] = cookie;
    onSave?.call(k, cookie);
  }

  /// Merges [cookie] (`k=v;k2=v2`) into the stored one; new keys win.
  static void replaceCookie(String url, String cookie) {
    if (url.isEmpty || cookie.isEmpty) return;
    final old = getCookie(url);
    if (old.isEmpty) {
      setCookie(url, cookie);
      return;
    }
    final m = cookieToMap(old)..addAll(cookieToMap(cookie));
    setCookie(url, mapToCookie(m));
  }

  static void removeCookie(String url) {
    final k = _key(url);
    if (_cookies.remove(k) != null) onRemove?.call(k);
  }

  /// Applies `Set-Cookie` response headers received from [url].
  static void saveFromResponse(String url, Iterable<String> setCookieHeaders) {
    if (setCookieHeaders.isEmpty) return;
    final m = cookieToMap(getCookie(url));
    var changed = false;
    for (final c in SetCookieParser.parseAll(setCookieHeaders)) {
      if (c.isDeletion) {
        changed = m.remove(c.name) != null || changed;
      } else {
        m[c.name] = c.value;
        changed = true;
      }
    }
    if (changed) setCookie(url, mapToCookie(m));
  }

  static Map<String, String> cookieToMap(String cookie) {
    final map = <String, String>{};
    if (cookie.trim().isEmpty) return map;
    for (final pair in cookie.split(';')) {
      final i = pair.indexOf('=');
      if (i < 0) continue;
      final key = pair.substring(0, i).trim();
      final value = pair.substring(i + 1);
      if (key.isEmpty) continue;
      if (value.trim().isNotEmpty || value.trim() == 'null') map[key] = value.trim();
    }
    return map;
  }

  static String? mapToCookie(Map<String, String>? m) {
    if (m == null || m.isEmpty) return null;
    final parts = <String>[];
    for (final e in m.entries) {
      if (e.value.trim().isNotEmpty) parts.add('${e.key}=${e.value}');
    }
    if (parts.isEmpty) return null;
    return parts.join(';');
  }

  static void resetForTests() {
    _cookies.clear();
    onSave = null;
    onRemove = null;
  }
}

/// JavaScript `cookie` object.
class CookieBinding extends JsBindable {
  static final CookieBinding instance = CookieBinding();

  @override
  Iterable<String> get jsMethods => const [
        'getCookie', 'getKey', 'setCookie', 'replaceCookie', 'removeCookie', 'cookieToMap', 'mapToCookie', 'get', 'set', 'remove',
        'setcookie',
      ];

  @override
  Object? jsCall(String name, List<Object?> args) {
    String a(int i) => i < args.length ? '${args[i] ?? ''}' : '';
    switch (name) {
      case 'getCookie':
      case 'get':
        if (args.length >= 2) return CookieStore.getKey(a(0), a(1));
        return CookieStore.getCookie(a(0));
      case 'getKey':
        return CookieStore.getKey(a(0), a(1));
      case 'setCookie':
      case 'setcookie':
      case 'set':
        CookieStore.setCookie(a(0), a(1));
        return null;
      case 'replaceCookie':
        CookieStore.replaceCookie(a(0), a(1));
        return null;
      case 'removeCookie':
      case 'remove':
        CookieStore.removeCookie(a(0));
        return null;
      case 'cookieToMap':
        return CookieStore.cookieToMap(a(0));
      case 'mapToCookie':
        final m = args.isNotEmpty && args[0] is Map ? (args[0] as Map).map((k, v) => MapEntry('$k', '$v')) : <String, String>{};
        return CookieStore.mapToCookie(m);
    }
    return super.jsCall(name, args);
  }
}
