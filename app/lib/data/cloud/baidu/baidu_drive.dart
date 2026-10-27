// data/cloud/baidu/baidu_drive.dart — Baidu Pan drive (original: OAuth device-code login, `xpan` file API, token refresh;
// 0x11130fc / 0xd8a39c). This build cannot ship the app's Baidu client credentials (they belong to the original developer and are
// not reproduced), so the drive is a shell: every call fails with [unsupported]. The UI (baidu_auth_dialog.dart) keeps its strings.
import 'dart:typed_data';

import '../../../models/webdavserver.dart';
import '../cloud_drive.dart';

class BaiduDrive extends CloudDrive {
  static const String unsupported = '当前版本不支持百度网盘（需要开发者应用凭证）';
  final WebDavServer server;
  BaiduDrive(this.server);

  Never _no() => throw const CloudDriveException(unsupported);

  @override
  Future<void> ping() async => _no();
  @override
  Future<List<CloudFile>> list(String path) async => _no();
  @override
  Future<Uint8List> read(String path, {void Function(int count, int total)? onProgress}) async => _no();
  @override
  Future<void> write(String path, Uint8List data, {void Function(int count, int total)? onProgress}) async => _no();
  @override
  Future<void> mkdir(String path) async => _no();
  @override
  Future<void> remove(String path) async => _no();
  @override
  Future<void> rename(String from, String to) async => _no();
}
