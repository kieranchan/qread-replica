// data/cloud/cloud_books.dart — 云端仓库, the original's WebDAV book repository (cloud_setting_page 0x5ce284 WebDAV section; the sync
// 0xf7a968 / 0xf7e960; its start-up run 0xf7a764; the restore 0xfb024c when a local book's file is missing; settings 0xf7b094 /
// 0xf82804 / 0xfc8314). The local books of the shelf are mirrored into `<backupDir>` of a network drive: files missing there are
// uploaded, files whose size differs are uploaded again, files of books no longer on the shelf are deleted (`同步完成，删除了 d 个WebDAV
// 文件，上传了 u 个本地文件`); a local book whose file is gone on this device is fetched back before it opens (`正在连接云端仓库...`).
// Settings live in prefs `cloudBooksWebDavServer` as the original's JSON {serverId, backupDir, lastSyncTime} (a bare server id from
// older replica builds is read too). The owner's account server offers a WebDAV store at `<apiBase>dav/` whose password is the
// session token, so 「使用轻阅读账号服务器」 sets the repository up without typing anything.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../common/common.dart';
import '../../models/book.dart';
import '../../models/webdavserver.dart';
import '../../read/api/readapi.dart';
import '../../read/local_book_importer.dart';
import '../../storage/storage.dart';
import '../bookself.dart';
import '../user.dart';
import '../webdav.dart';
import 'cloud_drive.dart';

class CloudBooksSettings {
  String serverId;
  String backupDir;
  String lastSyncTime;

  CloudBooksSettings({this.serverId = '', this.backupDir = CloudBooks.defaultDir, this.lastSyncTime = ''});

  Map<String, dynamic> toJson() => {'serverId': serverId, 'backupDir': backupDir, 'lastSyncTime': lastSyncTime};

  /// The stored JSON, a bare server id (older replica builds) or nothing.
  factory CloudBooksSettings.parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return CloudBooksSettings();
    if (s.startsWith('{')) {
      try {
        final m = jsonDecode(s);
        if (m is Map) {
          final dir = '${m['backupDir'] ?? ''}'.trim();
          return CloudBooksSettings(serverId: '${m['serverId'] ?? ''}', backupDir: dir.isEmpty ? CloudBooks.defaultDir : dir, lastSyncTime: '${m['lastSyncTime'] ?? ''}');
        }
      } catch (_) {}
      return CloudBooksSettings();
    }
    return CloudBooksSettings(serverId: s);
  }
}

class CloudBooksReport {
  final int uploaded;
  final int deleted;
  final List<String> errors;
  const CloudBooksReport(this.uploaded, this.deleted, this.errors);
}

abstract class CloudBooks {
  static const String key = WebDav.selectedKey;
  static const String defaultDir = '/books';

  /// The network-drive entry 「使用轻阅读账号服务器」 creates (the account server's WebDAV store).
  static const String ownServerId = 'qread-dav';
  static const String ownServerName = '轻阅读账号服务器';

  static void Function(String line)? log;
  static bool _syncing = false;
  static bool get syncing => _syncing;

  /// How a server becomes a drive (tests replace it).
  static CloudDrive Function(WebDavServer server) driveOf = CloudDrive.of;

  static CloudBooksSettings load() => CloudBooksSettings.parse(Storage.getString(key));
  static Future<void> save(CloudBooksSettings s) => Storage.setString(key, jsonEncode(s.toJson()));
  static bool get configured => load().serverId.isNotEmpty;

  /// Normalises a backup directory to `/a/b` form.
  static String normalizeDir(String dir) {
    var d = dir.trim().replaceAll('\\', '/');
    if (!d.startsWith('/')) d = '/$d';
    while (d.length > 1 && d.endsWith('/')) {
      d = d.substring(0, d.length - 1);
    }
    return d;
  }

  static String get ownUrl {
    final b = Common.apiBase;
    return '${b.endsWith('/') ? b : '$b/'}dav/';
  }

  /// The configured server (the account-server entry refreshed with the current session first), or null.
  static Future<WebDavServer?> server() async {
    final s = load();
    if (s.serverId.isEmpty) return null;
    await WebDav.load();
    if (s.serverId == ownServerId) await _refreshOwn();
    return WebDav.byId(s.serverId);
  }

  /// 「使用轻阅读账号服务器」: creates / refreshes the account-server entry and selects it.
  static Future<WebDavServer> useOwnServer() async {
    if (!UserSession.isLoggedIn) throw StateError('请先登录');
    await WebDav.load();
    final existing = WebDav.byId(ownServerId);
    if (existing == null) {
      await WebDav.add(WebDavServer(id: ownServerId, name: ownServerName, url: ownUrl, username: UserSession.username, password: UserSession.tockenid, type_: CloudDrive.typeWebdav));
    } else {
      await _refreshOwn();
    }
    final st = load()..serverId = ownServerId;
    await save(st);
    return WebDav.byId(ownServerId)!;
  }

  static Future<void> _refreshOwn() async {
    final e = WebDav.byId(ownServerId);
    if (e == null) return;
    if (e.password != UserSession.tockenid || e.username != UserSession.username || e.url != ownUrl) {
      e
        ..url = ownUrl
        ..username = UserSession.username
        ..password = UserSession.tockenid;
      await WebDav.save();
    }
  }

  /// Local books: imported here (`loc_book`) or local entries of the cloud shelf (`phone_book`).
  static bool isLocal(Book b) => b.origin == kPhoneBook || b.origin == ReadApi.localOrigin;

  /// The file name a book has in the repository.
  static String remoteName(Book b) => p.basename(LocalBookImporter.fileOf(b).path);

  static String remotePath(String dir, String name) => dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  /// 0xf7a968 / 0xf7e960: the mirror run. Throws `同步正在进行中，请稍候...` while one runs, `请先选择 WebDAV 服务器` without a server,
  /// `获取WebDAV文件列表失败` when the drive cannot be read; per-file failures are collected in the report.
  static Future<CloudBooksReport> sync({CloudDrive? drive, Iterable<Book>? books, String? backupDir}) async {
    if (_syncing) throw StateError('同步正在进行中，请稍候...');
    _syncing = true;
    try {
      final st = load();
      final dir = normalizeDir(backupDir ?? st.backupDir);
      CloudDrive d;
      if (drive != null) {
        d = drive;
      } else {
        final srv = await server();
        if (srv == null) throw StateError('请先选择 WebDAV 服务器');
        d = driveOf(srv);
      }
      log?.call('开始同步...');
      final shelf = books ?? await Bookdata.load();
      // the shelf's local books: name → file when it exists here (a missing file keeps the remote copy, another device may need it)
      final keep = <String, File?>{};
      for (final b in shelf) {
        if (!isLocal(b)) continue;
        final f = LocalBookImporter.fileOf(b);
        keep[p.basename(f.path)] = f.existsSync() ? f : null;
      }
      List<CloudFile> remote;
      try {
        try {
          remote = await d.list(dir);
        } catch (_) {
          await d.mkdir(dir);
          remote = await d.list(dir);
        }
      } catch (e) {
        throw StateError('获取WebDAV文件列表失败: $e');
      }
      final remoteByName = {for (final f in remote) if (!f.isDir) f.name: f};
      var uploaded = 0;
      var deleted = 0;
      final errors = <String>[];
      for (final e in keep.entries) {
        final f = e.value;
        if (f == null) continue;
        final r = remoteByName[e.key];
        final size = f.lengthSync();
        if (r != null && r.size == size) continue;
        try {
          await d.write(remotePath(dir, e.key), await f.readAsBytes());
          uploaded++;
          log?.call(r == null ? '上传了本地中不存在于WebDAV的文件: ${e.key}' : '上传了WebDAV的不完整的文件: ${e.key} (本地: $size, WebDAV: ${r.size})');
        } catch (err) {
          errors.add('上传文件失败 ${e.key}: $err');
          log?.call(errors.last);
        }
      }
      for (final r in remoteByName.values) {
        if (keep.containsKey(r.name)) continue;
        try {
          await d.remove(remotePath(dir, r.name));
          deleted++;
          log?.call('删除了WebDAV中不存在于本地的文件: ${r.name}');
        } catch (err) {
          errors.add('删除WebDAV文件失败 ${r.name}: $err');
          log?.call(errors.last);
        }
      }
      log?.call('同步完成，删除了 $deleted 个WebDAV文件，上传了 $uploaded 个本地文件');
      st.lastSyncTime = _now();
      await save(st);
      log?.call('同步时间已更新: ${st.lastSyncTime}');
      return CloudBooksReport(uploaded, deleted, errors);
    } finally {
      _syncing = false;
    }
  }

  static String _now() {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// 0xfb024c: fetches the file of [book] from the repository into its local place. Throws `找不到对应的WebDAV服务器`,
  /// `当前本地书本不存在或者已被删除` (not in the repository either) or `从云端书仓下载失败: …`.
  static Future<File> download(Book book, {CloudDrive? drive, void Function(String status)? status}) async {
    final st = load();
    CloudDrive d;
    if (drive != null) {
      d = drive;
    } else {
      final srv = await server();
      if (srv == null) throw StateError('找不到对应的WebDAV服务器: ${st.serverId}');
      d = driveOf(srv);
    }
    status?.call('正在连接云端仓库...');
    final f = LocalBookImporter.fileOf(book);
    final name = p.basename(f.path);
    final Uint8List bytes;
    try {
      bytes = await d.read(remotePath(normalizeDir(st.backupDir), name));
    } catch (e) {
      if ('$e'.contains('404')) throw StateError('当前本地书本不存在或者已被删除');
      throw StateError('从云端书仓下载失败: $e');
    }
    if (bytes.isEmpty) throw StateError('当前本地书本不存在或者已被删除');
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.part');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (e2) {
        log?.call('删除未完成文件失败: $e2');
      }
      rethrow;
    }
    return f;
  }

  /// Before a local book opens: its file is fetched from the repository when it is missing here (and a repository is set up).
  /// True when a file was restored.
  static Future<bool> restoreIfMissing(Book book, {void Function(String status)? status}) async {
    if (!isLocal(book) || LocalBookImporter.fileOf(book).existsSync() || !configured) return false;
    await download(book, status: status);
    return true;
  }

  /// 0xf7a764: the start-up run for a signed-in member with a repository; failures are only logged.
  static Future<void> syncAtStartup() async {
    if (!configured || !UserSession.isLoggedIn || !UserSession.isvip) return;
    try {
      await sync();
    } catch (e) {
      debugPrint('同步本地书籍与WebDAV备份时出错: $e');
    }
  }
}
