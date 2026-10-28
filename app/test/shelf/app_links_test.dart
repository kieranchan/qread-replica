// AppLinksService: files opened with the app, qread:// links, the 10 s duplicate filter; urlsaveBook's source matching.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/data/replace.dart';
import 'package:newread/data/source.dart';
import 'package:newread/data/txtrule.dart';
import 'package:newread/service/app_links_service.dart';
import 'package:newread/util/toast.dart';
import 'package:newread/widget/book/url_save_book.dart';

import 'support.dart';

void main() {
  late ShelfEnv env;
  setUp(() async {
    env = await shelfEnv();
    await AppLinksService.dispose();
  });
  tearDown(() async {
    await AppLinksService.dispose();
    env.dispose();
  });

  File write(String name, String text) => File('${env.dir.path}/$name')..writeAsStringSync(text);

  test('a TXT opened with the app goes to the shelf; unknown types are refused', () async {
    final f = File('${env.dir.path}/《山居笔记》作者：林间.txt');
    await File('test/fixtures/shelf/sample.txt').copy(f.path);
    await AppLinksService.handle(Uri.file(f.path));
    expect(BookSelfN.books.map((b) => b.name), ['山居笔记']);
    expect(Toast.log, contains('导入成功'));
    await AppLinksService.handle(Uri.file(write('a.doc', 'x').path));
    expect(Toast.log.last, '暂不支持当前格式');
  });

  test('JSON files are imported by content (replace rules, TXT rules); unknown content fails', () async {
    await AppLinksService.handle(Uri.file(write('r.json', '[{"name":"去广告","pattern":"广告","replacement":"","isRegex":false}]').path));
    expect(Toast.log.last, '导入成功（1）');
    expect(ReplaceData.store.items.map((e) => e.name), contains('去广告'));
    await AppLinksService.handle(Uri.file(write('t.json', '[{"name":"章节","rule":"^第.{1,6}章.*"}]').path));
    expect(Toast.log.last, '导入成功（1）');
    expect(Txtruledata.store.items.map((e) => e.name), contains('章节'));
    await AppLinksService.handle(Uri.file(write('x.json', '{"a":1}').path));
    expect(Toast.log.last, '导入失败:Exception: 未知的文件格式');
  });

  test('qread:// links download `src` and import it; the same link within 10 s is ignored; links arrive from the stream', () async {
    final asked = <String>[];
    AppLinksService.download = (url) async {
      asked.add(url);
      return '[{"name":"规则$url","rule":"^第.+章"}]';
    };
    addTearDown(() => AppLinksService.download = (u) async => throw UnimplementedError());
    final links = StreamController<Uri>();
    AppLinksService.linkStream = () => links.stream;
    addTearDown(() => AppLinksService.linkStream = null);
    await AppLinksService.init(null);
    final u = Uri.parse('qread://import/auto?src=https://q.test/rule.json');
    links.add(u);
    links.add(u);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(asked, ['https://q.test/rule.json']);
    expect(Txtruledata.store.items.map((e) => e.name), contains('规则https://q.test/rule.json'));
    await AppLinksService.onLink(Uri.parse('qread://import?src=https://q.test/b.json'));
    expect(asked, hasLength(2));
    await links.close();
  });

  test('urlsaveBook: first enabled local source whose bookUrlPattern matches; backend sources are skipped', () async {
    await Sources.addAll([
      {'bookSourceUrl': 'https://a.test@yuedu', 'bookSourceName': '后端', 'bookUrlPattern': r'https://book\.test/\d+'},
      {'bookSourceUrl': 'https://off.test', 'bookSourceName': '停用', 'enabled': false, 'bookUrlPattern': r'https://book\.test/\d+'},
      {'bookSourceUrl': 'https://b.test', 'bookSourceName': '本地', 'bookUrlPattern': r'https://book\.test/\d+'},
    ]);
    expect(sourceForBookUrl('https://book.test/123')?['bookSourceName'], '本地');
    expect(sourceForBookUrl('https://other.test/1'), isNull);
  });
}
