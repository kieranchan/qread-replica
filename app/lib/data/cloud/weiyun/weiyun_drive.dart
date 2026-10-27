// data/cloud/weiyun/weiyun_drive.dart — Tencent Weiyun drive (original: API Key pasted from the Weiyun authorisation page, header map
// closure 0xf5b70). The Weiyun open API contract is not recoverable from the snapshot, so this build keeps the stored key and the UI
// but every call fails with [unsupported].
import 'dart:typed_data';

import '../../../models/webdavserver.dart';
import '../cloud_drive.dart';

class WeiyunDrive extends CloudDrive {
  static const String unsupported = '当前版本不支持腾讯微云';
  final WebDavServer server;
  WeiyunDrive(this.server);

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
