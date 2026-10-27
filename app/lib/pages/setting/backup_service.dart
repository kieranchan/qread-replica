// pages/setting/backup_service.dart — the local backup / restore of backup_page.dart (isolate entries `_performBackupInIsolate`
// 0x1020e6c and `_performRestoreInIsolate` 0x101e8c0, driver 0x101fda4 / 0x101e06c).
//
// Backup: `<root>/backup/<backupName>_<yyyyMMddHHmmss>.zip` holding `settings.json` (the prefs dump, `Storage.dumpPrefs`) and data
// directories. Three sets, chosen by the isolate flags:
//   full (完整备份):            bookcache2 bookrule bookmark bookai book_reading_time books cache audio2 covers covers_cache fonts epub
//                              images item high reading_time tab_icons themes background_music
//   isquick (快速备份):          book_reading_time bookmark books fonts epub high images item tab_icons themes background_music
//   isquick2 (自动备份):         item
// The list of backups is the file-store key `backup` (JSON list of `BackupItem {id, name, date, size, path}`); failures show
// `压缩并保存失败: …` / `备份失败：…`.
// Restore: unzip into `<root>/restore_temp`, require `settings.json` and `item/` (`备份文件错误：缺少必要的settings.json或item目录`),
// restore the prefs, replace each directory of the backup, then the app reloads (`即将重启应用`).
// WebDAV: a backup zip can be uploaded to / downloaded from a network drive (data/cloud), folder [webdavDirKey].
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../common/app_dirs.dart';
import '../../data/cloud/cloud_drive.dart';
import '../../data/list_store.dart';
import '../../models/backup.dart';
import '../../models/webdavserver.dart';
import '../../storage/storage.dart';

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

abstract class BackupService {
  static const String listKey = 'backup';
  static const String autoBackupNumKey = 'autoBackupNum';
  static const String webdavDirKey = 'backupWebdavDir';
  static const String defaultWebdavDir = '/qread_backup/';

  static const List<String> fullDirs = AppDirs.backupDirs;
  static const List<String> quickDirs = [
    'book_reading_time', 'bookmark', 'books', 'fonts', 'epub', 'high', 'images', 'item', 'tab_icons', 'themes', 'background_music',
  ];
  static const List<String> autoDirs = ['item'];

  /// Called after a restore so the app reloads its state (the original restarts). The lead wires the real reload.
  static Future<void> Function() onRestored = () async {};

  static final ListStore<BackupItem> store = ListStore<BackupItem>('backup', fromJson: BackupItem.fromJson, toJson: (b) => b.toJson(), label: '备份');

  static Future<List<BackupItem>> list() async {
    final items = await store.load(force: true);
    // drop entries whose file vanished
    final alive = items.where((b) => File(b.path).existsSync()).toList();
    if (alive.length != items.length) {
      await store.run((l) => l
        ..clear()
        ..addAll(alive));
    }
    return List.of(store.items);
  }

  static String _stamp(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}${d.second.toString().padLeft(2, '0')}';

  /// Creates a backup and registers it. Returns the new item.
  static Future<BackupItem> create({String name = '备份', bool isquick = false, bool isquick2 = false}) async {
    final now = DateTime.now();
    final folder = await AppDirs.ensure('backup');
    final params = <String, dynamic>{
      'backupName': name.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_'),
      'backupFolder': folder.path,
      'documentsPath': AppDirs.root.path,
      'backupId': newId(),
      'timestamp': _stamp(now),
      'settings': Storage.dumpPrefs(),
      'isquick': isquick,
      'isquick2': isquick2,
    };
    final r = await Isolate.run(() => performBackup(params));
    if (r['success'] != true) throw BackupException('${r['error'] ?? '未知错误'}');
    final item = BackupItem.fromJson(Map<String, dynamic>.from(r['backupItem'] as Map));
    await store.run((l) => l.insert(0, item));
    return item;
  }

  /// `_performBackupInIsolate` (0x1020e6c); plain data in and out so it runs in an isolate.
  static Future<Map<String, dynamic>> performBackup(Map<String, dynamic> a) async {
    try {
      final docs = a['documentsPath'] as String;
      final fileName = '${a['backupName']}_${a['timestamp']}.zip';
      final path = p.join(a['backupFolder'] as String, fileName);
      final dirs = a['isquick2'] == true ? autoDirs : (a['isquick'] == true ? quickDirs : fullDirs);
      final enc = ZipFileEncoder();
      enc.create(path);
      try {
        enc.addArchiveFile(ArchiveFile.string('settings.json', jsonEncode(a['settings'])));
        for (final d in dirs.toSet()) {
          final dir = Directory(p.join(docs, d));
          if (dir.existsSync()) await enc.addDirectory(dir, includeDirName: true);
        }
      } finally {
        await enc.close();
      }
      final size = File(path).lengthSync();
      return {
        'success': true,
        'backupItem': {'id': a['backupId'], 'name': a['backupName'], 'date': DateTime.now().toIso8601String(), 'size': '$size', 'path': path},
      };
    } catch (e) {
      return {'success': false, 'error': '压缩并保存失败: $e'};
    }
  }

  /// Restores a backup zip. Throws [BackupException] with the original messages.
  static Future<void> restore(String zipPath) async {
    final temp = Directory(p.join(AppDirs.root.path, AppDirs.restoreTemp));
    final r = await Isolate.run(() => performRestore({'backupFilePath': zipPath, 'appDocPath': temp.path}));
    if (r['success'] != true) throw BackupException('恢复备份失败：${r['error'] ?? '未知错误'}');
    try {
      final settings = jsonDecode(r['settingsContent'] as String);
      final map = settings is Map && settings['settings'] is Map ? settings['settings'] as Map : settings;
      if (map is Map) await Storage.restorePrefs(Map<String, dynamic>.from(map));
      for (final e in temp.listSync()) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        final target = Directory(p.join(AppDirs.root.path, name));
        if (target.existsSync()) target.deleteSync(recursive: true);
        _copyDir(e, target);
      }
    } finally {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
    await onRestored();
  }

  /// `_performRestoreInIsolate` (0x101e8c0): unzip and check; returns `{success, settingsContent}` or `{success:false, error}`.
  static Future<Map<String, dynamic>> performRestore(Map<String, dynamic> a) async {
    try {
      final out = Directory(a['appDocPath'] as String);
      if (out.existsSync()) out.deleteSync(recursive: true);
      out.createSync(recursive: true);
      final archive = ZipDecoder().decodeBytes(File(a['backupFilePath'] as String).readAsBytesSync());
      var hasSettings = false;
      var hasItem = false;
      String settings = '';
      for (final f in archive.files) {
        final name = f.name.replaceAll('\\', '/');
        if (name == 'settings.json') {
          hasSettings = true;
          settings = utf8.decode(f.content);
          continue;
        }
        if (name.startsWith('item/')) hasItem = true;
        if (name.contains('..')) continue;
        final target = p.join(out.path, name);
        if (!f.isFile) {
          Directory(target).createSync(recursive: true);
        } else {
          File(target)
            ..createSync(recursive: true)
            ..writeAsBytesSync(f.content);
        }
      }
      if (!hasSettings || !hasItem) return {'success': false, 'error': '备份文件错误：缺少必要的settings.json或item目录'};
      return {'success': true, 'settingsContent': settings};
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  static void _copyDir(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final e in from.listSync()) {
      final dest = p.join(to.path, p.basename(e.path));
      if (e is Directory) {
        _copyDir(e, Directory(dest));
      } else if (e is File) {
        e.copySync(dest);
      }
    }
  }

  static Future<void> delete(BackupItem item) async {
    final f = File(item.path);
    if (f.existsSync()) await f.delete();
    await store.run((l) => l.removeWhere((e) => e.id == item.id));
  }

  /// 导入备份: copies a zip into the backup folder and registers it.
  static Future<BackupItem> importZip(File source) async {
    final folder = await AppDirs.ensure('backup');
    var dest = p.join(folder.path, p.basename(source.path));
    if (File(dest).existsSync()) dest = p.join(folder.path, '${p.basenameWithoutExtension(source.path)}_${_stamp(DateTime.now())}.zip');
    await source.copy(dest);
    final item = BackupItem(
      id: newId(),
      name: p.basenameWithoutExtension(source.path),
      date: DateTime.now().toIso8601String(),
      size: '${File(dest).lengthSync()}',
      path: dest,
    );
    await store.run((l) => l.insert(0, item));
    return item;
  }

  /// 自动备份: an `isquick2` backup named `自动备份`, keeping the newest [autoBackupNum] (default 7) automatic ones.
  static Future<BackupItem> autoBackup() async {
    final item = await create(name: '自动备份', isquick2: true);
    final keep = Storage.getInt(autoBackupNumKey, 7).clamp(1, 100);
    final autos = (await list()).where((b) => b.name == '自动备份').toList();
    for (final old in autos.skip(keep)) {
      await delete(old);
    }
    return item;
  }

  static String get webdavDir {
    final d = Storage.getString(webdavDirKey);
    return d.isEmpty ? defaultWebdavDir : (d.endsWith('/') ? d : '$d/');
  }

  /// Uploads a backup zip to [server] under [webdavDir].
  static Future<String> upload(BackupItem item, WebDavServer server, {CloudDrive? drive}) async {
    final d = drive ?? CloudDrive.of(server);
    await d.mkdir(webdavDir);
    final remote = '$webdavDir${p.basename(item.path)}';
    await d.write(remote, await File(item.path).readAsBytes());
    return remote;
  }

  /// The backup zips stored on [server].
  static Future<List<CloudFile>> remoteList(WebDavServer server, {CloudDrive? drive}) async {
    final d = drive ?? CloudDrive.of(server);
    try {
      return (await d.list(webdavDir)).where((f) => !f.isDir && f.name.toLowerCase().endsWith('.zip')).toList();
    } on CloudDriveException {
      return [];
    }
  }

  /// Downloads a remote zip into the backup folder and registers it.
  static Future<BackupItem> download(CloudFile file, WebDavServer server, {CloudDrive? drive}) async {
    final d = drive ?? CloudDrive.of(server);
    final data = await d.read(file.path);
    final folder = await AppDirs.ensure('backup');
    final tmp = File(p.join(folder.path, file.name));
    await tmp.writeAsBytes(data, flush: true);
    final item = BackupItem(id: newId(), name: p.basenameWithoutExtension(file.name), date: DateTime.now().toIso8601String(), size: '${data.length}', path: tmp.path);
    await store.run((l) {
      l.removeWhere((e) => e.path == tmp.path);
      l.insert(0, item);
    });
    return item;
  }
}
