// pages/web/web_hooks.dart — not a file of the original: the start-up wiring of the sources / RSS / web area.
//
//  * `LegadoPlatform` hooks of the engine -> these pages: `java.startBrowser` / `startBrowserAwait` / `webView` -> WebviewPage,
//    `java.getVerificationCode` -> the captcha dialog (qread/verification_code.dart), toast / copyText, `reLoginView` -> the
//    source login; `WebviewCookieManger.pushToWebView` -> the web view cookie store.
//  * `legado://` / `yuedu://` / `qread://` import links -> the importers.
//  * the bound 轻阅读 backend: state loaded, device channel connected when bound.
//  * route names for `Nav.openNamed` ([openSourcesRoute]) and the `Nav.openSourceEdit` / `Nav.openRss` targets ([registerNav]).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../common/nav.dart';
import '../../data/rss.dart';
import '../../data/source.dart';
import '../../qread/qread.dart';
import '../../qread/verification_code.dart';
import '../../util/cookiemanger.dart';
import '../../util/toast.dart';
import '../../util/webbook/model/book_source.dart';
import '../../util/webbook/model/rss_source.dart';
import '../../util/webbook/util/client_app.dart';
import '../qread/qread_login.dart';
import '../rss/open.dart';
import '../rss/rss_setting.dart';
import '../rss_page.dart';
import '../scanner/mobile_scanner.dart';
import '../source/edit_source.dart';
import '../source/login_dialog.dart';
import '../source/source_help.dart';
import '../source/source_setting.dart';
import 'bookmark_manager_page.dart';
import 'chrome.dart';
import 'webview.dart';

abstract class SourcesArea {
  /// Navigator used by the engine hooks (default: GetX's root navigator, which `GetMaterialApp` installs).
  static GlobalKey<NavigatorState>? navigatorKey;

  static NavigatorState? get _nav => navigatorKey?.currentState ?? Get.key.currentState;

  /// Installs every hook; call once after the storage is ready (e.g. at the end of `AppInit.init`).
  static Future<void> init({GlobalKey<NavigatorState>? key, bool connectBackend = true}) async {
    navigatorKey = key;
    installEngineHooks();
    importLinkHandler = handleImportLink;
    try {
      await Qread.load();
      if (connectBackend && Qread.isbind) {
        // the device channel is best effort; failures only log
        QreadWebsocket.connect();
      }
    } catch (e) {
      debugPrint('Qread.load: $e');
    }
  }

  static void installEngineHooks() {
    LegadoPlatform.toast = (m) => Toast.show(m);
    LegadoPlatform.longToast = (m) => Toast.show(m);
    LegadoPlatform.copyText = (t) => Clipboard.setData(ClipboardData(text: t));
    LegadoPlatform.openBrowser = (url, title) {
      _nav?.push(MaterialPageRoute(builder: (c) => WebviewPage(url: url, title: title)));
    };
    LegadoPlatform.startBrowserAwait = (url, title, refetch) async =>
        await _nav?.push<String>(MaterialPageRoute(builder: (c) => WebviewPage(url: url, title: title, captcha: true)));
    LegadoPlatform.webView = ({String? html, required String url, String? js, String? sourceRegex, String? overrideUrlRegex, Map<String, String>? headers}) async =>
        await _nav?.push<String>(MaterialPageRoute(
          builder: (c) => WebviewPage(
            url: url,
            html: html,
            header: headers,
            js: js,
            sourceRegex: sourceRegex,
            overrideUrlRegex: overrideUrlRegex,
            autoReturn: true,
          ),
        ));
    LegadoPlatform.getVerificationCode = (imageUrl) async {
      final ctx = _nav?.context;
      if (ctx == null) return null;
      return showVerificationCodeDialog(ctx, imageUrl);
    };
    LegadoPlatform.reLoginView = (key) async {
      final ctx = _nav?.context;
      if (ctx == null) return;
      final b = Sourcedata.byUrl(key);
      if (b != null) return showSourceLogin(ctx, BookSource.fromJson(b));
      final r = Rssdata.byUrl(key);
      if (r != null) return showSourceLogin(ctx, RssSource.fromJson(r));
    };
    WebviewCookieManger.pushToWebView = (url, cookie) async {
      final u = Uri.tryParse(url);
      if (u == null || u.host.isEmpty) return;
      try {
        final m = WebViewCookieManager();
        for (final pair in cookie.split(';')) {
          final i = pair.indexOf('=');
          if (i > 0) await m.setCookie(WebViewCookie(name: pair.substring(0, i).trim(), value: pair.substring(i + 1).trim(), domain: u.host));
        }
      } catch (e) {
        debugPrint('注入cookie失败:$e');
      }
    };
  }

  /// `legado://import/bookSource?src=…` and friends: RSS links go to the RSS importer, everything else to the book-source one.
  static Future<void> handleImportLink(BuildContext context, Uri uri) =>
      SourceImport.handleLink(context, uri, importRss: (c, src) async => RssImport.importText(c, src));

  /// Points the cross-area hooks at this area's pages.
  static void registerNav() {
    Nav.openSourceEdit = openSourceEdit;
    Nav.openRss = openRss;
  }

  /// Route names of this area for `Nav.openNamed` (the original's file stems); returns false for names it does not know.
  static Future<bool> openSourcesRoute(BuildContext context, String name, {Object? arguments}) async {
    final Widget? page = switch (name) {
      'source_page' || 'source_setting' || 'sourcesetting' => const SourceSettingPage(),
      'rss_page' => const RssPage(),
      'rss_setting' || 'rsssetting' => const RssSettingPage(),
      'chrome' || 'chrome_inapp' => ChromePage(url: arguments is String ? arguments : null),
      'bookmark_manager_page' => const BookmarkManagerPage(),
      'qread_login' => const QReadLoginPage(),
      'source_help' || 'sourcehelp' => const SourceHelpPage(),
      'mobile_scanner' => const MobileScannerPage(),
      'webview' when arguments is String => WebviewPage(url: arguments),
      _ => null,
    };
    if (page == null) return false;
    await Navigator.of(context).push(MaterialPageRoute(builder: (c) => page));
    return true;
  }
}
