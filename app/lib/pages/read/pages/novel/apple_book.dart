// pages/read/pages/novel/apple_book.dart — 仿真翻页(IOS原生): the original's `_AppleBookPageState` (apple_book.dart). A UIKit page view
// (packages/apple_book_curl: `UIPageViewController` with the page-curl transition) shows pictures of the previous / current / next
// screen; this widget paints the three screens under the native view, takes their pictures and sends them, and the view reports
// finished turns and taps. Original protocol: UiKitView `com.newread/apple_book_view` (0x7bc778), channel
// `com.newread/apple_book_<id>` (0xc6cfdc) with updateCurrentTexture / updateOtherTextures / setCanGoPrevious / animateToNext /
// animateToPrevious and the view's turn callback; the pictures were pixel buffers (`PageTextureEntry`), here PNG bytes.
//
// The finger-following curl and its release are the page view controller's own; a finished curl comes back as `pageTurned {delta}`
// and the position moves then (as `NovelPager.onTurned`). Taps come back as `tap` and go through the reader's tap zones
// (`onTap`), which turn pages with [NovelPagerController.turn] -> `animateToNext` / `animateToPrevious`. Vertical pulls (bookmark,
// leave) and text selection are not available in this mode, as in the original.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:apple_book_curl/apple_book_curl.dart' as curl;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'page.dart' show NovelPagerController, PagerDriver;

class AppleBookPager extends StatefulWidget {
  /// The screen at [delta] (-1 previous, 0 current, 1 next); only called for deltas where [canTurn] is true (and 0).
  final Widget Function(int delta) pageBuilder;
  final bool Function(int delta) canTurn;
  final void Function(int delta) onTurned;
  final void Function(int delta)? onBlocked;
  final void Function(Offset local, Size size)? onTap;
  final NovelPagerController? controller;
  final Color paperColor;

  const AppleBookPager({
    super.key,
    required this.pageBuilder,
    required this.canTurn,
    required this.onTurned,
    this.onBlocked,
    this.onTap,
    this.controller,
    this.paperColor = const Color(0xFFF2EEE4),
  });

  /// Whether the native page view exists on this platform (iOS); tests switch it on with a fake [platformView].
  static bool supported = !kIsWeb && Platform.isIOS;

  /// The native view; tests replace it with a widget that calls [onCreated] itself.
  static Widget Function(Map<String, Object?> params, void Function(int id) onCreated) platformView = (params, onCreated) => UiKitView(
        viewType: curl.viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onCreated,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      );

  /// QA driver (lib/dev/qa_driver.dart): synthetic pointer events never reach the native view, so a tap that lands on it is handed
  /// to the pager here (global position) and goes through [onTap] like a tap the view reports.
  static void Function(Offset global)? qaTapHook;

  @override
  State<AppleBookPager> createState() => _AppleBookPagerState();
}

class _AppleBookPagerState extends State<AppleBookPager> implements PagerDriver {
  final GlobalKey _prevKey = GlobalKey(debugLabel: 'apple-prev');
  final GlobalKey _curKey = GlobalKey(debugLabel: 'apple-cur');
  final GlobalKey _nextKey = GlobalKey(debugLabel: 'apple-next');
  MethodChannel? _channel;
  bool _animating = false;
  Timer? _animTimer;
  bool _syncScheduled = false;
  bool _syncing = false;
  bool _syncAgain = false;

  /// Hashes of the pictures the view holds (previous, current, next); 0 = no page, -1 = nothing sent yet.
  final List<int> _sent = [-1, -1, -1];

  @override
  void initState() {
    super.initState();
    widget.controller?.driver = this;
    AppleBookPager.qaTapHook = _qaTap;
  }

  void _qaTap(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || _animating) return;
    widget.onTap?.call(box.globalToLocal(global), box.size);
  }

  @override
  void didUpdateWidget(AppleBookPager old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?.driver == this) old.controller?.driver = null;
      widget.controller?.driver = this;
    }
    if (old.paperColor != widget.paperColor) unawaited(_channel?.invokeMethod('setPaperColor', {'color': widget.paperColor.toARGB32()}));
    // a rebuild from the reader: the pages may have changed (turned, chapter loaded, settings)
    _scheduleSync();
  }

  @override
  void dispose() {
    if (AppleBookPager.qaTapHook == _qaTap) AppleBookPager.qaTapHook = null;
    if (widget.controller?.driver == this) widget.controller?.driver = null;
    _animTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  // ------------------------------------------------------------------ PagerDriver

  @override
  bool get isAnimating => _animating;

  @override
  Future<bool> turn(int delta) async {
    if (_animating) return false;
    if (!widget.canTurn(delta)) {
      widget.onBlocked?.call(delta);
      return false;
    }
    final c = _channel;
    if (c == null) {
      widget.onTurned(delta);
      return true;
    }
    if (_sent[delta > 0 ? 2 : 0] <= 0) await _scheduleSync(); // the view has no picture of that page yet
    _startAnimating();
    try {
      await c.invokeMethod(delta > 0 ? 'animateToNext' : 'animateToPrevious');
    } catch (e) {
      debugPrint('apple_book animate: $e');
      _stopAnimating();
      widget.onTurned(delta);
    }
    return true;
  }

  void _startAnimating() {
    _animating = true;
    _animTimer?.cancel();
    _animTimer = Timer(const Duration(seconds: 2), () => _animating = false);
  }

  void _stopAnimating() {
    _animating = false;
    _animTimer?.cancel();
    _animTimer = null;
  }

  // ------------------------------------------------------------------ the native view

  void _created(int id) {
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel(curl.channelName(id))..setMethodCallHandler(_onCall);
    _sent.fillRange(0, 3, -1);
    _scheduleSync();
  }

  Future<dynamic> _onCall(MethodCall call) async {
    final args = call.arguments is Map ? Map<Object?, Object?>.from(call.arguments as Map) : const <Object?, Object?>{};
    switch (call.method) {
      case 'pageTurned':
        final delta = (args['delta'] as num?)?.toInt() ?? 0;
        _stopAnimating();
        if (delta == 0 || !mounted || !widget.canTurn(delta)) return null;
        // the view shifted its pictures the same way
        if (delta > 0) {
          _sent[0] = _sent[1];
          _sent[1] = _sent[2];
          _sent[2] = 0;
        } else {
          _sent[2] = _sent[1];
          _sent[1] = _sent[0];
          _sent[0] = 0;
        }
        widget.onTurned(delta);
        _scheduleSync();
        return null;
      case 'blocked':
        final delta = (args['delta'] as num?)?.toInt() ?? 0;
        _stopAnimating();
        if (delta != 0 && mounted && widget.canTurn(delta)) {
          // the view had no picture of that page (not sent yet): turn without the animation and send the pictures again
          widget.onTurned(delta);
          _sent.fillRange(0, 3, -1);
          _scheduleSync();
        } else if (delta != 0) {
          widget.onBlocked?.call(delta);
        }
        return null;
      case 'tap':
        final x = (args['x'] as num?)?.toDouble() ?? 0, y = (args['y'] as num?)?.toDouble() ?? 0;
        final w = (args['width'] as num?)?.toDouble() ?? 0, h = (args['height'] as num?)?.toDouble() ?? 0;
        if (!_animating && mounted) widget.onTap?.call(Offset(x, y), Size(w, h));
        return null;
    }
    return null;
  }

  // ------------------------------------------------------------------ pictures

  Completer<void>? _syncDone;

  /// Takes the pictures after the next frame (so that the screens are painted) and sends what changed; the future completes when
  /// that run (and any run it queued) is over.
  Future<void> _scheduleSync() {
    final done = _syncDone ??= Completer<void>();
    if (!_syncScheduled && _channel != null) {
      _syncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncScheduled = false;
        unawaited(_sync());
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return done.future;
  }

  /// Sends the view the pictures it does not have yet (previous / current / next; null = no page in that direction).
  Future<void> _sync() async {
    final c = _channel;
    if (c == null || !mounted) {
      final done = _syncDone;
      _syncDone = null;
      done?.complete();
      return;
    }
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      final pics = <int, Uint8List?>{};
      for (final d in const [-1, 0, 1]) {
        if (d != 0 && !widget.canTurn(d)) {
          pics[d] = null;
          continue;
        }
        pics[d] = await _capture(d == -1 ? _prevKey : (d == 0 ? _curKey : _nextKey), ratio);
      }
      if (!mounted || _channel == null) return;
      final cur = _hash(pics[0]);
      if (cur != _sent[1] && pics[0] != null) {
        await c.invokeMethod('updateCurrentTexture', {'image': pics[0]});
        _sent[1] = cur;
      }
      final others = <String, Object?>{};
      final prev = _hash(pics[-1]), next = _hash(pics[1]);
      if (prev != _sent[0]) {
        others['prev'] = pics[-1];
        _sent[0] = prev;
      }
      if (next != _sent[2]) {
        others['next'] = pics[1];
        _sent[2] = next;
      }
      if (others.isNotEmpty) await c.invokeMethod('updateOtherTextures', others);
    } catch (e) {
      debugPrint('apple_book sync: $e');
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(_sync());
      } else {
        final done = _syncDone;
        _syncDone = null;
        done?.complete();
      }
    }
  }

  /// PNG of the screen painted under [key] (null when it has no size yet).
  Future<Uint8List?> _capture(GlobalKey key, double ratio) async {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.hasSize || ro.size.isEmpty) return null;
    final img = await ro.toImage(pixelRatio: ratio);
    try {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  }

  /// A cheap fingerprint of a picture (length and sampled bytes); 0 for no picture.
  static int _hash(Uint8List? b) {
    if (b == null || b.isEmpty) return 0;
    var h = b.length;
    final step = b.length < 512 ? 1 : b.length ~/ 512;
    for (var i = 0; i < b.length; i += step) {
      h = (h * 31 + b[i]) & 0x3fffffff;
    }
    return h == 0 ? 1 : h;
  }

  @override
  Widget build(BuildContext context) {
    final params = <String, Object?>{'paperColor': widget.paperColor.toARGB32()};
    return Stack(fit: StackFit.expand, children: [
      // the three screens are painted under the native view so that their pictures can be taken
      RepaintBoundary(key: _prevKey, child: widget.canTurn(-1) ? widget.pageBuilder(-1) : const SizedBox.shrink()),
      RepaintBoundary(key: _nextKey, child: widget.canTurn(1) ? widget.pageBuilder(1) : const SizedBox.shrink()),
      RepaintBoundary(key: _curKey, child: widget.pageBuilder(0)),
      AppleBookPager.platformView(params, _created),
    ]);
  }
}
