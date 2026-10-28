// 字典: the four online dictionaries of the original parse their pages (fixtures) into the HTML the sheet shows.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/widget/delayed_selection_area.dart';

String _fx(String name) => File('test/fixtures/reader_ui/dict/$name').readAsStringSync();

void main() {
  final requested = <String>[];
  setUp(() {
    requested.clear();
    OnlineDictionary.fetch = (url) async {
      requested.add(url);
      if (url.contains('bing.com')) return _fx('bing.html');
      if (url.contains('hanyuguoxue')) return _fx('xinhua.html');
      if (url.contains('baidu')) return _fx('baidu.html');
      if (url.contains('dict.cn')) throw const SocketException('offline');
      return _fx('empty.html');
    };
  });

  test('urls and parsing of the original dictionaries', () async {
    final bing = await OnlineDictionary.bing.lookup('apple');
    expect(requested.single, 'https://cn.bing.com/dict/search?q=apple&qs=ds&form=CM');
    expect(bing, contains('<h1><span style="color:red">apple</span></h1>'));
    expect(bing, contains('<span style="color:#7DC475">【n.】</span>苹果；苹果公司'));
    expect(bing, contains('美 [ˈæp(ə)l] 英 [ˈæp(ə)l]'));
    expect(bing, contains('一天一个苹果。'));
    expect(bing, isNot(contains('更多')));
    expect(await OnlineDictionary.xinhua.lookup('苹果'), contains('落叶乔木，果实球形。'));
    expect(requested.last, 'https://www.hanyuguoxue.com/cidian/search?words=%E8%8B%B9%E6%9E%9C');
    expect(await OnlineDictionary.baidu.lookup('苹果'), '<p>苹果 píng guǒ 落叶乔木的果实。</p>');
    expect(await OnlineDictionary.dictcn.lookup('apple'), startsWith('获取海词英文失败：'));
    OnlineDictionary.fetch = (url) async => _fx('empty.html');
    expect(await OnlineDictionary.bing.lookup('zzz'), '未找到解释');
    expect(await OnlineDictionary.xinhua.lookup('zzz'), '未找到解释');
  });

  testWidgets('the sheet shows the result of the selected dictionary', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DictionaryResultWidget(word: 'apple'))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('查询字典：apple'), findsOneWidget);
    expect(find.byType(Html), findsOneWidget);
    await tester.tap(find.text('百度汉语'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(requested.last, contains('dict.baidu.com'));
  });
}
