// util/webbook/analyze_rule/js_files.dart - the file natives of rule JavaScript (`java.readFile`, `readTxtFile`, `deleteFile`,
// `unzipFile`, `getTxtInFolder`, `downloadFile`, `getZipStringContent`, `getZipByteArrayContent`), sandboxed like upstream Legado:
// every path is relative to one cache folder (`<documents>/cache/legado`) and may not leave it (`getFile` throws 非法路径).
//
// The original answers `not supported readFile/unzipFile/getTxtInFolder/getZip*` and returns "" for readTxtFile/deleteFile
// (dispatcher 0xd8d538); its downloadFile returns the body text (0x11190f4). The replica follows Legado instead (downloadFile
// stores the file and returns its path) so that sources written for Legado work.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../common/app_dirs.dart';
import '../../http.dart';
import '../../legado/js_bindable.dart';
import 'js_encode_utils.dart';

abstract class JsFiles {
  static Directory? _root;

  /// Tests point the sandbox at a temp folder.
  static set root(Directory d) => _root = d;

  /// `<documents>/cache/legado` (system temp when the app directories are not initialised, e.g. in tools).
  static Directory get root {
    final r = _root ??= AppDirs.hasRoot
        ? Directory(AppDirs.path('cache', 'legado'))
        : Directory(p.join(Directory.systemTemp.path, 'newread_legado'));
    if (!r.existsSync()) r.createSync(recursive: true);
    return r;
  }

  /// Legado `ArchiveUtils.TEMP_FOLDER_NAME`.
  static const String archiveTemp = 'ArchiveTemp';

  /// Legado `getFile(path)`: [path] below the sandbox root; throws for paths that leave it.
  static File getFile(String path) => File(_resolve(path));

  static String _resolve(String path) {
    final base = p.normalize(p.absolute(root.path));
    final rel = path.replaceAll('\\', '/');
    final full = p.normalize(p.join(base, rel.startsWith('/') ? rel.substring(1) : rel));
    if (full != base && !p.isWithin(base, full)) throw JsHostError('非法路径');
    return full;
  }

  static Uint8List? readFile(String path) {
    final f = getFile(path);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  /// Text of a file; the charset is detected (BOM, meta, UTF-8 validity, GB18030) unless [charset] is given.
  static String readTxtFile(String path, [String? charset]) {
    final b = readFile(path);
    if (b == null) return '';
    return AppHttp.decodeBody(b, charset: charset);
  }

  static bool deleteFile(String path) {
    final full = _resolve(path);
    final t = FileSystemEntity.typeSync(full);
    if (t == FileSystemEntityType.notFound) return false;
    if (t == FileSystemEntityType.directory) {
      Directory(full).deleteSync(recursive: true);
    } else {
      File(full).deleteSync();
    }
    return true;
  }

  /// Unpacks the zip at [zipPath] into `ArchiveTemp/<md5_16(file name)>` and returns that relative folder.
  static String unzipFile(String zipPath) {
    if (zipPath.isEmpty) return '';
    final zip = getFile(zipPath);
    final rel = '$archiveTemp/${JsEncodeUtils.md5Encode16(p.basename(zip.path))}';
    final out = Directory(_resolve(rel));
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    for (final f in archive.files) {
      final name = f.name.replaceAll('\\', '/');
      final target = p.normalize(p.join(out.path, name));
      if (!p.isWithin(out.path, target)) continue;
      if (!f.isFile) {
        Directory(target).createSync(recursive: true);
        continue;
      }
      File(target)
        ..createSync(recursive: true)
        ..writeAsBytesSync(f.readBytes() ?? Uint8List(0));
    }
    return rel;
  }

  /// All files of the folder [path] as text (one `\n` between files), then the folder is deleted.
  static String getTxtInFolder(String path) {
    if (path.isEmpty) return '';
    final dir = Directory(_resolve(path));
    if (!dir.existsSync()) return '';
    final files = dir.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    final text = files.map((f) => AppHttp.decodeBody(f.readAsBytesSync())).join('\n');
    dir.deleteSync(recursive: true);
    return text;
  }

  /// Stores a downloaded file as `<md5_16(url)>.<type>` and returns its path relative to the sandbox (`/name.type`).
  static String saveDownload(String url, List<int> bytes, String type) {
    final name = '${JsEncodeUtils.md5Encode16(url)}.$type';
    File(_resolve(name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return '/$name';
  }

  /// Legado `UrlUtil.getSuffix(url, default)`: the extension of the url path (letters/digits, ≤ 5 characters).
  static String suffixOf(String url, [String? fallback]) {
    final u = url.split(RegExp(r'[?#,]')).first;
    final m = RegExp(r'\.([a-zA-Z0-9]{1,5})$').firstMatch(u);
    return m?.group(1) ?? (fallback == null || fallback.isEmpty ? 'ext' : fallback);
  }

  /// The bytes of the entry [path] of the zip [bytes]; null when it is not there.
  static Uint8List? zipEntry(List<int> bytes, String path) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final f in archive.files) {
      if (f.isFile && f.name == path) return f.readBytes();
    }
    return null;
  }
}
