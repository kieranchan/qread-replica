// pages/web/web_hooks.dart — not a file of the original: the start-up wiring of the sources / RSS / web area.
//
//  * `LegadoPlatform` hooks of the engine -> these pages: `java.startBrowser` / `startBrowserAwait` / `webView` -> WebviewPage,
//    `java.getVerificationCode` -> the captcha dialog (qread/verification_code.dart), toast / copyText, `reLoginView` -> the
//    source login; `WebviewCookieManger.pushToWebView` -> the web view cookie store.
//  * 时光源 page handlers (`SourceUi`) -> the source browser page (source_webview.dart), captcha, detail and search pages.
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
import '../../models/book.dart';
import '../../qread/qread.dart';
import '../../qread/verification_code.dart';
import '../../util/cookiemanger.dart';
import '../../util/source/baswebview.dart';
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
import 'source_webview.dart';
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
    installTimeSourceHooks();
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

  /// What the 时光源 page handlers open (util/source/baswebview.dart `SourceUi`): the source browser page (startBrowser*, login
  /// urls, discovery entries of type 1), the captcha dialog, the detail page (`addbook`), the search page (`searchbook`), the
  /// screen size. Reader hooks (getReadBook, refreshContent, voice, …) are left to the reader area.
  static void installTimeSourceHooks() {
    SourceUi.openBrowser = (r) async {
      final nav = _nav;
      if (nav == null) return null;
      return SourceWebviewPage.open(nav, r);
    };
    SourceUi.verificationCode = (url, headers) async {
      final ctx = _nav?.context;
      if (ctx == null) return null;
      return showVerificationCodeDialog(ctx, url);
    };
    SourceUi.openBook = (sourceUrl, bookUrl) async {
      final ctx = _nav?.context;
      if (ctx == null || bookUrl.isEmpty) return;
      await Nav.openBook(ctx, Book(bookUrl: bookUrl, origin: sourceUrl));
    };
    SourceUi.searchBook = (sourceUrl, key) async {
      final ctx = _nav?.context;
      if (ctx == null) return;
      final s = Sourcedata.sourceByUrl(sourceUrl);
      await Nav.openSearch(ctx, key: key, sources: s == null ? null : [s]);
    };
    SourceUi.chooseSvg = (svg) async {
      final ctx = _nav?.context;
      if (ctx == null) return;
      await Nav.openNamed(ctx, 'choose_svg', arguments: {'svg': svg});
    };
    SourceUi.screenSize = () {
      final ctx = _nav?.context;
      return ctx == null ? Size.zero : MediaQuery.sizeOf(ctx);
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
