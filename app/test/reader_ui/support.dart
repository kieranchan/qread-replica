// Shared setup of the reader UI tests: a temporary device (prefs + storage root), the TXT fixture imported as a local book, a fake
// speaker and helpers that let real file IO finish inside widget tests.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/data/fonts.dart';
import 'package:newread/data/ground.dart';
import 'package:newread/data/highlight.dart';
import 'package:newread/data/note_data_n.dart';
import 'package:newread/data/replace.dart';
import 'package:newread/data/txtrule.dart';
import 'package:newread/data/user.dart';
import 'package:newread/models/book.dart';
import 'package:newread/pages/read/pages/novel/content.dart';
import 'package:newread/pages/read/pages/novel_view.dart';
import 'package:newread/pages/read/read_page.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/pages/read/reader_ai.dart';
import 'package:newread/pages/read/reader_speaker.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/read/local_book_importer.dart';
import 'package:newread/util/toast.dart';

import '../support/env.dart';

class ReaderFixture {
  final TestDevice device;
  final Book book;
  final List<BookChapter> chapters;
  ReaderFixture(this.device, this.book, this.chapters);
}

/// Fresh device + the sample TXT imported. Call inside `tester.runAsync` in widget tests.
Future<ReaderFixture> setUpReader({String fixture = 'sample.txt'}) async {
  final device = await newDevice();
  ReadIsolate.enabled = false;
  ReadStorageRoot.dir = device.dir;
  ReadApi.resetCaches();
  ReadApi.onProgress = null;
  ReadApi.remote = null;
  ReadApi.log = null;
  UserSession.isvip = false;
  ReaderSpeaker.factory = null;
  ReaderAi.instance = null;
  Toast.log.clear();
  Toast.sink = (_, _) {};
  // Load the stores here (real zone): their per-key locks must not be first used inside a test's fake-async zone, whose microtasks stop
  // running when that test ends (a later test would wait on them forever).
  await ReplaceData.load();
  await HighlightData.load();
  await NoteDataN.load();
  await Txtruledata.load();
  await Ground.load();
  await FontsData.load();
  final src = File('test/fixtures/reader_ui/$fixture');
  final local = await const LocalBookImporter().import(src);
  return ReaderFixture(device, local.book, local.chapters);
}

/// Lets async IO (real files) and animations progress until [until] holds (or [max] rounds).
Future<void> settle(WidgetTester tester, {bool Function()? until, int max = 80}) async {
  for (var i = 0; i < max; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
    if (until != null && until()) return;
  }
  if (until != null && !until()) fail('condition not reached');
}

/// Unmounts the tree and lets pending file IO of the test finish (static per-key storage locks must not stay held for the next test).
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester, max: 10);
}

void phoneSize(WidgetTester tester, {Size size = const Size(400, 760)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget app(Widget home) => MaterialApp(home: home);

/// Records what it was asked to speak; [finish] plays the role of the engine's completion callback.
class FakeSpeaker extends ReaderSpeaker {
  final List<String> spoken = [];
  final List<String> calls = [];
  double rate = 1;

  void finish() => onDone?.call();

  @override
  String get engineName => '测试引擎';
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    calls.add('speak');
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> setRate(double rate) async => this.rate = rate;
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<List<SpeakerVoice>> voices() async => const [SpeakerVoice('婷婷', 'zh-CN')];
  @override
  Future<void> setVoice(SpeakerVoice voice) async {}
  @override
  Future<void> dispose() async {}
}

/// Answers every chat with a fixed reply split into chunks.
class FakeAi implements ReaderAi {
  final List<List<Map<String, String>>> requests = [];
  String reply;
  FakeAi(this.reply);

  @override
  List<ReaderAiModel> get models => const [ReaderAiModel('m1', '模型一')];

  @override
  Stream<String> chat(List<Map<String, String>> messages, {String? modelId, bool deep = false}) async* {
    requests.add(messages);
    for (var i = 0; i < reply.length; i += 4) {
      yield reply.substring(i, i + 4 > reply.length ? reply.length : i + 4);
    }
  }
}

String md5Of(String s) => ReadFileStore.md5Hex(s);

NovelViewState stateOf(WidgetTester t) => t.state<NovelViewState>(find.byType(NovelView));

/// Opens [book] in a [ReadPage] and waits until the first chapter is laid out.
Future<NovelViewState> openReader(WidgetTester tester, Book book, {int? chapterIndex}) async {
  await tester.pumpWidget(app(ReadPage(book: book, chapterIndex: chapterIndex)));
  try {
    await settle(tester, until: () {
      final s = tester.stateList<NovelViewState>(find.byType(NovelView));
      return s.isNotEmpty && s.first.pageCount > 0;
    });
  } catch (_) {
    final s = tester.stateList<NovelViewState>(find.byType(NovelView));
    // ignore: avoid_print
    print('reader log: ${s.isEmpty ? 'no state' : s.first.logs.join(' | ')}; toasts: ${Toast.log}');
    rethrow;
  }
  return stateOf(tester);
}

/// The [i]-th text block of the page on screen (index 0 is the chapter title on a chapter's first page).
Finder textBlock(int i) => find.descendant(of: find.byType(PageBody), matching: find.byType(RichText)).at(i);
