// pages/read/pages/novel/page.dart — the paged reader: shows the current screen and animates to the previous / next one.
//
// Original: `_ReadPageState` (page.dart, "动画完成处理错误: ") for 左右平移 / 上下平移 / 无动画, `_ReadCoverState` (cover.dart) for 左右覆盖,
// `_FlipPageState` (filp.dart) for 仿真翻页, `_BookPageState` (book.dart) for 模拟翻书 and `_AppleBookPageState` (apple_book.dart) for the
// iOS native curl. One widget drives all of them here: a drag (or [NovelPagerController.turn]) moves an animation from 0 to 1 and the
// mode decides how the current and the neighbouring screen are drawn at that point.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../read/setting/read_setting.dart';
import '../../../../widget/pageflip/page_curl.dart';

class NovelPagerController {
  _NovelPagerState? _state;

  /// Turns one screen forward (1) or back (-1) with the current animation. False when there is nothing in that direction.
  Future<bool> turn(int delta) async => await _state?._turn(delta) ?? false;

  bool get isAnimating => _state?._dir != 0;
}

class NovelPager extends StatefulWidget {
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

  bool get _vertical => widget.mode == TurnMode.verticalSlide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: widget.duration)..addListener(() => setState(() {}));
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(NovelPager old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.duration != widget.duration) _anim.duration = widget.duration;
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _anim.dispose();
    super.dispose();
  }

  void _finish() {
    final d = _dir;
    _dir = 0;
    _anim.value = 0;
    _busy = false;
    if (d != 0) widget.onTurned(d);
  }

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
    setState(() => _dir = delta);
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
  }

  void _dragUpdate(double delta) {
    if (_busy) return;
    _drag += delta;
    if (_dir == 0 && _drag.abs() > 4) {
      final dir = _drag < 0 ? 1 : -1;
      if (!widget.canTurn(dir)) {
        widget.onBlocked?.call(dir);
        _drag = 0;
        _busy = true; // ignore the rest of this drag
        return;
      }
      setState(() => _dir = dir);
    }
    if (_dir != 0 && widget.mode != TurnMode.none) {
      final extent = _vertical ? _size.height : _size.width;
      final p = (-_drag * _dir / (extent <= 0 ? 1 : extent)).clamp(0.0, 1.0);
      _anim.value = p;
    }
  }

  Future<void> _dragEnd(double velocity) async {
    if (_busy) {
      if (_dir == 0) _busy = false;
      return;
    }
    if (_dir == 0) return;
    final forward = -velocity * _dir > 300 || _anim.value > 0.15 || widget.mode == TurnMode.none;
    _busy = true;
    if (widget.mode == TurnMode.none) {
      setState(_finish);
      return;
    }
    try {
      await _anim.animateTo(forward ? 1 : 0, curve: Curves.easeOut);
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (forward) {
        _finish();
      } else {
        _dir = 0;
        _busy = false;
      }
    });
  }

  // ------------------------------------------------------------------ drawing

  Widget _shadowed(Widget child) => DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 12)]),
        child: child,
      );

  Widget _compose(double w, double h) {
    final cur = widget.pageBuilder(0);
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
      case TurnMode.book:
      case TurnMode.appleBook:
        // TODO(asm book.dart / apple_book.dart): 模拟翻书 and the iOS native curl share the simulation effect.
        return _dir == 1
            ? PageCurl(front: cur, under: other, amount: t, paperColor: widget.paperColor)
            : PageCurl(front: other, under: cur, amount: 1 - t, paperColor: widget.paperColor);
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
            ..onStart = _dragStart
            ..onUpdate = ((d) => _dragUpdate(d.delta.dy))
            ..onEnd = ((d) => _dragEnd(d.velocity.pixelsPerSecond.dy)),
        );
      } else {
        gestures[HorizontalDragGestureRecognizer] = GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(),
          (r) => r
            ..onStart = _dragStart
            ..onUpdate = ((d) => _dragUpdate(d.delta.dx))
            ..onEnd = ((d) => _dragEnd(d.velocity.pixelsPerSecond.dx)),
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
