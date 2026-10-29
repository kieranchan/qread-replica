// 仿真翻页(IOS原生): the Dart side of the native page view (pages/read/pages/novel/apple_book.dart) against a fake platform view and a
// mocked channel: pictures of the three screens go out, turns reported by the view move the position, taps reach the reader's tap
// zones, and the controller's turns become native animations.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/apple_book.dart';
import 'package:newread/pages/read/pages/novel/page.dart';

const int _viewId = 7;
const String _channel = 'com.newread/apple_book_7';

/// Stands in for the UiKitView: reports itself created after the first frame.
class _FakeView extends StatefulWidget {
  final void Function(int id) onCreated;
  const _FakeView(this.onCreated);
  @override
  State<_FakeView> createState() => _FakeViewState();
}

class _FakeViewState extends State<_FakeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCreated(_viewId));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// A five-page book around [AppleBookPager].
class _Book extends StatefulWidget {
  final NovelPagerController controller;
  final List<int> turned;
  final List<int> blocked;
  final List<(Offset, Size)> taps;
  const _Book({required this.controller, required this.turned, required this.blocked, required this.taps});
  @override
  State<_Book> createState() => _BookState();
}

class _BookState extends State<_Book> {
  int index = 2;
  static const int pages = 5;

  @override
  Widget build(BuildContext context) => AppleBookPager(
        controller: widget.controller,
        paperColor: const Color(0xFFEEEEEE),
        pageBuilder: (d) => ColoredBox(
          color: Colors.primaries[(index + d) % Colors.primaries.length],
          child: Center(child: Text('page ${index + d}', style: const TextStyle(fontSize: 30))),
        ),
        canTurn: (d) => index + d >= 0 && index + d < pages,
        onTurned: (d) => setState(() {
          index += d;
          widget.turned.add(d);
        }),
        onBlocked: widget.blocked.add,
        onTap: (local, size) => widget.taps.add((local, size)),
      );
}

/// A picture message: raw RGBA of width x height device pixels.
bool _isPic(Object? v) {
  if (v is! Map) return false;
  final w = v['width'], h = v['height'], b = v['bytes'];
  return w is int && h is int && w > 0 && h > 0 && b is Uint8List && b.length == w * h * 4;
}

Map<Object?, Object?> _args(MethodCall c) => Map<Object?, Object?>.from(c.arguments as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  Future<void> fromNative(String method, Map<String, Object?> args) async {
    await messenger.handlePlatformMessage(_channel, const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});
  }

  /// Lets the picture round trips (toImage / png, each an engine hop) and the channel calls happen: real-time slices with frames in
  /// between, until [until] holds (or 60 rounds).
  Future<void> settle(WidgetTester t, [bool Function()? until]) async {
    for (var i = 0; i < 60; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 10));
      if (until != null && until()) return;
    }
    if (until != null) fail('condition not reached; calls: ${calls.map((c) => c.method).toList()}');
  }

  bool sentPics() => calls.any((c) => c.method == 'updateTextures');

  setUp(() {
    calls = [];
    AppleBookPager.platformView = (params, onCreated) => _FakeView(onCreated);
    messenger.setMockMethodCallHandler(MethodChannel(_channel), (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(MethodChannel(_channel), null);
  });

  testWidgets('pictures of the three screens reach the view; a reported turn moves the position and refreshes the neighbours', (t) async {
    final controller = NovelPagerController();
    final turned = <int>[], blocked = <int>[], taps = <(Offset, Size)>[];
    await t.pumpWidget(MaterialApp(home: _Book(controller: controller, turned: turned, blocked: blocked, taps: taps)));
    await settle(t, sentPics);
    expect(AppleBookPager.qaTapHook, isNotNull);
    // the first run sends all three pictures
    final first = _args(calls.firstWhere((c) => c.method == 'updateTextures'));
    expect(first.keys.toSet(), {'prev', 'cur', 'next'});
    expect(first.values.every(_isPic), isTrue);
    expect(controller.driver, isNotNull);

    // the view finished a forward curl: it shifted its own pictures, only the new next page is sent
    calls.clear();
    await fromNative('pageTurned', {'delta': 1});
    await settle(t, sentPics);
    expect(turned, [1]);
    expect(find.text('page 3'), findsOneWidget);
    final after = calls.where((c) => c.method == 'updateTextures').map(_args).toList();
    expect(after.length, 1);
    expect(after.single.keys.toSet(), {'next'});
    expect(_isPic(after.single['next']), isTrue);

    // at the last page there is no next page: the view dropped it itself when it shifted its pictures, so nothing is sent
    calls.clear();
    await fromNative('pageTurned', {'delta': 1});
    await settle(t);
    expect(find.text('page 4'), findsOneWidget);
    expect(turned, [1, 1]);
    expect(calls.where((c) => c.method == 'updateTextures'), isEmpty);
    // a turn past the end is refused before the view is asked
    expect(await controller.turn(1), isFalse);
    expect(blocked, [1]);
    expect(calls.where((c) => c.method == 'animateToNext'), isEmpty);

    // back: the view shifted the other way, the new previous page is sent
    calls.clear();
    await fromNative('pageTurned', {'delta': -1});
    await settle(t, sentPics);
    expect(find.text('page 3'), findsOneWidget);
    final back = calls.where((c) => c.method == 'updateTextures').map(_args).toList();
    expect(back.single.keys.toSet(), {'prev'});
    expect(_isPic(back.single['prev']), isTrue);
  });

  testWidgets('taps go to the reader; the controller turns through the view; blocked turns and missing pages', (t) async {
    final controller = NovelPagerController();
    final turned = <int>[], blocked = <int>[], taps = <(Offset, Size)>[];
    await t.pumpWidget(MaterialApp(home: _Book(controller: controller, turned: turned, blocked: blocked, taps: taps)));
    await settle(t, sentPics);
    await fromNative('tap', {'x': 200.0, 'y': 300.0, 'width': 400.0, 'height': 800.0});
    expect(taps.single, (const Offset(200, 300), const Size(400, 800)));
    // the QA driver's way in (global position -> the pager's own coordinates)
    final box = t.renderObject<RenderBox>(find.byType(AppleBookPager));
    AppleBookPager.qaTapHook!(box.localToGlobal(const Offset(30, 40)));
    expect(taps.last.$1, const Offset(30, 40));
    expect(taps.last.$2, box.size);

    calls.clear();
    expect(await controller.turn(1), isTrue);
    expect(calls.map((c) => c.method), contains('animateToNext'));
    expect(controller.isAnimating, isTrue);
    await fromNative('pageTurned', {'delta': 1});
    await settle(t);
    expect(controller.isAnimating, isFalse);
    expect(turned, [1]);

    expect(await controller.turn(-1), isTrue);
    expect(calls.map((c) => c.method), contains('animateToPrevious'));
    // the view had no picture: the position still moves, without the animation
    await fromNative('blocked', {'delta': -1});
    await settle(t);
    expect(turned, [1, -1]);
    expect(blocked, isEmpty);

    // beyond the book
    final b = _BookState.pages;
    for (var i = 0; i < b; i++) {
      await fromNative('pageTurned', {'delta': 1});
      await settle(t);
    }
    expect(find.text('page ${b - 1}'), findsOneWidget);
    expect(await controller.turn(1), isFalse);
    expect(blocked, [1]);
  });
}
