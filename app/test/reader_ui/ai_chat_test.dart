// The reader's AI chat: member gate, "未配置模型" without a ReaderAi, streamed answers through a fake ReaderAi, sessions stored per book,
// the character library ("提取角色" -> 角色库).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/read/pages/novel/views/ai_character_page.dart';
import 'package:newread/pages/read/pages/novel/views/ai_chat_sheet.dart';
import 'package:newread/pages/read/reader_ai.dart';
import 'package:newread/storage/setting.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';
import 'support.dart';

final Book _book = Book(bookUrl: 'books/ai.txt', name: '斗破', author: '天蚕', origin: 'loc_book');

Widget _host() => app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showAiChatSheet(context, book: _book, chapterTitle: '第一章', chapterText: '萧炎是主角。'),
            child: const Text('open'),
          ),
        ),
      ),
    ));

void main() {
  setUp(() {
    Toast.log.clear();
    Toast.sink = (_, _) {};
    ReaderAi.instance = null;
  });

  testWidgets('member gate, not configured, streamed reply, stored session', (tester) async {
    phoneSize(tester);
    await tester.runAsync(newDevice);
    UserSession.isvip = false;
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(Toast.log, contains('当前功能仅对会员开放'));
    expect(find.text('时光 AI 助手'), findsNothing);

    UserSession.isvip = true;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('时光 AI 助手'), findsOneWidget);
    expect(find.text('未配置模型'), findsOneWidget);
    expect(find.text('请先在模型管理中添加模型'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20)); // dismiss the sheet
    await tester.pumpAndSettle();

    final ai = FakeAi('你好，我是阅读助手。');
    ReaderAi.instance = ai;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '主角是谁？');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('你好，我是阅读助手。'), findsOneWidget);
    expect(ai.requests.single.first['role'], 'system');
    expect(ai.requests.single.first['content'], contains('《斗破》'));
    expect(ai.requests.single.last, {'role': 'user', 'content': '主角是谁？'});
    final sessions = Setting.getAiChatSessions(aiBookKey(_book));
    expect(sessions.single.title, '主角是谁？');
    expect(sessions.single.messages.length, 2);
    UserSession.isvip = false;
  });

  testWidgets('character library: merge from an AI answer, list, empty state', (tester) async {
    phoneSize(tester);
    await tester.runAsync(newDevice);
    const key = 'k1';
    await tester.pumpWidget(app(const AiCharacterPage(bookKey: key)));
    expect(find.textContaining('角色库还是空的'), findsOneWidget);

    final added = mergeCharacters(key, '角色如下：[{"name":"萧炎","gender":1,"personality":"坚韧"},{"name":"药老","gender":0}] 完');
    expect(added, 2);
    expect(mergeCharacters(key, '[{"name":"萧炎"}]'), 0); // already there
    expect(mergeCharacters(key, '没有 JSON'), 0);
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpWidget(app(const AiCharacterPage(bookKey: key)));
    expect(find.text('萧炎（男）'), findsOneWidget);
    expect(find.text('药老（未知）'), findsOneWidget);
    expect(find.text('暂无个性描述'), findsOneWidget);
  });
}
