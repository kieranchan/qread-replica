// Scroll mode ("上下滚动", `turn` = 4): the list of page bodies, progress while scrolling, the next chapter appended at the end.
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/list.dart';
import 'package:newread/read/setting/read_setting.dart';
import 'package:newread/storage/storage.dart';

import 'support.dart';

void main() {
  testWidgets('scroll mode shows the list and saves the progress while scrolling', (tester) async {
    phoneSize(tester);
    final f = (await tester.runAsync(setUpReader))!;
    await Storage.setInt('turn', TurnMode.scroll);
    final s = await openReader(tester, f.book);
    expect(find.byType(ListPage), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListPage), const Offset(0, -700));
      await settle(tester, max: 3);
    }
    await settle(tester, until: () => s.pageIndex > 0 || s.chapterIndex > 0);
    await settle(tester, until: () => f.book.durChapterPos > 0 || f.book.durChapterIndex > 0);
    // Tap in the middle opens the menus in scroll mode as well.
    await tester.tapAt(const Offset(200, 380));
    await settle(tester, until: () => s.menuVisible);
    await finish(tester);
  });
}
