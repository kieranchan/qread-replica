// util/source/browser_source.dart — the built-in 「浏览器」 时光源 behind the in-app browser's 阅读模式 (pages/web/chrome_inapp.dart).
//
// Original (SourceApi.getSource 0x1b9adc): a book whose `origin` ends in `@chrome` belongs to a synthetic Source named 「浏览器」 whose
// page is `http://yuan.qread.xyz/get-html?url=<page url>` — a generic parser served (as an `@aes` page) by qread.xyz. The replica
// never calls qread.xyz: the page is its own (browser_source_page.dart), and the owner's server may hold a newer copy at
// `<apiBase>static/browser.html` (server: `qread-admin set-static browser <file.html>`), which replaces the built-in page once
// fetched so that the parser can be updated without a new build. `Sourcedata.byUrl` hands this source out for every `@chrome`
// origin, so the detail page, catalog, reader and downloads treat such a book like any 时光源 book.
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../common/common.dart';
import '../../storage/storage.dart';
import '../http.dart';
import 'browser_source_page.dart';

abstract class BrowserSource {
  /// Origin suffix of the original (`"@chrome"`, 0x21cd8).
  static const String suffix = '@chrome';

  /// `bookSourceName` of the synthetic source (0x1b9b88).
  static const String name = '浏览器';

  /// Path of the server copy of the page under `Common.apiBase`.
  static const String remotePath = 'static/browser.html';

  /// Storage key of the cached server copy.
  static const String remoteKey = 'browser_source_page';

  /// The server copy, '' when the server has none (the built-in page is used then).
  static String remotePage = '';

  /// Whether start-up fetches the server copy (not under `flutter test`: tests call [refresh] themselves).
  static bool autoRefresh = !Platform.environment.containsKey('FLUTTER_TEST');

  static bool isOrigin(String origin) => origin.length > suffix.length && origin.endsWith(suffix);

  /// The page url inside an origin (`https://a/b@chrome` -> `https://a/b`); other strings come back unchanged.
  static String pageUrl(String origin) => isOrigin(origin) ? origin.substring(0, origin.length - suffix.length) : origin;

  static String originOf(String pageUrl) => '$pageUrl$suffix';

  /// The page in use: the server copy when one was fetched, else the built-in one.
  static String get page => remotePage.isNotEmpty ? remotePage : browserSourcePage;

  /// The raw source map `Sourcedata.byUrl` gives for [origin] (one source per page, so every page gets its own runner — the
  /// original keys its runners by the `get-html?url=…` address the same way).
  static Map<String, dynamic> raw(String origin) => {
        'bookSourceUrl': origin,
        'bookSourceName': name,
        'bookSourceGroup': name,
        'html': page,
        'enabled': true,
        'enabledExplore': false,
      };

  /// A page is a 时光源 page of this kind when it declares the entry point 阅读模式 calls.
  static bool looksLikePage(String html) => html.contains('async function getinfo(') && html.contains('async function chapter(');

  /// Start-up: the cached server copy, if any.
  static Future<void> load() async {
    try {
      final cached = await Storage.read(remoteKey);
      remotePage = looksLikePage(cached) ? cached : '';
    } catch (_) {
      remotePage = '';
    }
  }

  /// Fetches the server copy (`<apiBase>static/browser.html`) and keeps it; a 404 (no copy on the server) drops a cached one so
  /// that the built-in page is used again. Network errors keep whatever was loaded.
  static Future<bool> refresh({Duration timeout = const Duration(seconds: 15)}) async {
    final base = Common.apiBase.endsWith('/') ? Common.apiBase : '${Common.apiBase}/';
    try {
      final res = await AppHttp.send(HttpRequest(url: '$base$remotePath', timeout: timeout));
      if (res.statusCode == 404) {
        if (remotePage.isNotEmpty) {
          remotePage = '';
          await Storage.write(remoteKey, '');
        }
        return false;
      }
      if (!res.isSuccessful) return false;
      final body = AppHttp.decodeBody(res.bodyBytes, contentType: res.contentType).trim();
      if (!looksLikePage(body)) return false;
      if (body != remotePage) {
        remotePage = body;
        await Storage.write(remoteKey, body);
      }
      return true;
    } catch (e) {
      debugPrint('浏览器书源更新失败: $e');
      return false;
    }
  }
}
