// service/app_links_service.dart — links and files handed to the app (original `AppLinksService`, mixin of the main page; `_appLinks`
// static 0x910, listener 0x8eb0fc, dispatcher 0x10bd4a0).
//
//  * the same link again within 10 s is ignored (0x8eb0fc keeps the last uri and its time);
//  * `file://…` (documents opened with the app): `.txt` / `.epub` / `.mobi` / `.pdf` → imported to the shelf (0xf792cc), `.json` →
//    imported by content (0xe6af58), anything else → toast `暂不支持当前格式`; failures `导入失败:<error>`;
//  * `qread://…?src=<url>`: path `/addToBookshelf` → `urlsaveBook` (the detail page of the book url), otherwise the text at `src` is
//    downloaded and imported by content (0xe6ad38, error `获取网络规则失败:`);
//  * `legado://` / `yuedu://` import links (not in the original's dispatcher; Legado's own scheme) → the source / RSS importers.
// Content detection of 0xe6af58, in this order: `bookSourceUrl` + `bookSourceName` → book sources, `sourceUrl"` → RSS sources,
// `isRegex"` → replace rules, `name` + `html` → HTTP TTS engines, `name` + `rule` → TXT TOC rules, else `未知的文件格式`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../data/bookself.dart';
import '../data/replace.dart';
import '../data/tts.dart';
import '../data/txtrule.dart';
import '../models/book.dart';
import '../pages/book/book_detail_page.dart';
import '../pages/rss/rss_setting.dart';
import '../pages/source/source_setting.dart';
import '../read/local_book_importer.dart';
import '../util/http.dart';
import '../util/toast.dart';
import '../widget/book/url_save_book.dart';

abstract class AppLinksService {
  static GlobalKey<NavigatorState>? _navigatorKey;
  static AppLinks? _appLinks;
  static StreamSubscription<Uri>? _sub;
  static String? _lastUri;
  static int _lastMs = 0;

  /// Book files the shelf imports when they are opened with the app.
  static const List<String> bookExtensions = ['.txt', '.epub', '.mobi', '.pdf'];

  /// Hooks for tests: the link stream (default: the `app_links` plugin) and the downloader of `qread://…?src=` texts.
  static Stream<Uri> Function()? linkStream;
  static Future<String> Function(String url) download = _download;

  /// Starts listening (the initial link included). [navigatorKey] gives the context for dialogs and pages; without it GetX's root
  /// navigator is used.
  static Future<void> init(GlobalKey<NavigatorState>? navigatorKey) async {
    _navigatorKey = navigatorKey;
    await _sub?.cancel();
    Stream<Uri> stream;
    try {
      stream = linkStream?.call() ?? (_appLinks ??= AppLinks()).uriLinkStream;
    } catch (e) {
      debugPrint('AppLinks: $e');
      return;
    }
    _sub = stream.listen((uri) => unawaited(onLink(uri)), onError: (Object e) => debugPrint('AppLinks: $e'));
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _lastUri = null;
    _lastMs = 0;
  }

  static BuildContext? get _context => _navigatorKey?.currentState?.context ?? Get.key.currentState?.context;

  /// 0x8eb0fc: drops the same link within 10 s, then dispatches it.
  static Future<void> onLink(Uri uri) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = uri.toString();
    if (s == _lastUri && now - _lastMs < 10000) return;
    _lastUri = s;
    _lastMs = now;
    await handle(uri);
  }

  /// 0x10bd4a0.
  static Future<void> handle(Uri uri) async {
    try {
      switch (uri.scheme.toLowerCase()) {
        case 'file':
          await _openFile(File(uri.toFilePath()));
        case 'qread':
          await _qreadLink(uri);
        case 'legado':
        case 'yuedu':
          final ctx = _context;
          if (ctx == null) return;
          await SourceImport.handleLink(ctx, uri, importRss: (c, src) async => RssImport.importText(c, src));
      }
    } catch (e) {
      debugPrint('处理文件失败: $e');
      Toast.show('导入失败:$e', iserror: true);
    }
  }

  static Future<void> _openFile(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (bookExtensions.contains(ext)) {
      // 0xf792cc (`delete: !isIOS`: the iOS inbox copy is kept)
      final local = await const LocalBookImporter().import(file);
      await BookSelfN.add(local.book);
      Toast.show('导入成功');
      return;
    }
    if (ext == '.json') {
      final text = await file.readAsString();
      if (text.trim().isEmpty) throw Exception('文件内容为空');
      await importText(text);
      return;
    }
    Toast.show('暂不支持当前格式');
  }

  /// 0xe6ad38.
  static Future<void> _qreadLink(Uri uri) async {
    final src = uri.queryParameters['src'] ?? '';
    if (src.isEmpty) return;
    if (uri.path == '/addToBookshelf') {
      final ctx = _context;
      if (ctx == null) return;
      await urlSaveBook(ctx, src, (bookUrl, origin) async {
        final c = _context;
        if (c == null) return;
        await Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: Book(bookUrl: bookUrl, origin: origin))));
      });
      return;
    }
    String text;
    try {
      text = await download(src);
    } catch (e) {
      Toast.show('获取网络规则失败:$e', iserror: true);
      return;
    }
    await importText(text);
  }

  static Future<String> _download(String url) async {
    final r = await AppHttp.send(HttpRequest(url: url));
    if (!r.isSuccessful) throw HttpFailure('HTTP ${r.statusCode}');
    return AppHttp.decodeBody(r.bodyBytes, contentType: r.contentType);
  }

  /// 0xe6af58: imports [text] into the list its content belongs to.
  static Future<void> importText(String text) async {
    bool has(String s) => text.contains(s);
    if (has('bookSourceUrl') && has('bookSourceName')) {
      final ctx = _context;
      if (ctx == null) return;
      await SourceImport.importText(ctx, text);
      return;
    }
    if (has('sourceUrl"') || has("sourceUrl'")) {
      final ctx = _context;
      if (ctx == null) return;
      await RssImport.importText(ctx, text);
      return;
    }
    int n;
    if (has('isRegex"') || has("isRegex'")) {
      n = await Replaces.importJson(text);
    } else if (has('name') && has('html')) {
      n = await Tts.importJson(_ttsDefinitions(text));
    } else if (has('name') && has('rule')) {
      n = await Txtrule.importJson(text);
    } else {
      throw Exception('未知的文件格式');
    }
    Toast.show('导入成功${n > 0 ? '（$n）' : ''}');
  }

  /// Exported engines (`{name, html: {…definition…}}`) → the Legado HttpTTS definitions `Tts.importJson` reads.
  static String _ttsDefinitions(String text) {
    final v = jsonDecode(text);
    final items = v is List ? v : [v];
    return jsonEncode([
      for (final e in items)
        if (e is Map && e['html'] is Map) {...Map<String, dynamic>.from(e['html'] as Map), 'name': e['name'] ?? (e['html'] as Map)['name']} else e
    ]);
  }
}
