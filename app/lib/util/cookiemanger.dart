// util/cookiemanger.dart - app-level cookie access (`MyCookieManger`) and the bridge to WebView cookie stores (`WebviewCookieManger`).
// The file name keeps the original's spelling.
import 'legado/cookie_jar.dart';

abstract class MyCookieManger {
  static Future<String> get(String url) async => CookieStore.getCookie(url);

  /// Replaces the cookie of [url]'s domain with [cookie] (`a=1; b=2`).
  static Future<void> set(String url, String cookie) async => CookieStore.setCookie(url, cookie);

  static Future<void> delete(String url) async => CookieStore.removeCookie(url);

  /// Cookie header text from a map (`k=v; k2=v2`).
  static String fromMap(Map<String, String> m) => m.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// Synchronises cookies with a WebView's store. The host app installs the hooks (a WebView plugin cannot be used in unit tests);
/// without hooks the calls only touch [CookieStore].
abstract class WebviewCookieManger {
  static Future<void> Function(String url, String cookie)? pushToWebView;
  static Future<String> Function(String url)? pullFromWebView;

  /// Copies the WebView's cookies for [url] into [CookieStore] (after a login in a browser page).
  static Future<void> pull(String url) async {
    final f = pullFromWebView;
    if (f == null) return;
    final c = await f(url);
    if (c.isNotEmpty) CookieStore.replaceCookie(url, c);
  }

  /// Hands the stored cookies of [url] to the WebView (before loading a source page in it).
  static Future<void> push(String url) async {
    final f = pushToWebView;
    final c = CookieStore.getCookie(url);
    if (f != null && c.isNotEmpty) await f(url, c);
  }
}
