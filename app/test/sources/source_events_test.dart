// 事件监听 / 定制按钮 / `@onclick:` of 时光源 (util/source/source_events.dart, the detail page, the intro renderer): which events go
// to the page's `callbackjs(event, book)`, when a consumed event skips the app's action, and intro buttons running js in the page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/source.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/book/book_detail_page.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';
import 'package:newread/pages/search/search_book_page.dart';
import 'package:newread/util/source/baswebview.dart';
import 'package:newread/util/source/inapp_engine.dart';
import 'package:newread/util/source/js_engine.dart';
import 'package:newread/util/source/run.dart';
import 'package:newread/util/source/source.dart';
import 'package:newread/util/source/source_events.dart';
import 'package:newread/widget/book/intro_view.dart';

import '../shelf/support.dart' as shelf;
import '../support/env.dart';
import 'support.dart';
import 'time_source_support.dart';

const String url = 'https://ev.test';

Map<String, dynamic> raw({bool listen = true, bool button = true, bool qread = false}) => {
      'bookSourceUrl': url,
      'bookSourceName': '事件源',
      'html': fixture('time_source.html'),
      'eventListener': listen,
      'customButton': button,
      if (qread) 'isqread': true,
    };

void fakes() {
  FakeSourceEngine.created.clear();
  FakeTimePage.events.clear();
  SourceJsEngine.create = FakeSourceEngine.new;
  WebCookies.push = (_) async {};
  WebCookies.pull = (_) async {};
  WebCookies.pullAll = () async {};
  SourceUi.resetForTests();
}

Future<void> waitFor(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('SourceEvents', () {
    late TestDevice dev;
    setUp(() async {
      dev = await freshArea();
      fakes();
      await Sourcedata.load();
    });
    tearDown(() async {
      await SourceRun.clear();
      dev.delete();
    });

    final book = Book(bookUrl: '$url/book/1', name: '测试书', origin: url);

    test('switches: 事件监听 / 定制按钮 of a 时光源; never for the bound backend or Legado sources', () async {
      await Sources.add(raw());
      expect(SourceEvents.listens(url), isTrue);
      expect(SourceEvents.hasCustomButton(url), isTrue);
      await Sources.add(raw(listen: false, button: false));
      expect(SourceEvents.listens(url), isFalse);
      expect(SourceEvents.hasCustomButton(url), isFalse);
      await Sources.add(raw(qread: true));
      expect(SourceEvents.listens(url), isFalse);
      await Sources.add({'bookSourceUrl': 'https://legado.test', 'bookSourceName': 'L', 'searchUrl': '/s', 'eventListener': true});
      expect(SourceEvents.listens('https://legado.test'), isFalse);
    });

    test('callbackjs(event, book JSON): true consumes; notify / fire only when listening', () async {
      await Sources.add(raw());
      expect(await SourceEvents.notify(SourceEvents.longClickBookName, book), isTrue);
      expect(await SourceEvents.notify(SourceEvents.clickAuthor, book), isFalse);
      SourceEvents.fire(SourceEvents.saveRead, book);
      await waitFor(() => FakeTimePage.events.length == 3);
      expect(FakeTimePage.events, [('longClickBookName', '测试书'), ('clickAuthor', '测试书'), ('saveRead', '测试书')]);

      await Sources.add(raw(listen: false));
      FakeTimePage.events.clear();
      expect(await SourceEvents.notify(SourceEvents.clickAuthor, book), isFalse);
      SourceEvents.fire(SourceEvents.addBookShelf, book);
      // the custom buttons are sent without 事件监听
      expect(await SourceEvents.send(url, SourceEvents.clickCustomButton, book), isFalse);
      await waitFor(() => FakeTimePage.events.isNotEmpty);
      expect(FakeTimePage.events, [('clickCustomButton', '测试书')]);
    });
  });

  testWidgets('intro: a <button> with @onclick: is a button running its js; one without is left out', (t) async {
    final ran = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IntroView(
          intro: '@html:<p>简介</p><button>看评论 @onclick:showCmt(\'a\',\'b\')</button><button>无动作</button>',
          onClickJs: ran.add,
        ),
      ),
    ));
    expect(find.text('看评论'), findsOneWidget);
    expect(find.textContaining('无动作'), findsNothing);
    await t.tap(find.text('看评论'));
    expect(ran, ["showCmt('a','b')"]);
    expect(introButton('x @onclick:a()'), ('x', 'a()'));
    expect(introButton('plain'), isNull);
  });

  testWidgets('detail page: events of name / author / labels, the custom button and intro buttons go to the page', (t) async {
    final book = Book(bookUrl: '$url/book/1', name: '测试书', author: '作者甲', origin: url, kind: '玄幻');
    final engine = FakeBookSearchService(
      library: {
        url: [
          Book(
            bookUrl: book.bookUrl,
            name: book.name,
            author: book.author,
            kind: '玄幻',
            intro: '@html:<p>简介</p><button>签到 @onclick:checkin()</button>',
          ),
        ],
      },
      tocs: {book.bookUrl: shelf.chapters(2)},
    );
    late shelf.ShelfEnv env;
    await t.runAsync(() async {
      env = await shelf.shelfEnv(engine: engine);
      fakes();
      await Sourcedata.load();
      await Sources.add(raw());
      // the runner is started outside the test zone (its idle sweeper is a real timer)
      await (await SourceRun.of(BaseSource.fromJson(raw()))).waitReady();
    });
    addTearDown(env.dispose);
    await t.pumpWidget(shelf.app(BookDetailPage(book: book)));
    await shelf.settle(t);

    Future<void> until(int n) => shelf.settleUntil(t, () => FakeTimePage.events.length >= n, timeout: const Duration(seconds: 5));

    // long press on the name: consumed by the page, so no search page
    await t.longPress(find.byKey(const Key('detail_name')));
    await until(1);
    expect(find.byType(SearchBookPage), findsNothing);
    await t.tap(find.byKey(const Key('detail_author')));
    await until(2);
    await t.tap(find.text('玄幻'));
    await until(3);
    await t.tap(find.byKey(const Key('detail_custom_button')));
    await until(4);
    expect([for (final e in FakeTimePage.events) e.$1], ['longClickBookName', 'clickAuthor', 'clickBookLabel', 'clickCustomButton']);
    expect(FakeTimePage.events.first.$2, '测试书');

    await t.tap(find.text('签到'));
    final page = FakeSourceEngine.created.single.page!;
    await shelf.settleUntil(t, () => page.calls.any((c) => c.contains('checkin()')), timeout: const Duration(seconds: 5));
    expect(page.calls.last, contains('checkin()'));
    await t.runAsync(SourceRun.clear);
  });
}
