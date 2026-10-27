// Read aloud through a fake ReaderSpeaker: paragraph order (title first), the reader follows the spoken paragraph, pause/resume,
// speed (`readspeed2`), stop timer, the listen bar and the full listen page; "从这行开始朗读" from a selection.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/listen_page.dart';
import 'package:newread/pages/read/read_aloud.dart';
import 'package:newread/pages/read/reader_speaker.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/model/line.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/storage/storage.dart';

import 'support.dart';

void main() {
  test('segmentsOf: title first, one segment per paragraph with chapter offsets', () {
    final rc = ReadChapter(BookChapter(name: '第一章'), '第一章', ChapterContent.fromText('　　甲段。\n\n乙段。'));
    final segs = ReadAloudController.segmentsOf(rc);
    expect(segs.map((s) => s.text), ['第一章', '甲段。', '乙段。']);
    expect(segs[0].start, -1);
    expect(rc.content.text.substring(segs[1].start, segs[1].end), '甲段。');
    expect(ReadAloudController.segmentsOf(rc, withTitle: false).length, 2);
    expect(CLineType.image, 1);
  });

  testWidgets('listen: speaks paragraph by paragraph and the reader follows', (tester) async {
    phoneSize(tester);
    final f = (await tester.runAsync(setUpReader))!;
    final fake = FakeSpeaker();
    ReaderSpeaker.factory = () => fake;
    final s = await openReader(tester, f.book);

    s.startListen();
    await settle(tester, until: () => fake.spoken.isNotEmpty);
    expect(fake.spoken.first, '第一章 开端');
    expect(s.aloud!.active, isTrue);
    expect(find.text('定时'), findsOneWidget); // the listen bar replaced the page footer area

    fake.finish();
    await settle(tester, until: () => fake.spoken.length == 2);
    expect(fake.spoken[1], startsWith('清晨的雾气'));

    // Keep finishing paragraphs until the spoken one is on the next page: the reader turns by itself.
    for (var i = 0; i < 40 && s.pageIndex == 0; i++) {
      fake.finish();
      await settle(tester, max: 2);
    }
    expect(s.pageIndex, greaterThan(0));
    final seg = s.aloud!.current!;
    expect(seg.start, greaterThanOrEqualTo(0));

    // pause / resume / speed / timer
    await tester.tap(find.byTooltip('暂停'));
    await settle(tester, max: 2);
    expect(s.aloud!.paused, isTrue);
    expect(fake.calls.last, 'pause');
    fake.finish(); // completion while paused does not advance
    await settle(tester, max: 2);
    final spokenWhilePaused = fake.spoken.length;
    await tester.tap(find.byTooltip('继续'));
    await settle(tester, max: 2);
    expect(fake.calls.last, 'resume');
    expect(fake.spoken.length, spokenWhilePaused);

    await s.aloud!.setRate(1.5);
    expect(fake.rate, 1.5);
    expect(Storage.getDouble('readspeed2'), 1.5);
    s.aloud!.setTimer(15);
    expect(s.aloud!.timerLeft, isNotNull);
    expect(Storage.getString('listenTimerMinutes'), '15');
    s.aloud!.setTimer(0);
    expect(s.aloud!.timerLeft, isNull);

    // full listen page
    await tester.tap(find.byTooltip('听书'));
    await settle(tester, max: 5);
    expect(find.byType(ListenPage), findsOneWidget);
    expect(find.text('朗读引擎：测试引擎'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await settle(tester, max: 3);
    expect(s.aloud!.active, isFalse);
    expect(fake.calls.last, 'stop');
    await tester.pageBack();
    await settle(tester, max: 20);

    // "从这行开始朗读" from a selection restarts at that paragraph
    await tester.longPress(textBlock(1));
    await settle(tester, max: 5);
    final before = fake.spoken.length;
    await tester.tap(find.text('从这行开始朗读'));
    await settle(tester, until: () => fake.spoken.length > before);
    expect(s.aloud!.active, isTrue);
    expect(fake.spoken.last, isNot('第一章 开端'));
    await s.aloud!.stop();
    await finish(tester);
  });
}
