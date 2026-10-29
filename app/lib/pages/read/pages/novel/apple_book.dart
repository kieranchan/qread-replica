// pages/read/pages/novel/apple_book.dart — 仿真翻页(IOS原生): the original's `_AppleBookPageState` (apple_book.dart). A UIKit page view
// (packages/apple_book_curl: `UIPageViewController` with the page-curl transition) shows pictures of the previous / current / next
// screen; this widget paints the three screens under the native view, takes their pictures and sends them, and the view reports
// finished turns and taps. Original protocol: UiKitView `com.newread/apple_book_view` (0x7bc778), channel
// `com.newread/apple_book_<id>` (0xc6cfdc) with updateCurrentTexture / updateOtherTextures / setCanGoPrevious / animateToNext /
// animateToPrevious and the view's turn callback; the pictures were pixel buffers (`PageTextureEntry`) — here too: raw RGBA at the
// device pixel ratio (no PNG round trip: encoding and decoding a 1320x2868 page cost hundreds of milliseconds on the main thread
// and was felt as a stutter at the start of every curl).
//
// What is sent and when: only the pictures the view does not hold. After a turn the view shifts its own pictures (the old next
// page is the current one now), so only the new far neighbour is painted and sent; a rebuild from the reader (settings, chapter
// loaded) marks all three. The finger-following curl and its release are the page view controller's own; a finished curl comes
// back as `pageTurned {delta}` and the position moves then (as `NovelPager.onTurned`). Taps come back as `tap` and go through the
// reader's tap zones (`onTap`), which turn pages with [NovelPagerController.turn] -> `animateToNext` / `animateToPrevious`.
// Vertical pulls (bookmark, leave) and text selection are not available in this mode, as in the original.
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

  /// Timing of every picture in the log (`[apple_book] …`), read on the phone with `syslog live -pn Runner`.
  static bool verbose = true;

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

/// A picture of one screen: raw RGBA, [width] x [height] device pixels.
class _Pic {
  final Uint8List bytes;
  final int width;
  final int height;
  final int hash;
  _Pic(this.bytes, this.width, this.height) : hash = _hashOf(bytes);

  Map<String, Object?> toMessage() => {'width': width, 'height': height, 'bytes': bytes};

  /// A cheap fingerprint (length and sampled bytes); never 0 (0 = no picture).
  static int _hashOf(Uint8List b) {
    var h = b.length;
    final step = b.length < 4096 ? 1 : b.length ~/ 4096;
    for (var i = 0; i < b.length; i += step) {
      h = (h * 31 + b[i]) & 0x3fffffff;
    }
    return h == 0 ? 1 : h;
  }
}

class _AppleBookPagerState extends State<AppleBookPager> implements PagerDriver {
  static const List<String> _slotNames = ['prev', 'cur', 'next'];

  final List<GlobalKey> _keys = [GlobalKey(debugLabel: 'apple-prev'), GlobalKey(debugLabel: 'apple-cur'), GlobalKey(debugLabel: 'apple-next')];
  MethodChannel? _channel;
  bool _animating = false;
  Timer? _animTimer;
  bool _syncScheduled = false;
  bool _syncing = false;
  bool _syncAgain = false;
  Completer<void>? _syncDone;

  /// Fingerprints of the pictures the view holds (previous, current, next); 0 = no page there, -1 = nothing sent yet.
  final List<int> _sent = [-1, -1, -1];

  /// Slots whose picture must be taken again.
  final List<bool> _dirty = [true, true, true];

  /// The next rebuild comes from our own `onTurned` (the dirty slots are already set, the others are unchanged).
  bool _turnRebuild = false;

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
    if (_turnRebuild) {
      _turnRebuild = false;
    } else {
      // a rebuild from the reader: the pages may have changed (chapter loaded, settings, jump)
      _dirty.fillRange(0, 3, true);
    }
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
    final slot = delta > 0 ? 2 : 0;
    if (_sent[slot] <= 0) {
      // the view has no picture of that page yet
      _dirty[slot] = true;
      await _scheduleSync();
    }
    _startAnimating();
    try {
      await c.invokeMethod(delta > 0 ? 'animateToNext' : 'animateToPrevious');
    } catch (e) {
      debugPrint('[apple_book] animate: $e');
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
    _dirty.fillRange(0, 3, true);
    _scheduleSync();
  }

  Future<dynamic> _onCall(MethodCall call) async {
    final args = call.arguments is Map ? Map<Object?, Object?>.from(call.arguments as Map) : const <Object?, Object?>{};
    switch (call.method) {
      case 'pageTurned':
        final delta = (args['delta'] as num?)?.toInt() ?? 0;
        _stopAnimating();
        if (delta == 0 || !mounted || !widget.canTurn(delta)) return null;
        // the view shifted its pictures the same way: only the new far neighbour has to be painted
        if (delta > 0) {
          _sent[0] = _sent[1];
          _sent[1] = _sent[2];
          _sent[2] = 0;
          _dirty[2] = true;
        } else {
          _sent[2] = _sent[1];
          _sent[1] = _sent[0];
          _sent[0] = 0;
          _dirty[0] = true;
        }
        _turnRebuild = true;
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
          _dirty.fillRange(0, 3, true);
          _scheduleSync();
        } else if (delta != 0) {
          widget.onBlocked?.call(delta);
        }
        return null;
      case 'log':
        if (AppleBookPager.verbose) debugPrint('[apple_book] ${call.arguments}');
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

  void _finishSync() {
    final done = _syncDone;
    _syncDone = null;
    done?.complete();
  }

  /// Sends the view the pictures of the dirty slots that differ from what it holds (null = no page in that direction).
  Future<void> _sync() async {
    final c = _channel;
    if (c == null || !mounted) {
      _finishSync();
      return;
    }
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      final message = <String, Object?>{};
      for (var i = 0; i < 3; i++) {
        if (!_dirty[i]) continue;
        final d = i - 1;
        _Pic? pic;
        if (d == 0 || widget.canTurn(d)) pic = await _capture(_keys[i], ratio, _slotNames[i]);
        if (!mounted || _channel == null) return;
        _dirty[i] = false;
        final hash = pic?.hash ?? 0;
        if (hash == _sent[i]) continue;
        message[_slotNames[i]] = pic?.toMessage();
        _sent[i] = hash;
      }
      if (message.isNotEmpty) {
        final sw = Stopwatch()..start();
        await c.invokeMethod('updateTextures', message);
        if (AppleBookPager.verbose) debugPrint('[apple_book] sent ${message.keys.join(',')} in ${sw.elapsedMilliseconds} ms');
      }
    } catch (e) {
      debugPrint('[apple_book] sync: $e');
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(_sync());
      } else {
        _finishSync();
      }
    }
  }

  /// The screen painted under [key] as raw RGBA at [ratio] device pixels per logical pixel (null when it has no size yet).
  Future<_Pic?> _capture(GlobalKey key, double ratio, String name) async {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.hasSize || ro.size.isEmpty) return null;
    final sw = Stopwatch()..start();
    final img = await ro.toImage(pixelRatio: ratio);
    final raster = sw.elapsedMilliseconds;
    try {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      if (AppleBookPager.verbose) {
        debugPrint('[apple_book] $name ${img.width}x${img.height} raster $raster ms, read ${sw.elapsedMilliseconds - raster} ms');
      }
      return _Pic(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), img.width, img.height);
    } finally {
      img.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = <String, Object?>{'paperColor': widget.paperColor.toARGB32()};
    return Stack(fit: StackFit.expand, children: [
      // the three screens are painted under the native view so that their pictures can be taken
      RepaintBoundary(key: _keys[0], child: widget.canTurn(-1) ? widget.pageBuilder(-1) : const SizedBox.shrink()),
      RepaintBoundary(key: _keys[2], child: widget.canTurn(1) ? widget.pageBuilder(1) : const SizedBox.shrink()),
      RepaintBoundary(key: _keys[1], child: widget.pageBuilder(0)),
      AppleBookPager.platformView(params, _created),
    ]);
  }
}
