// Reading-settings tools of 时光 AI 助手: the original's 33 parameter metas, schemas, apply with clamping / unknown keys, and the chat sheet
// running them through an adapter that supports tools.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/ai/chat/chat_agent.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/read/pages/novel/views/ai_chat_sheet.dart';
import 'package:newread/pages/read/pages/novel/views/read_setting_tools.dart';
import 'package:newread/pages/read/reader_ai.dart';
import 'package:newread/read/setting/read_setting.dart';
import 'package:newread/storage/storage.dart';

import '../support/env.dart';

class _ToolAi implements ReaderAi, ReaderAiTools {
  final List<String> toolResults = [];
  final Map<String, dynamic> call;
  final String tool;
  _ToolAi(this.tool, this.call);

  @override
  List<ReaderAiModel> get models => const [ReaderAiModel('m', '模型')];

  @override
  Stream<String> chat(List<Map<String, String>> messages, {String? modelId, bool deep = false}) async* {
    yield '无工具';
  }

  @override
  Stream<String> chatWithTools(List<Map<String, String>> messages, List<ChatTool> tools, {String? modelId, bool deep = false}) async* {
    final t = tools.firstWhere((e) => e.spec.name == tool);
    toolResults.add(await t.run(call));
    yield '已调整';
  }
}

void main() {
  setUp(() async {
    await newDevice();
    UserSession.isvip = true;
  });

  test('metas: 33 parameters, the tool key lists cover them', () {
    expect(readingParams, hasLength(33));
    final s = ReadSetting();
    final tools = ReadSettingApplier(s).tools();
    expect(tools.map((t) => t.spec.name), ['get_reading_settings', 'update_typography', 'update_spacing', 'update_display']);
    final covered = {for (final t in tools.skip(1)) ...(t.spec.parameters['properties'] as Map).keys};
    expect(covered, readingParams.map((m) => m.key).toSet());
    final p = ReadSettingApplier(s, fonts: ['circle']).propertySchema(readingParamsByKey['fontSize']!);
    expect(p, {'type': 'number', 'description': '字号', 'minimum': 10, 'maximum': 55});
    expect(ReadSettingApplier(s).propertySchema(readingParamsByKey['underlineStyle']!)['description'], '划线样式：0=无, 1=实线, 2=点线, 3=虚线, 4=波浪线');
    expect(ReadSettingApplier(s, fonts: ['circle']).propertySchema(readingParamsByKey['fontFamily']!)['description'], '字体，可选字体：default=系统默认, circle');
  });

  test('apply clamps, writes the original keys, reports unknown parameters', () async {
    final s = ReadSetting();
    final a = ReadSettingApplier(s);
    final r = await a.apply({'fontSize': 80, 'lineHeight': 1.5, 'twoColumns': true, 'simplified': 2, 'topSafeDistance': -1, 'foo': 1, 'titleAlign': 9});
    expect(s.fontSize, 55);
    expect(Storage.getString(ReadSetting.fontSizeKey), '55');
    expect(s.lineHeight, 1.5);
    expect(s.ispad, isTrue);
    expect(s.simplified, 2);
    expect(r.changed['fontSize'], {'before': 30.0, 'after': 55.0});
    expect(r.unknown, ['foo', 'titleAlign']);
    expect(r.needRelayout, isTrue);
    final view = await ReadSettingApplier(s).tools()[0].run({
      'keys': ['fontSize', 'pageTurnAnimation'],
    });
    final m = jsonDecode(view) as Map;
    expect(m['settings']['fontSize']['value'], 55.0);
    expect((m['settings']['pageTurnAnimation']['options'] as Map)['5'], '仿真翻页');
    final none = await ReadSettingApplier(s).tools()[1].run({});
    expect(jsonDecode(none), {'error': '没有提供任何要修改的参数'});
    final res = jsonDecode(await ReadSettingApplier(s).tools()[3].run({'showHeader': false, 'bad': 1})) as Map;
    expect(s.showTop, isFalse);
    expect(res['warning'], '未知参数：bad');
    expect(res['changed'], ['显示页眉 true→false']);
  });

  testWidgets('the chat sheet hands the tools to an adapter that supports them', (tester) async {
    final s = ReadSetting();
    final ai = _ToolAi('update_typography', {'fontSize': 22});
    ReaderAi.instance = ai;
    addTearDown(() => ReaderAi.instance = null);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiChatSheet(book: Book(bookUrl: 'b', name: '书'), setting: s))));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '把字调小一点');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(s.fontSize, 22);
    expect(ai.toolResults.single, contains('字号 30.0→22.0'));
    expect(find.textContaining('已调整'), findsOneWidget);
  });
}
