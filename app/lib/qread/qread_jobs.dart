// qread/qread_jobs.dart — the device-channel jobs of the bound 轻阅读 backend that reach into pages (dispatcher 0x2ad0ac, see
// `QreadWebsocket.handle`), and 导入后端 (upload local books to the backend's shelf, 0xf77e50).
//
// The original keeps the pages these jobs act on in statics that the pages set while they are open; [QreadHooks] holds the same
// slots (static addresses in brackets) so the reader / discovery / source-login pages can register themselves without this file
// importing them. A job whose page is not registered does nothing, like the original's null checks.
//
//   logout 0xe0e7d4        isbind false (file store `Qreadisbind<appid>` = "false"), allowchange 2, no edit permission, the next
//                          `init` asks /getUserInfo again, the channel closes, the main page refreshes [0x1ee0]
//   openurl 0xf1e558       操作提醒 / 是否打开《title》吗？; legado / yuedu links go to the app-link handler, others open outside the app
//   searchBook 0xf1e38c    the search page with `title` as key; `url` (after `::` when present) limits it to that source
//   addBook 0xf1df74       `/urlsaveBook {url}` → the backend's book (`isqread`) → its detail page; failures as a toast
//   bookmd5                nothing (the original compares and returns)
//   rssmd5 0xf1c7d8 / sourcemd5 0xf1b0cc   the backend's RSS / book-source list is fetched again when its md5 changed
//   init 0xf1ad98          once per binding: /getUserInfo
//   gonggao 0xf1abe4       once per run: the backend's notice in a 提示 dialog (util/info.dart 0xd3920)
//   reLoginView / upLoginData   the source-login page [0x1e90 / 0x1e94]
//   refreshBookInfo / refreshBookToc / refreshContent   only for the backend book open in the reader [0x1e98] whose `origin` is `title`:
//                          its info from the source (0xe6477c), the reader's TOC [0x1e9c] or chapter [0x1ea0]
//   refreshExplore 0xf1ab48   clears the file-store cache `QExploreUrl<title>` and reloads the discovery page [0x1ea4]
//   anything else          `/noCookies {id}` tells the backend the job is not handled here (0x2af1fc → 0xf1a9ac)
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../common/common.dart';
import '../common/nav.dart';
import '../data/bookself.dart';
import '../data/qsource.dart';
import '../data/source.dart';
import '../models/book.dart';
import '../models/source.dart';
import '../storage/storage.dart';
import '../util/toast.dart';
import 'api/qsourceapi.dart';
import 'http.dart';
import 'qread.dart';
import 'rssdata.dart';

/// Pages register here while they are open (the original's statics).
abstract class QreadHooks {
  /// [0x1edc] context for dialogs and pushed pages.
  static BuildContext? Function() context = () => Get.context;

  /// [0x1ee0] the main page refreshes after the backend logged this device out.
  static VoidCallback? onLogout;

  /// [0x1ea4] the discovery page reloads its backend explore entries.
  static Future<void> Function()? refreshExplore;

  /// [0x1e98] the book open in the reader.
  static Book? currentBook;

  /// [0x1e9c] / [0x1ea0] the reader reloads its table of contents / its chapter.
  static Future<void> Function()? refreshToc;
  static Future<void> Function()? refreshContent;

  /// 0xe6477c: refreshes the info of [book] from its source and saves it on the shelf.
  static Future<void> Function(Book book)? refreshBookInfo;

  /// [0x1e90] / [0x1e94] the source-login page reloads its view / receives login data.
  static VoidCallback? reLoginView;
  static void Function(String data)? upLoginData;

  /// legado:// / yuedu:// links of `openurl` (the app-link dispatcher); null = open outside the app.
  static Future<void> Function(String url)? openAppLink;

  /// Opens a link outside the app (tests replace it).
  static Future<void> Function(String url) launch = (url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  };

  /// Asks before `openurl` (tests replace it): 操作提醒 / 是否打开《title》吗？.
  static Future<bool> Function(BuildContext context, String title) confirmOpen = (context, title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('操作提醒'),
        content: Text('是否打开《$title》吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
        ],
      ),
    );
    return ok == true;
  };

  @visibleForTesting
  static void reset() {
    context = () => Get.context;
    onLogout = null;
    refreshExplore = null;
    currentBook = null;
    refreshToc = null;
    refreshContent = null;
    refreshBookInfo = null;
    reLoginView = null;
    upLoginData = null;
    openAppLink = null;
    QreadJobs.inited = false;
    QreadJobs.noticeShown = false;
  }
}

abstract class QreadJobs {
  /// [0x1d40] `init` ran for this binding.
  static bool inited = false;

  /// [0x1d74] the notice was shown in this run.
  static bool noticeShown = false;

  static Future<void>? _sourceSync;
  static Future<void>? _rssSync;

  /// Runs job [msg] with the fields of the message [f] (String values). True when the job is one of these.
  static Future<bool> run(String msg, String Function(String key) f) async {
    switch (msg) {
      case 'logout':
        await logout();
      case 'openurl':
        await openUrl(f('url'), f('title'));
      case 'searchBook':
        await searchBook(f('title'), f('url'));
      case 'addBook':
        await addBook(f('url'));
      case 'bookmd5':
        break;
      case 'rssmd5':
        await rssMd5(f('md5'));
      case 'sourcemd5':
        await sourceMd5(f('md5'));
      case 'init':
        if (!inited) {
          inited = true;
          await Qread.refreshUserInfo();
        }
      case 'gonggao':
        notice(f('md5'));
      case 'reLoginView':
        QreadHooks.reLoginView?.call();
      case 'upLoginData':
        QreadHooks.upLoginData?.call(f('title'));
      case 'refreshBookInfo':
      case 'refreshBookToc':
      case 'refreshContent':
        final b = QreadHooks.currentBook;
        if (b == null || !b.isqread || b.origin != f('title')) break;
        final Future<void> Function()? job = switch (msg) {
          'refreshBookInfo' => QreadHooks.refreshBookInfo == null ? null : () => QreadHooks.refreshBookInfo!(b),
          'refreshBookToc' => QreadHooks.refreshToc,
          _ => QreadHooks.refreshContent,
        };
        await job?.call();
      case 'refreshExplore':
        await Storage.write('QExploreUrl${f('title')}', '');
        await QreadHooks.refreshExplore?.call();
      default:
        return false;
    }
    return true;
  }

  /// 0xe0e7d4: the backend ended this device's session.
  static Future<void> logout() async {
    Qread.isbind = false;
    await Storage.write('Qreadisbind${Common.appid}', 'false');
    Qread.allowchange = 2;
    Qread.caneditsource = false;
    inited = false;
    QreadWebsocket.close();
    Qread.revision.value++;
    QreadHooks.onLogout?.call();
  }

  static Future<void> openUrl(String url, String title) async {
    final ctx = QreadHooks.context();
    if (ctx == null || url.isEmpty) return;
    if (!await QreadHooks.confirmOpen(ctx, title)) return;
    if ((url.contains('legado') || url.contains('yuedu')) && QreadHooks.openAppLink != null) {
      await QreadHooks.openAppLink!(url);
    } else {
      await QreadHooks.launch(url);
    }
  }

  static Future<void> searchBook(String title, String url) async {
    final ctx = QreadHooks.context();
    if (ctx == null) return;
    if (url.isEmpty) {
      await Nav.openSearch(ctx, key: title);
      return;
    }
    final u = url.contains('::') ? url.split('::').last : url;
    final Source? source = Sourcedata.sourceByUrl(u) ?? QSources.byUrl(u);
    await Nav.openSearch(ctx, key: title, sources: source == null ? null : [source]);
  }

  /// `/urlsaveBook` (0xf1e164): the backend parses a book page url into one of its books.
  static Future<Book> urlSaveBook(String url) async {
    final data = await Qread.post('/urlsaveBook', {'url': url});
    if (data is! Map) throw const QreadException('网络错误');
    return Book.fromJson(Map<String, dynamic>.from(data))
      ..isqread = true
      ..isinfo = false;
  }

  static Future<void> addBook(String url) async {
    try {
      final book = await urlSaveBook(url);
      final ctx = QreadHooks.context();
      if (ctx != null && ctx.mounted) await Nav.openBook(ctx, book);
    } catch (e) {
      Toast.show('$e', iserror: true);
    }
  }

  static Future<void> sourceMd5(String md5) {
    if (md5 == QSources.md5) return Future.value();
    return _sourceSync ??= QSourceApi.refresh().then<void>((_) {}).catchError((Object e) => debugPrint('sourcemd5: $e')).whenComplete(() => _sourceSync = null);
  }

  static Future<void> rssMd5(String md5) {
    if (md5 == QRssSources.md5) return Future.value();
    return _rssSync ??= QRssSources.refresh().then<void>((_) {}).catchError((Object e) => debugPrint('rssmd5: $e')).whenComplete(() => _rssSync = null);
  }

  /// 0xf1abe4: the backend's notice, once per run.
  static void notice(String text) {
    if (noticeShown || text.isEmpty) return;
    final ctx = QreadHooks.context();
    if (ctx == null) return;
    noticeShown = true;
    showDialog<void>(context: ctx, builder: (c) => noticeDialog(c, text));
  }

  /// util/info.dart 0xd3920: icon + 提示, the text, 确定.
  static Widget noticeDialog(BuildContext c, String text) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.info_outline, size: 24),
          SizedBox(width: 12),
          Text('提示', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        content: SingleChildScrollView(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.5))),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('确定'))],
      );

  /// 0x2af1fc → 0xf1a9ac: tells the backend that job [id] is not handled on this device.
  static Future<void> notHandled(String id) async {
    try {
      await Qread.post('/noCookies', {'id': id});
    } catch (e) {
      debugPrint('noCookies: $e');
    }
  }
}

/// 导入后端 (shelf 添加书籍, ImportType 4 → 0xf77e50): local txt / epub files are uploaded to the bound backend
/// (`/importBookPreview`, multipart field `file`, 0xf78418); the books it answers (`data.books`) go on the shelf as backend books.
/// Toasts as the original: 请选择您想要导入的小说文件 first, `正在导入文件<n>` while uploading, `第<n>本书，导入失败:<error>!` per failed file.
abstract class QreadImport {
  /// The file picker (tests replace it): txt and epub only, like the original.
  static Future<List<File>> Function() pickFiles = () async {
    final files = await FilePicker.pickFiles(dialogTitle: '请选择您想要导入的小说文件', type: FileType.custom, allowedExtensions: const ['txt', 'epub']);
    return [for (final f in files) if (f.path != null) File(f.path!)];
  };

  /// 0xf78418: uploads one file; the backend's books, marked `isqread`.
  static Future<List<Book>> upload(File file) async {
    final url = Qread.api('/importBookPreview');
    final Map<String, dynamic> r;
    try {
      r = await QHttp.postFile(url, const {}, await file.readAsBytes(), p.basename(file.path));
    } on QHttpException {
      throw const QreadException('网络连接错误');
    }
    if (r['isSuccess'] != true) throw QreadException('${r['errorMsg'] ?? '导入失败'}');
    var data = r['data'];
    if (data is String && data.trim().startsWith('{')) data = jsonDecode(data);
    var list = data is Map ? data['books'] : data;
    if (list is String && list.trim().startsWith('[')) list = jsonDecode(list);
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map)
          Book.fromJson(Map<String, dynamic>.from(e))
            ..isqread = true
            ..type_ = 0
            ..isinfo = true,
    ];
  }

  /// The whole flow; returns the number of books added to the shelf.
  static Future<int> run() async {
    if (!Qread.isbind) {
      Toast.show('请先绑定轻阅读后端');
      return 0;
    }
    Toast.show('请选择您想要导入的小说文件');
    List<File> files;
    try {
      files = await pickFiles();
    } catch (e) {
      Toast.show('选择文件失败:$e!', iserror: true);
      return 0;
    }
    var added = 0;
    for (var i = 0; i < files.length; i++) {
      Toast.show('正在导入文件${i + 1}');
      try {
        for (final b in await upload(files[i])) {
          await BookSelfN.add(b);
          added++;
        }
      } catch (e) {
        Toast.show('第${i + 1}本书，导入失败:$e!', iserror: true);
      }
    }
    return added;
  }
}
