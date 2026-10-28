// Shared setup of the shelf-area widget tests: a temp device (storage root + prefs), the fake engine, a fake file picker, a
// recording Nav.openReader, toasts captured in Toast.log.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:newread/common/nav.dart';
import 'package:newread/data/bookself.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/pages/search/book_search_service.dart';
import 'package:newread/pages/search/fake_book_search_service.dart';
import 'package:newread/read/api/read_file_store.dart';
import 'package:newread/read/api/read_storage_root.dart';
import 'package:newread/read/api/readapi.dart';
import 'package:newread/util/toast.dart';
import 'package:newread/widget/book/book_file_picker.dart';

import '../support/env.dart';

class FakePicker implements BookFilePicker {
  List<File> books = [];
  File? json;
  File? image;

  @override
  Future<List<File>> pickBooks() async => books;

  @override
  Future<File?> pickJson() async => json;

  @override
  Future<File?> pickImage() async => image;
}

class ReaderCall {
  final Book book;
  final int? chapterIndex;
  ReaderCall(this.book, this.chapterIndex);
}

class ShelfEnv {
  final TestDevice device;
  final FakeBookSearchService engine;
  final FakePicker picker = FakePicker();
  final List<ReaderCall> reader = [];

  ShelfEnv(this.device, this.engine);

  Directory get dir => device.dir;

  void dispose() => device.delete();
}

/// The books of test/fixtures/shelf/books.json.
List<Book> fixtureBooks() => [
      for (final e in jsonDecode(File('test/fixtures/shelf/books.json').readAsStringSync()) as List) Book.fromJson(Map<String, dynamic>.from(e as Map)),
    ];

List<BookChapter> chapters(int n, {String prefix = '第'}) => [for (var i = 0; i < n; i++) BookChapter(name: '$prefix${i + 1}章', index: i, chapterId: 'c$i')];

/// Call inside `tester.runAsync` (real file IO).
Future<ShelfEnv> shelfEnv({FakeBookSearchService? engine}) async {
  final d = await newDevice();
  ReadStorageRoot.dir = d.dir;
  ReadIsolate.enabled = false;
  ReadApi.resetCaches();
  Bookdata.autoSync = false;
  Toast.log.clear();
  Toast.sink = (m, e) {};
  final env = ShelfEnv(d, engine ?? FakeBookSearchService());
  BookSearchService.instance = env.engine;
  BookFilePicker.instance = env.picker;
  Nav.openReader = (context, book, {chapterIndex, chapters}) async => env.reader.add(ReaderCall(book, chapterIndex));
  await BookSelfN.load();
  return env;
}

Widget app(Widget home) => GetMaterialApp(home: home);

/// Note for test authors: the data managers keep static `Lock`s whose tail future belongs to the zone of the last call. A write
/// started by a tap runs in the fake-async zone of that test; a later test that takes the same lock waits on a future of a dead
/// zone and hangs. Tests that write through the UI therefore live in their own file (each file runs in its own isolate) and are
/// the last lock users of that file.
Future<ShelfEnv> pumpPage(WidgetTester t, Widget page, {List<Book>? books, FakeBookSearchService? engine}) async {
  late ShelfEnv env;
  await t.runAsync(() async {
    env = await shelfEnv(engine: engine);
    if (books != null) await BookSelfN.addAll(books);
  });
  await t.pumpWidget(app(page));
  await settle(t);
  return env;
}

/// Lets real async work (file IO) started from the fake-async test zone finish: every IO step completes in real time but its
/// continuation only runs on the next pump, so alternate short real waits with pumps.
/// Like [settle], but keeps going until [done] holds (or [timeout] of real time passes), then settles once more.
Future<void> settleUntil(WidgetTester t, bool Function() done, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(end)) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
  await settle(t, rounds: 5);
}

Future<void> settle(WidgetTester t, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 8)));
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 400));
}
