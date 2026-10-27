// data/cloud/cloud_drive.dart — the network-drive abstraction (`CloudDrive`, `CloudFile` size 0x38; sort closure 0xd8a31c = folders
// first, then by name). Implementations: WebDAV (webdav_drive.dart, also used for CloudDrive2's `/dav`), Baidu Pan and Weiyun
// (shells in this build). [CloudDrive.of] picks the implementation from `WebDavServer.type`.
import 'dart:typed_data';

import '../../models/webdavserver.dart';
import 'baidu/baidu_drive.dart';
import 'webdav_drive.dart';
import 'weiyun/weiyun_drive.dart';

class CloudFile {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? modified;
  final String id;
  const CloudFile({required this.name, required this.path, this.isDir = false, this.size = 0, this.modified, this.id = ''});

  /// Book files the browser can open / import.
  bool get isBook {
    final n = name.toLowerCase();
    return n.endsWith('.txt') || n.endsWith('.epub') || n.endsWith('.mobi') || n.endsWith('.azw3') || n.endsWith('.pdf');
  }
}

/// 0xd8a31c.
int compareCloudFiles(CloudFile a, CloudFile b) {
  if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

class CloudDriveException implements Exception {
  final String message;
  const CloudDriveException(this.message);
  @override
  String toString() => message;
}

abstract class CloudDrive {
  /// Server types stored in `WebDavServer.type` (`''` = WebDAV).
  static const String typeWebdav = 'webdav';
  static const String typeBaidu = 'baidu';
  static const String typeWeiyun = 'weiyun';
  static const String typeCloudDrive2 = 'clouddrive2';

  /// Builds the drive of a stored server.
  static CloudDrive of(WebDavServer s) => switch (s.type_) {
        typeBaidu => BaiduDrive(s),
        typeWeiyun => WeiyunDrive(s),
        _ => WebDavDrive(s),
      };

  Future<void> ping();
  Future<List<CloudFile>> list(String path);
  Future<Uint8List> read(String path, {void Function(int count, int total)? onProgress});
  Future<void> write(String path, Uint8List data, {void Function(int count, int total)? onProgress});
  Future<void> mkdir(String path);
  Future<void> remove(String path);
  Future<void> rename(String from, String to);

  /// Recursive name search below [path] (`输入关键词，搜索当前目录及其所有子目录`); [onDir] reports scanned directories.
  Future<List<CloudFile>> search(String path, String keyword, {void Function(int dirs)? onDir, int maxDirs = 500}) async {
    final out = <CloudFile>[];
    final queue = <String>[path];
    var dirs = 0;
    final k = keyword.toLowerCase();
    while (queue.isNotEmpty && dirs < maxDirs) {
      final d = queue.removeAt(0);
      List<CloudFile> items;
      try {
        items = await list(d);
      } catch (_) {
        continue;
      }
      dirs++;
      onDir?.call(dirs);
      for (final f in items) {
        if (f.name.toLowerCase().contains(k)) out.add(f);
        if (f.isDir) queue.add(f.path);
      }
    }
    return out;
  }
}
