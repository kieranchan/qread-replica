// pages/read/pages/novel/page.dart — the paged reader: shows the current screen and animates to the previous / next one.
//
// Original: `_ReadPageState` (page.dart, "动画完成处理错误: ") for 左右平移 / 上下平移 / 无动画, `_ReadCoverState` (cover.dart) for 左右覆盖,
// `_FlipPageState` (filp.dart) for 仿真翻页 — a picture of the page rolled like a cylinder by `PageFlipEffect` — and `_BookPageState`
// (book.dart) for 模拟翻书 — the page corner follows the finger (`PaperPoint`, `BookCurl`). The iOS native curl of `_AppleBookPageState`
// (apple_book.dart, a UIKit page view) is `AppleBookPager` in apple_book.dart; off iOS that mode uses the 模拟翻书 corner curl here.
//
// One widget drives all modes: a drag (or [NovelPagerController.turn]) moves an animation from 0 to 1 and the mode decides how the
// current and the neighbouring screen are drawn at that point; in the corner-curl modes the touch point itself is animated.
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../../../read/setting/read_setting.dart';
import '../../../../widget/bookfx/book_painter.dart';
import '../../../../widget/bookfx/model/paper_point.dart';
import '../../../../widget/pageflip/effects/flip_effect.dart';

/// What a pager offers the [NovelPagerController]: this Flutter pager, or the native iOS page view (apple_book.dart).
abstract class PagerDriver {
  Future<bool> turn(int delta);
  bool get isAnimating;
}

class NovelPagerController {
  _NovelPagerState? _state;

  /// Set by a pager other than [NovelPager] (the 仿真翻页(IOS原生) view) while it is on screen.
  PagerDriver? driver;

  /// Turns one screen forward (1) or back (-1) with the current animation. False when there is nothing in that direction.
  Future<bool> turn(int delta) async {
    final d = driver;
    if (d != null) return d.turn(delta);
    return await _state?._turn(delta) ?? false;
  }

  bool get isAnimating => driver?.isAnimating ?? (_state?._dir != 0);

  /// 模拟翻书: the idle pictures of the current / previous page are ready (tests).
  @visibleForTesting
  bool get idlePicturesReady => _state?._idlePicturesReady ?? false;

  /// 模拟翻书: the running turn draws from a picture (tests).
  @visibleForTesting
  bool get turnUsesPicture => _state?._flipImage != null;
}

class NovelPager extends StatefulWidget {
  /// Logs the frames of every 仿真翻页 / 模拟翻书 turn (`[curl] …`; on the phone `syslog live -pn Runner`).
  static bool verbose = true;

  final int mode;
  final Duration duration;

  /// The screen at [delta] (-1 previous, 0 current, 1 next); only called for deltas where [canTurn] is true (and 0).
  final Widget Function(int delta) pageBuilder;
  final bool Function(int delta) canTurn;
  final void Function(int delta) onTurned;

  /// A turn was requested where there is no page (start / end of the book or the neighbour is still loading).
  final void Function(int delta)? onBlocked;
  final void Function(Offset local, Size size)? onTap;

  /// Vertical drags on horizontal modes (pull down for a bookmark, pull up to leave), reported with the total distance on release.
  final void Function(double dy)? onVerticalPull;
  final void Function(double dy)? onVerticalPullUpdate;
  final NovelPagerController? controller;
  final Color paperColor;

  const NovelPager({
    super.key,
    required this.mode,
    required this.pageBuilder,
    required this.canTurn,
    required this.onTurned,
    this.duration = const Duration(milliseconds: 300),
    this.onBlocked,
    this.onTap,
    this.onVerticalPull,
    this.onVerticalPullUpdate,
    this.controller,
    this.paperColor = const Color(0xFFF2EEE4),
  });

  @override
  State<NovelPager> createState() => _NovelPagerState();
}

class _NovelPagerState extends State<NovelPager> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  int _dir = 0;
  double _drag = 0;
  double _vdrag = 0;
  Size _size = Size.zero;
  bool _busy = false;

  // corner curl (模拟翻书): touch point a, lifted corner f, the animation runs a from [_from] to [_to]
  Offset? _touch;
  Offset _corner = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  Offset _down = Offset.zero;
  bool _horizontal = true;

  // 仿真翻页: picture of the page that rolls; 模拟翻书: picture of the page whose corner is lifted
  final GlobalKey _curKey = GlobalKey(debugLabel: 'flip-cur');
  final GlobalKey _prevKey = GlobalKey(debugLabel: 'flip-prev');
  final GlobalKey _frontKey = GlobalKey(debugLabel: 'curl-front');
  ui.Image? _flipImage;
  int _captureFor = 0;

  // frame timing of a turn (`[curl] …` in the log) when [NovelPager.verbose]: the engine reports frame timings in batches, about
  // once a second, so every turn is a time window and the frames inside it are summed up when a later batch arrives
  final List<(int start, int end)> _turnWindows = [];
  final Map<int, List<FrameTiming>> _turnFrames = {};
  int _turnStartedAt = 0;
  TimingsCallback? _timings;

  /// The paper colour of the lifted page, read from its picture (the back of the paper is tinted with it, not with the theme's
  /// background colour: a textured paper is not that colour).
  Color? _paperOfPage;

  // 模拟翻书 pictures taken while the pager is idle: the current page (lifted by a forward turn) and the previous page (it comes in on
  // a backward turn; rendered underneath the opaque current page for that purpose). A turn then starts straight from a picture —
  // nothing is rebuilt or photographed in its first frame, which is what made every turn start with a visible "refresh" (the
  // Android original draws from bitmaps and has none of it; owner, 2026-10-30).
  ui.Image? _curPic;
  ui.Image? _prevPic;
  int _idleGen = 0;
  bool _idleDirty = true;


  bool get _vertical => widget.mode == TurnMode.verticalSlide;
  bool get _bookMode => widget.mode == TurnMode.book || widget.mode == TurnMode.appleBook;
  bool get _flipMode => widget.mode == TurnMode.simulation;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: widget.duration)..addListener(_tick);
    widget.controller?._state = this;
    if (NovelPager.verbose) {
      _timings = _onTimings;
      SchedulerBinding.instance.addTimingsCallback(_timings!);
    }
  }

  /// Sorts the reported frames into the turn windows and logs a window once a later frame shows it is complete: how many frames,
  /// how many over the 120 Hz / 60 Hz budgets, the worst, the average build and raster times.
  void _onTimings(List<FrameTiming> list) {
    if (_turnWindows.isEmpty || list.isEmpty) return;
    var latest = 0;
    for (final f in list) {
      final t = f.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      if (t > latest) latest = t;
      for (final w in _turnWindows) {
        if (t >= w.$1 - 20000 && t <= w.$2) (_turnFrames[w.$1] ??= []).add(f);
      }
    }
    for (final w in List.of(_turnWindows)) {
      if (w.$2 == 0 || latest <= w.$2) continue;
      _turnWindows.remove(w);
      final frames = _turnFrames.remove(w.$1) ?? const [];
      if (frames.isEmpty) continue;
      var over8 = 0, over16 = 0, worst = 0, build = 0, raster = 0;
      for (final f in frames) {
        final t = f.totalSpan.inMicroseconds;
        if (t > 8400) over8++;
        if (t > 16800) over16++;
        if (t > worst) worst = t;
        build += f.buildDuration.inMicroseconds;
        raster += f.rasterDuration.inMicroseconds;
      }
      final n = frames.length;
      debugPrint('[curl] mode ${widget.mode}: ${((w.$2 - w.$1) / 1000).round()} ms, $n frames, $over8 over 8.3 ms, $over16 over 16.7 ms, '
          'worst ${(worst / 1000).toStringAsFixed(1)} ms, avg build ${(build / n / 1000).toStringAsFixed(1)} ms, '
          'avg raster ${(raster / n / 1000).toStringAsFixed(1)} ms');
    }
  }

  void _turnBegan() {
    if (_timings == null) return;
    _turnStartedAt = Timeline.now;
    _turnWindows.add((_turnStartedAt, 0));
  }

  void _turnEnded() {
    if (_timings == null || _turnStartedAt == 0) return;
    final i = _turnWindows.indexWhere((w) => w.$1 == _turnStartedAt);
    if (i >= 0) _turnWindows[i] = (_turnStartedAt, Timeline.now);
    _turnStartedAt = 0;
  }

  void _tick() {
    if (_bookMode && _dir != 0 && !_dragging) _touch = Offset.lerp(_from, _to, Curves.easeOut.transform(_anim.value));
    setState(() {});
  }

  bool _dragging = false;

  @override
  void didUpdateWidget(NovelPager old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.duration != widget.duration) _anim.duration = widget.duration;
    _idleDirty = true; // the pages may have changed
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    if (_timings != null) SchedulerBinding.instance.removeTimingsCallback(_timings!);
    _anim.dispose();
    _flipImage?.dispose();
    _curPic?.dispose();
    _prevPic?.dispose();
    super.dispose();
  }

  void _finish() {
    final d = _dir;
    _dir = 0;
    _turnEnded();
    _anim.value = 0;
    _busy = false;
    _touch = null;
    _dropImage();
    _idleDirty = true;
    if (d != 0) widget.onTurned(d);
  }

  void _cancelled() {
    _dir = 0;
    _turnEnded();
    _busy = false;
    _touch = null;
    _anim.value = 0;
    _dropImage();
    _idleDirty = true;
  }

  void _dropImage() {
    _flipImage?.dispose();
    _flipImage = null;
    _captureFor = 0;
  }

  // ------------------------------------------------------------------ idle pictures (模拟翻书)

  /// Whether both idle pictures that the current position allows are ready (tests).
  bool get _idlePicturesReady => _curPic != null && (_prevPic != null || !widget.canTurn(-1));

  /// Called from an idle build: once per change, one frame after the page was painted, photographs the current page and the
  /// previous one (frames rather than a timer: nothing may stay pending when the pager goes away).
  void _scheduleIdlePictures() {
    if (!_idleDirty) return;
    _idleDirty = false;
    final gen = ++_idleGen;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _idleGen) return;
      SchedulerBinding.instance.scheduleFrame();
      SchedulerBinding.instance.addPostFrameCallback((_) => _takeIdlePictures(gen));
    });
  }

  Future<void> _takeIdlePictures(int gen) async {
    {
      if (!mounted || gen != _idleGen || _dir != 0) return;
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      final front = _frontKey.currentContext?.findRenderObject();
      final cur = front is RenderRepaintBoundary ? await _snap(front, dpr) : null;
      final paper = front is RenderRepaintBoundary && cur != null ? await _paperColorOf(front) : null;
      final prevRo = widget.canTurn(-1) ? _prevKey.currentContext?.findRenderObject() : null;
      final prev = prevRo is RenderRepaintBoundary ? await _snap(prevRo, dpr) : null;
      if (!mounted || gen != _idleGen || _dir != 0) {
        cur?.dispose();
        prev?.dispose();
        return;
      }
      _curPic?.dispose();
      _prevPic?.dispose();
      _curPic = cur;
      _prevPic = prev;
      if (paper != null) _paperOfPage = paper;
    }
  }

  static Future<ui.Image?> _snap(RenderRepaintBoundary ro, double dpr) async {
    try {
      return await ro.toImage(pixelRatio: dpr);
    } catch (_) {
      return null;
    }
  }

  /// 仿真翻页 rolls a picture of the front page, 模拟翻书 lifts the corner of one: taken once the page has been painted (the previous
  /// page appears under the current one for a frame when turning back; the curl is drawn from the live widgets until then) — or,
  /// in 模拟翻书, ready before the turn starts (the idle pictures), in which case the first frame already uses it.
  Future<void> _capture(int dir) async {
    if (!(_flipMode || _bookMode) || _captureFor == dir) return;
    if (_bookMode && _flipImage == null) {
      final ready = dir == 1 ? _curPic : _prevPic;
      if (ready != null) {
        if (dir == 1) {
          _curPic = null;
        } else {
          _prevPic = null;
        }
        _flipImage = ready;
        _captureFor = dir;
        _turnBegan();
        return;
      }
    }
    _captureFor = dir;
    _turnBegan();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _dir != dir) return;
    final key = _bookMode ? _frontKey : (dir == 1 ? _curKey : _prevKey);
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return;
    try {
      final img = await ro.toImage(pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);
      final paper = _bookMode ? await _paperColorOf(ro) : null;
      if (!mounted || _dir != dir || _flipImage != null) {
        img.dispose();
        return;
      }
      setState(() {
        _flipImage = img;
        if (paper != null) _paperOfPage = paper;
      });
    } catch (_) {}
  }

  /// The paper colour of a page: the mean of the lighter half of a tiny picture of it (the text is the darker part).
  static Future<Color?> _paperColorOf(RenderRepaintBoundary ro) async {
    final thumb = await ro.toImage(pixelRatio: 0.04);
    try {
      final bd = await thumb.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      final n = bd.lengthInBytes ~/ 4;
      if (n == 0) return null;
      var lum = 0;
      for (var i = 0; i < n; i++) {
        lum += bd.getUint8(i * 4) + bd.getUint8(i * 4 + 1) + bd.getUint8(i * 4 + 2);
      }
      final mean = lum / n;
      var r = 0, g = 0, b = 0, m = 0;
      for (var i = 0; i < n; i++) {
        final pr = bd.getUint8(i * 4), pg = bd.getUint8(i * 4 + 1), pb = bd.getUint8(i * 4 + 2);
        if (pr + pg + pb < mean) continue;
        r += pr;
        g += pg;
        b += pb;
        m++;
      }
      if (m == 0) return null;
      return Color.fromARGB(255, r ~/ m, g ~/ m, b ~/ m);
    } finally {
      thumb.dispose();
    }
  }

  // ------------------------------------------------------------------ corner curl geometry

  void _startCurl(int dir, {Offset? at}) {
    final w = _size.width, h = _size.height;
    if (dir == 1) {
      final y = (at ?? Offset(w, h)).dy;
      _horizontal = at == null ? false : (y > h / 3 && y < h * 2 / 3);
      _corner = Offset(w, (at != null && y < h / 3) ? 0 : h);
    } else {
      _horizontal = true;
      _corner = Offset(w, h);
    }
  }

  /// The touch point for a finger at [local] (backwards the previous page is pulled in from the left).
  Offset _curlTouch(Offset local) {
    final w = _size.width, h = _size.height;
    if (_dir == -1) return Offset((2 * local.dx - w).clamp(-w, w), h);
    if (_horizontal) return Offset(local.dx.clamp(-w, w), _corner.dy);
    return PaperPoint.constrain(Offset(local.dx.clamp(-w, w - 0.5), local.dy.clamp(0, h)), _corner, _size);
  }

  /// Where the touch point ends: turned (forward: off the left edge; back: flat) or put back.
  Offset _curlTarget(bool complete) {
    final w = _size.width;
    if (_dir == 1) return complete ? Offset(-w, _corner.dy) : _corner;
    return complete ? _corner : Offset(-w, _corner.dy);
  }

  /// 0..1 progress of the curl for the decision on release.
  double get _curlProgress {
    final a = _touch;
    if (a == null) return 0;
    final w = _size.width;
    return _dir == 1 ? ((w - a.dx) / (2 * w)).clamp(0.0, 1.0) : ((a.dx + w) / (2 * w)).clamp(0.0, 1.0);
  }

  Future<bool> _animateCurl(Offset to) async {
    _from = _touch ?? _from;
    _to = to;
    _anim.value = 0;
    try {
      await _anim.animateTo(1);
    } on TickerCanceled {
      return false;
    }
    return mounted;
  }

  // ------------------------------------------------------------------ turns

  Future<bool> _turn(int delta) async {
    if (_busy) return false;
    if (!widget.canTurn(delta)) {
      widget.onBlocked?.call(delta);
      return false;
    }
    if (widget.mode == TurnMode.none || _size.width <= 0) {
      widget.onTurned(delta);
      return true;
    }
    _busy = true;
    if (_bookMode) {
      setState(() {
        _dir = delta;
        _startCurl(delta);
        final w = _size.width, h = _size.height;
        _touch = delta == 1 ? Offset(w - 1, h - 1) : Offset(-w, h);
      });
      _capture(delta);
      if (!await _animateCurl(_curlTarget(true))) return false;
      setState(_finish);
      return true;
    }
    setState(() => _dir = delta);
    _capture(delta);
    try {
      await _anim.animateTo(1, curve: Curves.easeOut);
    } on TickerCanceled {
      return false;
    }
    if (!mounted) return false;
    setState(_finish);
    return true;
  }

  // ------------------------------------------------------------------ gestures

  void _dragStart(DragStartDetails d) {
    if (_busy) return;
    _drag = 0;
    _down = d.localPosition;
    _dragging = true;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_busy) return;
    final delta = _vertical ? d.delta.dy : d.delta.dx;
    _drag += delta;
    if (_dir == 0 && _drag.abs() > 4) {
      final dir = _drag < 0 ? 1 : -1;
      if (!widget.canTurn(dir)) {
        widget.onBlocked?.call(dir);
        _drag = 0;
        _busy = true; // ignore the rest of this drag
        return;
      }
      setState(() {
        _dir = dir;
        if (_bookMode) _startCurl(dir, at: _down);
      });
      _capture(dir);
    }
    if (_dir == 0 || widget.mode == TurnMode.none) return;
    if (_bookMode) {
      setState(() => _touch = _curlTouch(d.localPosition));
      return;
    }
    final extent = _vertical ? _size.height : _size.width;
    _anim.value = (-_drag * _dir / (extent <= 0 ? 1 : extent)).clamp(0.0, 1.0);
  }

  Future<void> _dragEnd(DragEndDetails d) async {
    _dragging = false;
    if (_busy) {
      if (_dir == 0) _busy = false;
      return;
    }
    if (_dir == 0) return;
    final velocity = _vertical ? d.velocity.pixelsPerSecond.dy : d.velocity.pixelsPerSecond.dx;
    final progress = _bookMode ? _curlProgress : _anim.value;
    final forward = -velocity * _dir > 300 || progress > 0.15 || widget.mode == TurnMode.none;
    _busy = true;
    if (widget.mode == TurnMode.none) {
      setState(_finish);
      return;
    }
    if (_bookMode) {
      if (!await _animateCurl(_curlTarget(forward))) return;
      setState(forward ? _finish : _cancelled);
      return;
    }
    try {
      await _anim.animateTo(forward ? 1 : 0, curve: Curves.easeOut);
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    setState(forward ? _finish : _cancelled);
  }

  // ------------------------------------------------------------------ drawing

  Widget _shadowed(Widget child) => DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 12)]),
        child: child,
      );

  Widget _compose(double w, double h) {
    if (_flipMode && _dir == 0) return RepaintBoundary(key: _curKey, child: widget.pageBuilder(0));
    final cur = widget.pageBuilder(0);
    if (_bookMode && _dir == 0) {
      // idle: the current page in a boundary to photograph, the previous page painted underneath it for the same purpose (pages
      // paint their own paper, so it never shows)
      _scheduleIdlePictures();
      return Stack(fit: StackFit.expand, children: [
        if (widget.canTurn(-1)) RepaintBoundary(key: _prevKey, child: widget.pageBuilder(-1)),
        RepaintBoundary(key: _frontKey, child: cur),
      ]);
    }
    if (_dir == 0) return cur;
    final other = widget.pageBuilder(_dir);
    final t = _anim.value;
    switch (widget.mode) {
      case TurnMode.slide:
        return Stack(fit: StackFit.expand, children: [
          Transform.translate(offset: Offset(-_dir * t * w, 0), child: cur),
          Transform.translate(offset: Offset(_dir * (1 - t) * w, 0), child: other),
        ]);
      case TurnMode.verticalSlide:
        return Stack(fit: StackFit.expand, children: [
          Transform.translate(offset: Offset(0, -_dir * t * h), child: cur),
          Transform.translate(offset: Offset(0, _dir * (1 - t) * h), child: other),
        ]);
      case TurnMode.simulation:
        final front = RepaintBoundary(key: _dir == 1 ? _curKey : _prevKey, child: _dir == 1 ? cur : other);
        final under = _dir == 1 ? other : cur;
        final img = _flipImage;
        if (img == null) {
          // until the picture exists: forward shows the flat page, backward keeps the previous page painted under the current one
          return Stack(fit: StackFit.expand, children: _dir == 1 ? [under, front] : [front, under]);
        }
        final amount = _dir == 1 ? 1 - t : t;
        return Stack(fit: StackFit.expand, children: [
          under,
          Offstage(child: front),
          IgnorePointer(child: CustomPaint(painter: PageFlipEffect(amount: amount, image: img, backgroundColor: widget.paperColor))),
        ]);
      case TurnMode.book:
      case TurnMode.appleBook:
        final a = _touch;
        final front = _dir == 1 ? cur : other;
        final under = _dir == 1 ? other : cur;
        if (a == null) return _dir == 1 ? front : under;
        final img = _flipImage;
        if (img != null) {
          return BookCurl(front: front, under: under, frontImage: img, touch: a, corner: _corner, paperColor: _paperOfPage ?? widget.paperColor);
        }
        // until the picture exists: the live widgets, with a full copy of the front page painted underneath for the picture; the
        // same paper colour as the picture frames will use, else the back of the paper changes tint when the picture arrives
        return Stack(fit: StackFit.expand, children: [
          RepaintBoundary(key: _frontKey, child: front),
          BookCurl(front: front, under: under, touch: a, corner: _corner, paperColor: _paperOfPage ?? widget.paperColor),
        ]);
      case TurnMode.none:
        return cur;
      default: // cover
        return _dir == 1
            ? Stack(fit: StackFit.expand, children: [other, Transform.translate(offset: Offset(-t * w, 0), child: _shadowed(cur))])
            : Stack(fit: StackFit.expand, children: [cur, Transform.translate(offset: Offset(-(1 - t) * w, 0), child: _shadowed(other))]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.biggest != _size) _idleDirty = true;
      _size = box.biggest;
      final content = ClipRect(child: _compose(_size.width, _size.height));
      final gestures = <Type, GestureRecognizerFactory>{
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (r) => r.onTapUp = (d) {
            if (!_busy) widget.onTap?.call(d.localPosition, _size);
          },
        ),
      };
      if (_vertical) {
        gestures[VerticalDragGestureRecognizer] = GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer(),
          (r) => r
            ..dragStartBehavior = DragStartBehavior.down
            ..onStart = _dragStart
            ..onUpdate = _dragUpdate
            ..onEnd = _dragEnd,
        );
      } else if (_bookMode) {
        // the corner follows the finger in every direction
        gestures[PanGestureRecognizer] = GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
          () => PanGestureRecognizer(),
          (r) => r
            ..dragStartBehavior = DragStartBehavior.down
            ..onStart = _dragStart
            ..onUpdate = _dragUpdate
            ..onEnd = _dragEnd,
        );
      } else {
        gestures[HorizontalDragGestureRecognizer] = GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(),
          (r) => r
            ..dragStartBehavior = DragStartBehavior.down
            ..onStart = _dragStart
            ..onUpdate = _dragUpdate
            ..onEnd = _dragEnd,
        );
        if (widget.onVerticalPull != null) {
          gestures[VerticalDragGestureRecognizer] = GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer(),
            (r) => r
              ..onStart = ((_) => _vdrag = 0)
              ..onUpdate = ((d) {
                _vdrag += d.delta.dy;
                widget.onVerticalPullUpdate?.call(_vdrag);
              })
              ..onEnd = ((_) {
                widget.onVerticalPull?.call(_vdrag);
                _vdrag = 0;
              }),
          );
        }
      }
      return RawGestureDetector(behavior: HitTestBehavior.opaque, gestures: gestures, child: content);
    });
  }
}
