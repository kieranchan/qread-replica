// Wi-Fi传书 → shelf (ShelfRoutes.importUploadedFile, wired to WiFiPage.importBook by init/wiring.dart): an uploaded TXT lands on the
// shelf as a local book; an unreadable file answers with the error text instead of a false 上传成功.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/common/app_dirs.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/pages/book/shelf_routes.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('qread_wifi_import_');
    SharedPreferences.setMockInitialValues({});
    await Storage.init(prefs: await SharedPreferences.getInstance(), root: tmp);
    AppDirs.root = tmp;
    ReadStorageRoot.dir = tmp;
    await BookSelfN.load();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('an uploaded TXT is imported onto the shelf; a bad file reports the error', () async {
    final books = Directory('${tmp.path}/books')..createSync(recursive: true);
    final f = File('${books.path}/云端仓库测试.txt')..writeAsStringSync('第1章 开始\n\n正文一。\n\n第2章 继续\n\n正文二。\n');
    expect(await ShelfRoutes.importUploadedFile(f), isNull);
    final b = Bookdata.books.where((b) => b.name.contains('云端仓库测试')).toList();
    expect(b.length, 1);
    expect(ReadApi.isLocalBook(b.single), isTrue);
    expect(b.single.bookUrl, 'books/云端仓库测试.txt', reason: 'kept in place, stored relative to the root');
    expect(await ShelfRoutes.importUploadedFile(File('${books.path}/missing.txt')), contains('文件不存在'));
    expect(await ShelfRoutes.importUploadedFile(File('${books.path}/x.xyz')..writeAsStringSync('?')), isNotNull);
  });
}
