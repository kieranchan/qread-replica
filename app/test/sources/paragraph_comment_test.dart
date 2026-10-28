// 段评 of 时光源: the `<img src>` conventions (dp: bubbles, `,{json}` with js / headers, data: images), tapping an image runs its
// js in the source page, the bubble store handlers showsvg / getsvg / addsvg (0xea5444 / 0x2273b0) and the reader side (bubble
// size, the drawn bubble).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart' show SvgPicture;
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/cloud_api.dart';
import 'package:newread/data/source.dart';
import 'package:newread/data/svg.dart';
import 'package:newread/data/user.dart';
import 'package:newread/pages/read/pages/novel/content.dart';
import 'package:newread/pages/read/pages/novel_view.dart';
import 'package:newread/pages/setting/choose_svg.dart';
import 'package:newread/read/model/line.dart';
import 'package:newread/read/model/page.dart';
import 'package:newread/read/setting/read_layout_style.dart';
import 'package:newread/storage/storage.dart';
import 'package:newread/util/source/baswebview.dart';
import 'package:newread/util/source/image_meta.dart';
import 'package:newread/util/source/inapp_engine.dart';
import 'package:newread/util/source/js_engine.dart';
import 'package:newread/util/source/run.dart';
import 'package:newread/util/source/source.dart';

import '../support/env.dart';
import 'support.dart';
import 'time_source_support.dart';

class _Cloud implements CloudApi {
  final String md5;
  final String json;
  _Cloud(this.md5, this.json);
  @override
  Future<String> getItemMd5(String item) async => item == 'svg' ? md5 : '';
  @override
  Future<String> getItemJson(String item) async => item == 'svg' ? json : '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const String _sourceName = '段评源';

Future<void> _addSource() async {
  await Sourcedata.load();
  await Sources.add({'bookSourceUrl': 'https://dp.test', 'bookSourceName': _sourceName, 'html': fixture('time_source.html')});
}

void main() {
  late TestDevice dev;
  setUp(() async {
    dev = await freshArea();
    FakeSourceEngine.created.clear();
    SourceJsEngine.create = FakeSourceEngine.new;
    WebCookies.push = (_) async {};
    WebCookies.pull = (_) async {};
    WebCookies.pullAll = () async {};
    SourceUi.resetForTests();
    ParagraphComments.activeSource = null;
    UserSession.isvip = false;
    UserSession.cloudtheme = false;
  });
  tearDown(() async {
    await SourceRun.clear();
    dev.delete();
  });

  test('image src conventions: dp bubbles, ,{json} metadata (double or single quotes), data: images', () {
    final dp = ImageMeta.parse('dp:99+,{"js":"showCmt(\'https://s.test/c?a=1\',\'番茄\')"}');
    expect(dp.isDp, isTrue);
    expect(dp.dpText, '99+');
    expect(dp.js, "showCmt('https://s.test/c?a=1','番茄')");

    final svg = base64Encode(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'));
    final data = ImageMeta.parse('data:image/svg+xml;base64,$svg,{"js":"chapter_review(\'x\')"}');
    expect(data.url, 'data:image/svg+xml;base64,$svg');
    expect(data.isSvgData, isTrue);
    expect(utf8.decode(data.dataBytes!), contains('<svg'));
    expect(data.js, "chapter_review('x')");

    final net = ImageMeta.parse("http://img.test/a.png,{'headers':{'a':'b'},'imageDecode':true}");
    expect(net.url, 'http://img.test/a.png');
    expect(net.headers, {'a': 'b'});
    expect(net.imageDecode, isTrue);
    expect(net.js, isEmpty);

    final plain = ImageMeta.parse('http://img.test/a,b.png');
    expect(plain.url, 'http://img.test/a,b.png');
    expect(ImageMeta.hex(const Color(0xFF102030)), '#102030');
  });

  test('a dp bubble is the chosen bubble with the text colour and the count', () async {
    await Svg.load();
    await Storage.setString('svg', '2');
    final s = ImageMeta.parse('dp:7').dpSvg(const Color(0xFFAA0000));
    expect(s, contains('#aa0000'));
    expect(s, contains('>7<'));
    expect(s, isNot(contains(r'$color')));
    expect(s, startsWith(Svg.desvgs[2].svg.substring(0, 20)));
  });

  test('tapping an image with js runs it in the page of the open book\'s source', () async {
    await _addSource();
    ParagraphComments.activeSource = () => 'https://dp.test';
    expect(await ParagraphComments.click('checkin()'), isTrue);
    final page = FakeSourceEngine.created.single.page!;
    expect(page.calls.single, contains('checkin()'));
    expect(await ParagraphComments.click('checkin()', sourceUrl: 'https://unknown.test'), isFalse);
    expect(await ParagraphComments.click(''), isFalse);
  });

  group('bubble handlers', () {
    late FakeSourceEngine e;
    final chosen = <String>[];
    setUp(() {
      chosen.clear();
      e = FakeSourceEngine(const SourceJsEngineOptions());
      SourceHandlers.register(e, const BaseSource(bookSourceUrl: 'https://src.test'));
      SourceUi.chooseSvg = (svg) async => chosen.add(svg);
    });

    test('getsvg answers the built-in bubbles for non-members, the stored ones for members', () async {
      final list = await e.callHandler('getsvg') as List;
      expect([for (final m in list) (m as Map)['id']], ['0', '1', '2', '3']);
      await Svg.load();
      await Svg.clear();
      await Svg.put('mine', '<svg/>');
      UserSession.isvip = true;
      expect(await e.callHandler('getsvg'), [
        {'id': 'mine', 'svg': '<svg/>'},
      ]);
    });

    test('showsvg / addsvg open the chooser; with cloud themes on a changed cloud list replaces the local one first', () async {
      await e.callHandler('showsvg');
      await e.callHandler('addsvg', ['<svg id="new"/>']);
      expect(chosen, ['', '<svg id="new"/>']);

      await Svg.load();
      UserSession.cloudtheme = true;
      defaultCloudApi = _Cloud('m1', jsonEncode([
        {'id': 'c1', 'svg': '<svg c/>'},
      ]));
      addTearDown(() => defaultCloudApi = const UserApiCloud());
      await e.callHandler('showsvg');
      expect([for (final s in Svg.svgs) s.id], ['c1']);
      expect(Storage.getString(PrefKeys.svgmd5), 'm1');
      // same md5: nothing pulled again
      await Svg.put('local', '<svg/>');
      await e.callHandler('showsvg');
      expect(Svg.svgs.length, 2);
    });
  });

  testWidgets('the bubble chooser opened with a page bubble starts its editor with that code (members)', (t) async {
    UserSession.isvip = true;
    await t.runAsync(() => Svg.load());
    await t.pumpWidget(const MaterialApp(home: ChooseSvgPage(svg: '<svg id="from-page"/>')));
    for (var i = 0; i < 10 && find.text('添加气泡').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.text('添加气泡'), findsOneWidget);
    expect(find.text('<svg id="from-page"/>'), findsOneWidget);
  });

  test('reader: a bubble is about one character big', () async {
    expect(await NovelViewState.imageSize('dp:3', fontSize: 18), const Size(24, 18));
  });

  testWidgets('reader: a dp image is drawn as the bubble and a tap runs its js', (t) async {
    await t.runAsync(_addSource);
    ParagraphComments.activeSource = () => 'https://dp.test';
    final img = Content(
      lines: [
        Line(clines: [CLine(type: CLineType.image, style: CLineStyle.image, href: 'dp:5,{"js":"checkin()"}')]),
      ],
      height: 18,
      type: CLineType.image,
      line: 1,
    );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageBody(page: PageText(contents: [img]), style: const ReadLayoutStyle(), textColor: Colors.black, width: 300, chapterIndex: 0),
      ),
    ));
    expect(find.byType(SvgPicture), findsOneWidget);
    await t.tap(find.byType(SvgPicture));
    final ran = <String>[];
    await t.runAsync(() async {
      for (var i = 0; i < 50 && FakeSourceEngine.created.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final page = FakeSourceEngine.created.single;
      for (var i = 0; i < 50 && (page.page?.calls.isEmpty ?? true); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      ran.addAll(page.page!.calls);
      // the runner's idle sweeper was started inside the test zone
      await SourceRun.clear();
    });
    expect(ran.single, contains('checkin()'));
  });
}
