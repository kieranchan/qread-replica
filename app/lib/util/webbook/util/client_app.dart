// util/webbook/util/client_app.dart - the seam between the engine and the host app: things rule JavaScript can ask for that only the UI
// layer can do (toast, open a browser, WebView evaluation, captcha input, copy to clipboard). All hooks are optional; unset hooks make
// the corresponding `java.*` native raise a JS error instead of silently doing nothing.
import 'dart:async';

typedef WebViewHandler = Future<String?> Function({String? html, required String url, String? js, String? sourceRegex, String? overrideUrlRegex, Map<String, String>? headers});

class LegadoPlatform {
  static void Function(String message)? toast;
  static void Function(String message)? longToast;

  /// `java.startBrowser(url, title)` / `java.openUrl(url)`: show [url] in an in-app or external browser.
  static void Function(String url, String title)? openBrowser;

  /// `java.startBrowserAwait(url, title, refetchAfterSuccess)`: user interacts with the page, result is the final page source.
  static Future<String?> Function(String url, String title, bool refetchAfterSuccess)? startBrowserAwait;

  /// `java.webView(html, url, js)` / `webViewGetSource` / `webViewGetOverrideUrl`.
  static WebViewHandler? webView;

  /// `java.getVerificationCode(imageUrl)`: shows the captcha and returns what the user typed.
  static Future<String?> Function(String imageUrl)? getVerificationCode;

  static void Function(String text)? copyText;

  /// Value of `java.androidId()` (the app's device id, `Common.appid`).
  static String deviceId = '';

  /// `java.getWebViewUA()`.
  static String? webViewUserAgent;

  /// Asks the user to log in again for the source (`java.reLoginView()`).
  static void Function(String sourceKey)? reLoginView;

  static void resetForTests() {
    toast = null;
    longToast = null;
    openBrowser = null;
    startBrowserAwait = null;
    webView = null;
    getVerificationCode = null;
    copyText = null;
    deviceId = '';
    webViewUserAgent = null;
    reLoginView = null;
  }
}
