// data/cloud/webdav_drive.dart — `WebDavDrive` (implements CloudDrive over `webdav_client`; entry mapping 0xd8a800 File → CloudFile).
// Used for plain WebDAV servers (群晖、坚果云、Alist …) and for CloudDrive2, whose WebDAV endpoint is `http://host:19798/dav`.
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart' as wd;

import '../../models/webdavserver.dart';
import 'cloud_drive.dart';

class WebDavDrive extends CloudDrive {
  final WebDavServer server;
  late final wd.Client client;

  WebDavDrive(this.server) {
    client = wd.newClient(server.url, user: server.username, password: server.password);
    client.setConnectTimeout(15000);
    client.setSendTimeout(60000);
    client.setReceiveTimeout(60000);
  }

  static String _join(String dir, String name) => dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  /// 0xd8a800.
  static CloudFile toCloudFile(wd.File f, String parent) {
    final name = f.name ?? '';
    var path = f.path ?? _join(parent, name);
    if (f.isDir == true && !path.endsWith('/')) path = '$path/';
    return CloudFile(name: name, path: path, isDir: f.isDir == true, size: f.size ?? 0, modified: f.mTime, id: f.eTag ?? '');
  }

  Never _wrap(Object e) {
    final s = '$e';
    if (s.contains('401')) throw const CloudDriveException('用户名或密码错误');
    throw CloudDriveException(s);
  }

  @override
  Future<void> ping() async {
    try {
      await client.ping();
    } catch (e) {
      _wrap(e);
    }
  }

  @override
  Future<List<CloudFile>> list(String path) async {
    try {
      final items = await client.readDir(path.isEmpty ? '/' : path);
      return [for (final f in items) if ((f.name ?? '').isNotEmpty) toCloudFile(f, path)]..sort(compareCloudFiles);
    } catch (e) {
      _wrap(e);
    }
  }

  @override
  Future<Uint8List> read(String path, {void Function(int count, int total)? onProgress}) async {
    try {
      return Uint8List.fromList(await client.read(path, onProgress: onProgress));
    } catch (e) {
      _wrap(e);
    }
  }

  @override
  Future<void> write(String path, Uint8List data, {void Function(int count, int total)? onProgress}) async {
    try {
      await client.write(path, data, onProgress: onProgress);
    } catch (e) {
      _wrap(e);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    try {
      await client.mkdirAll(path);
    } catch (e) {
      _wrap(e);
    }
  }

  @override
  Future<void> remove(String path) async {
    try {
      await client.removeAll(path);
    } catch (e) {
      _wrap(e);
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    try {
      await client.rename(from, to, true);
    } catch (e) {
      _wrap(e);
    }
  }
}
