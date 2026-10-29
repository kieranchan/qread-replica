// 进度同步确认 (read/util/progress_sync.dart): the comparison with the server's record, the 覆盖 / 跳转 outcomes and the dialog.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_progress_remote.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/read/util/progress_sync.dart';

class _Remote implements ReadProgressRemote {
  final List<String> calls = [];
  RemotePosition? answer;
  Object? error;

  @override
  Future<void> autoPos(Book book, int index, double pos) async => calls.add('autopos $index $pos');

  @override
  Future<void> addReads(Book book) async => calls.add('addreads');

  @override
  Future<RemotePosition?> fetchPos(Book book) async {
    calls.add('getpos');
    if (error != null) throw error!;
    return answer;
  }
}

Book _book({int index = 2, double pos = 0.5, String url = 'https://example.com/book/1'}) =>
    Book(bookUrl: url, name: '测试书', author: 'A', origin: 'https://example.com', durChapterIndex: index, durChapterPos: pos, durChapterTitle: '第三章');

ReadApi _api(Book book, {int chapters = 10}) => ReadApi(
      book,
      chapters: [for (var i = 0; i < chapters; i++) BookChapter(name: '第${i + 1}章', index: i, chapterId: 'c$i')],
      loader: (c) async => ChapterContent.fromText('${c.name}正文'),
    );

void main() {
  late Directory tmp;
  late _Remote remote;
  final log = <String>[];

  setUp(() {
    ReadIsolate.enabled = false;
    tmp = Directory.systemTemp.createTempSync('qread_sync_');
    ReadStorageRoot.dir = tmp;
    ReadApi.resetCaches();
    ReadApi.onProgress = null;
    remote = _Remote();
    ReadApi.remote = remote;
    log.clear();
    ReadApi.log = log.add;
    ProgressSync.reset();
    ProgressSync.deviceId = () => 'this-phone';
  });

  tearDown(() {
    ReadApi.remote = null;
    ReadApi.log = null;
    ProgressSync.deviceId = () => '';
    tmp.deleteSync(recursive: true);
  });

  test('differs: another device at another place; the own record and tiny position drifts do not count', () {
    final b = _book(index: 2, pos: 0.5);
    expect(ProgressSync.differs(b, const RemotePosition(index: 5, pos: 0, appid: 'ipad')), isTrue);
    expect(ProgressSync.differs(b, const RemotePosition(index: 2, pos: 0.9, appid: 'ipad')), isTrue);
    expect(ProgressSync.differs(b, const RemotePosition(index: 2, pos: 0.505, appid: 'ipad')), isFalse);
    expect(ProgressSync.differs(b, const RemotePosition(index: 5, pos: 0, appid: 'this-phone')), isFalse);
    expect(ProgressSync.differs(b, const RemotePosition(index: 5, pos: 0)), isTrue, reason: 'a record without appid (older server) counts');
  });

  test('label: the chapter number is not doubled when the title carries it', () {
    expect(ProgressSync.label(2, '第三章', 0.5), '第3章 第三章  50.0%');
    expect(ProgressSync.label(11, '第12章 黑夜女神', 0.129), '第12章 黑夜女神  12.9%');
    expect(ProgressSync.label(30, '', 0.5), '第31章  50.0%');
  });

  test('fetchDifferent: logs the server record, answers only a different one; errors and local books are silent', () async {
    final api = _api(_book());
    expect(await ProgressSync.fetchDifferent(api), isNull);
    expect(remote.calls, ['getpos']);
    remote.answer = const RemotePosition(index: 2, pos: 0.5, appid: 'ipad');
    expect(await ProgressSync.fetchDifferent(api), isNull);
    expect(log, ['保存服务器记录 : 2, 0.5']);
    remote.answer = const RemotePosition(index: 7, pos: 0.25, appid: 'ipad');
    final p = await ProgressSync.fetchDifferent(api);
    expect(p?.index, 7);
    expect(log.last, '不一致');
    remote.error = StateError('offline');
    expect(await ProgressSync.fetchDifferent(api), isNull);
    expect(log.last, startsWith('获取服务器进度失败'));
    // a local book never asks
    remote.error = null;
    remote.calls.clear();
    final local = _api(_book(url: '/var/books/a.txt')..origin = ReadApi.localOrigin);
    expect(await ProgressSync.fetchDifferent(local), isNull);
    expect(remote.calls, isEmpty);
    // no remote wired: nothing happens
    ReadApi.remote = null;
    expect(await ProgressSync.fetchDifferent(api), isNull);
  });

  test('apply: 覆盖 uploads this device, 跳转 opens the server chapter (clamped) and saves it, 取消 does nothing', () async {
    final api = _api(_book(index: 2, pos: 0.5));
    final jumps = <String>[];
    Future<void> jump(int i, double p) async => jumps.add('$i $p');
    const far = RemotePosition(index: 7, pos: 0.25, appid: 'ipad');
    await ProgressSync.apply(api, null, far, jump: jump);
    expect(remote.calls, isEmpty);
    expect(jumps, isEmpty);

    await ProgressSync.apply(api, ProgressSyncChoice.overwrite, far, jump: jump);
    await Future<void>.delayed(Duration.zero);
    expect(remote.calls, ['autopos 2 0.5']);
    expect(jumps, isEmpty);
    expect(api.book.durChapterIndex, 2);

    remote.calls.clear();
    await ProgressSync.apply(api, ProgressSyncChoice.jump, far, jump: jump);
    await Future<void>.delayed(Duration.zero);
    expect(jumps, ['7 0.25']);
    expect(api.book.durChapterIndex, 7);
    expect(api.book.durChapterPos, 0.25);
    expect(remote.calls.first, 'autopos 7 0.25');

    // a record beyond the catalog opens the last chapter
    remote.calls.clear();
    jumps.clear();
    await ProgressSync.apply(api, ProgressSyncChoice.jump, const RemotePosition(index: 99, pos: 2, appid: 'ipad'), jump: jump);
    expect(jumps, ['9 1.0']);
  });

  testWidgets('dialog: the original texts and the three answers', (tester) async {
    ProgressSyncChoice? result;
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            opened++;
            result = await showDialog<ProgressSyncChoice>(
              context: context,
              builder: (_) => const ProgressSyncDialog(local: '第3章 第三章  50.0%', remote: '第8章 第八章  25.0%'),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('进度同步确认'), findsOneWidget);
    expect(find.text('检测到进度不一致，请选择同步方式：'), findsOneWidget);
    expect(find.text('当前设备进度'), findsOneWidget);
    expect(find.text('云端同步进度'), findsOneWidget);
    expect(find.text('第8章 第八章  25.0%'), findsOneWidget);
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();
    expect(result, ProgressSyncChoice.jump);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖'));
    await tester.pumpAndSettle();
    expect(result, ProgressSyncChoice.overwrite);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(opened, 3);
  });
}
