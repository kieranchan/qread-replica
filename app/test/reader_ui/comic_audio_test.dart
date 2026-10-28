// Comic view (image chapters, 上一话 / 下一话, progress) and audio view (fake ReaderAudioPlayer: URL from the chapter text, skip intro,
// next chapter on completion), video shell.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/models/book.dart';
import 'package:newread/models/bookchapter.dart';
import 'package:newread/pages/read/pages/audio_view.dart';
import 'package:newread/pages/read/pages/comic_view.dart';
import 'package:newread/pages/read/read_page.dart';
import 'package:newread/pages/video/video_player_page.dart';
import 'package:newread/read/model/line.dart';
import 'package:newread/read/model/page.dart';
import 'package:newread/read/util/chapter_content.dart';
import 'package:newread/storage/storage.dart';

import 'support.dart';

class _FakePlayer implements ReaderAudioPlayer {
  final List<String> calls = [];
  final _pos = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _done = StreamController<void>.broadcast();
  bool _isPlaying = false;

  void complete() => _done.add(null);

  @override
  Future<Duration?> setUrl(String url, {Map<String, String>? headers}) async {
    calls.add('url $url');
    return const Duration(minutes: 10);
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _playing.add(true);
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _playing.add(false);
    calls.add('pause');
  }

  @override
  Future<void> seek(Duration position) async => calls.add('seek ${position.inSeconds}');
  @override
  Future<void> setSpeed(double speed) async => calls.add('speed $speed');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() async {}
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<void> get completedStream => _done.stream;
  @override
  Duration? get duration => const Duration(minutes: 10);
  @override
  bool get playing => _isPlaying;
}

void main() {
  testWidgets('comic view: images per chapter, next episode, progress', (tester) async {
    phoneSize(tester);
    await tester.runAsync(setUpReader);
    final book = Book(bookUrl: 'comic/1', name: '漫画书', origin: 'loc_book', type_: BookType.comic);
    final chapters = [BookChapter(name: '第1话', index: 0), BookChapter(name: '第2话', index: 1)];
    Future<ChapterContent> loader(BookChapter c) async => ChapterContent.fromBlocks([
          for (var i = 0; i < 3; i++) CalcuPages.image(CLine(type: CLineType.image, href: '/no/such/${c.index}_$i.png')),
        ]);
    await tester.pumpWidget(app(ReadPage(book: book, chapters: chapters, loader: loader)));
    await settle(tester, until: () => find.text('第1话').evaluate().isNotEmpty);
    final s = tester.state<ComicViewState>(find.byType(ComicView));
    expect(s.imageCount, 3);
    await tester.tapAt(const Offset(200, 400));
    await settle(tester, max: 3);
    expect(find.text('下一话'), findsOneWidget);
    expect(find.byKey(const ValueKey('comic_slider_chapter')), findsOneWidget); // 菜单滑动条 按章节 (menuSliderType2 0)
    expect(find.byType(InteractiveViewer), findsNothing); // 双指缩放 off by default
    await tester.tap(find.text('下一话'));
    await settle(tester, until: () => s.chapterIndex == 1 && book.durChapterIndex == 1);
    await finish(tester);
  });

  testWidgets('comic view: 双指缩放 (two) and 按分页 slider (menuSliderType2 1)', (tester) async {
    phoneSize(tester);
    await tester.runAsync(setUpReader);
    await tester.runAsync(() async {
      await Storage.setBool('two', true);
      await Storage.setInt('menuSliderType2', 1);
    });
    final book = Book(bookUrl: 'comic/2', name: '漫画书', origin: 'loc_book', type_: BookType.comic);
    final chapters = [BookChapter(name: '第1话', index: 0)];
    Future<ChapterContent> loader(BookChapter c) async => ChapterContent.fromBlocks([
          for (var i = 0; i < 12; i++) CalcuPages.image(CLine(type: CLineType.image, href: '/no/such/${c.index}_$i.png')),
        ]);
    await tester.pumpWidget(app(ReadPage(book: book, chapters: chapters, loader: loader)));
    await settle(tester, until: () => find.text('第1话').evaluate().isNotEmpty);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final s = tester.state<ComicViewState>(find.byType(ComicView));
    await s.page(1);
    await settle(tester, max: 5);
    await tester.tapAt(const Offset(200, 400));
    await settle(tester, max: 10); // the tap waits for the double-tap (restore zoom) timeout
    expect(find.byKey(const ValueKey('comic_slider_page')), findsWidgets);
    await finish(tester);
  });

  testWidgets('audio view: plays the URL of the chapter, skips the intro, continues with the next chapter', (tester) async {
    phoneSize(tester);
    await tester.runAsync(setUpReader);
    final player = _FakePlayer();
    ReaderAudioPlayer.factory = () => player;
    addTearDown(() => ReaderAudioPlayer.factory = null);
    final book = Book(bookUrl: 'audio/1', name: '有声书', origin: 'loc_book', type_: BookType.audio);
    await Storage.setInt('skipStartTime${book.bookUrl}', 30);
    final chapters = [BookChapter(name: '第1集', index: 0), BookChapter(name: '第2集', index: 1)];
    Future<ChapterContent> loader(BookChapter c) async => ChapterContent.fromText('http://127.0.0.1/a${c.index}.mp3');
    await tester.pumpWidget(app(ReadPage(book: book, chapters: chapters, loader: loader)));
    await settle(tester, until: () => player.calls.contains('play'));
    expect(player.calls, containsAllInOrder(['url http://127.0.0.1/a0.mp3', 'speed 1.0', 'seek 30', 'play']));
    expect(find.text('第1集'), findsWidgets);
    player.complete();
    await settle(tester, until: () => player.calls.contains('url http://127.0.0.1/a1.mp3'));
    final s = tester.state<AudioViewState>(find.byType(AudioView));
    expect(s.chapterIndex, 1);
    await settle(tester, until: () => book.durChapterIndex == 1);
    await finish(tester);
  });

  testWidgets('video player: in-app playback, drag to seek, speed, progress kept per episode', (tester) async {
    await tester.runAsync(setUpReader);
    final fake = _FakeVideo();
    ReaderVideoController.create = (url, headers) => fake;
    addTearDown(() => ReaderVideoController.create = PluginVideoController.new);
    await tester.pumpWidget(app(const VideoPlayerPage(url: 'https://example.com/v.mp4', title: '第1集')));
    await tester.pump();
    await tester.pump();
    expect(fake.calls, ['init', 'play']);
    expect(find.text('第1集'), findsOneWidget);
    final s = tester.state<VideoPlayerPageState>(find.byType(VideoPlayerPage));
    await tester.timedDragFrom(const Offset(200, 300), const Offset(100, 0), const Duration(milliseconds: 300));
    await tester.pump();
    expect(fake.position, const Duration(seconds: 30)); // 10 s + 100 px * 0.2 s
    await s.setSpeed(1.5);
    expect(fake.speed, 1.5);
    await s.toggle();
    expect(fake.calls.last, 'pause');
    await tester.pumpWidget(const SizedBox());
    expect(Storage.getInt(VideoPlayerPage.progressKey('https://example.com/v.mp4')), 30000);

    // a second open resumes there
    final again = _FakeVideo();
    ReaderVideoController.create = (url, headers) => again;
    await tester.pumpWidget(app(const VideoPlayerPage(url: 'https://example.com/v.mp4')));
    await tester.pump();
    await tester.pump();
    expect(again.calls, ['init', 'seek 30000', 'play']);
    await tester.pumpWidget(app(const VideoPlayerPage(url: 'bad url')));
    expect(find.textContaining('无效的视频地址'), findsOneWidget);
  });
}

class _FakeVideo implements ReaderVideoController {
  final List<String> calls = [];
  @override
  Duration position = const Duration(seconds: 10);
  double speed = 1;
  bool playing = false;
  final List<VoidCallback> _ls = [];

  @override
  Future<void> initialize() async => calls.add('init');
  @override
  Future<void> play() async {
    playing = true;
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    playing = false;
    calls.add('pause');
  }

  @override
  Future<void> seekTo(Duration d) async {
    position = d;
    calls.add('seek ${d.inMilliseconds}');
    for (final l in _ls) {
      l();
    }
  }

  @override
  Future<void> setSpeed(double s) async => speed = s;
  @override
  Duration get duration => const Duration(minutes: 20);
  @override
  bool get isPlaying => playing;
  @override
  double get aspectRatio => 16 / 9;
  @override
  Widget view() => const ColoredBox(color: Colors.black);
  @override
  void addListener(VoidCallback l) => _ls.add(l);
  @override
  void removeListener(VoidCallback l) => _ls.remove(l);
  @override
  Future<void> dispose() async {}
}
