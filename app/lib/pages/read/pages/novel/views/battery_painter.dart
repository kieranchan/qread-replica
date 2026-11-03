// pages/read/pages/novel/views/battery_painter.dart — the battery glyph of the reader's status line (original `BatteryPainter`, a
// CustomPainter the footer item builds at `Size(fontSize + 10, fontSize - 1)` (0x6339a0 / 0x633fa8) with the level, the charging
// state and the text colour; "充电中" is shown next to it while charging). The painter's own body is not in the blutter output,
// so the drawing follows the system battery glyph: a rounded outline with a small terminal, the level as a rounded bar inside, red
// when low, a lightning bolt knocked out of the bar while charging.
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

class BatteryPainter extends CustomPainter {
  /// 0..100, null = unknown (drawn as an empty outline).
  final int? level;
  final Color color;
  final bool charging;

  /// 内置百分比电池: the level is written inside the outline.
  final bool percentInside;

  const BatteryPainter({required this.level, required this.color, this.charging = false, this.percentInside = false});

  /// Below this level the bar turns red (unless charging).
  static const int lowLevel = 20;
  static const Color lowColor = Color(0xFFE5484D);

  /// The glyph the original footer asks for: `Size(fontSize + 10, fontSize - 1)`.
  static Size sizeFor(double fontSize) => Size(fontSize + 10, math.max(6, fontSize - 1));

  /// The lightning bolt inside a battery body [r] (a polygon in 0..1 coordinates, scaled to the middle of the body).
  static Path bolt(Rect r) {
    final w = r.height * 0.62, h = r.height * 0.82;
    final o = Offset(r.center.dx - w / 2, r.center.dy - h / 2);
    Offset p(double x, double y) => Offset(o.dx + x * w, o.dy + y * h);
    return Path()
      ..moveTo(p(0.58, 0).dx, p(0.58, 0).dy)
      ..lineTo(p(0.08, 0.58).dx, p(0.08, 0.58).dy)
      ..lineTo(p(0.46, 0.58).dx, p(0.46, 0.58).dy)
      ..lineTo(p(0.4, 1).dx, p(0.4, 1).dy)
      ..lineTo(p(0.92, 0.4).dx, p(0.92, 0.4).dy)
      ..lineTo(p(0.54, 0.4).dx, p(0.54, 0.4).dy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final stroke = (h / 9).clamp(1.0, 1.4);
    final nubW = (h * 0.16).clamp(1.5, 3.0);
    final gap = stroke * 0.5;
    final body = Rect.fromLTWH(0, 0, size.width - nubW - gap, h);
    final outer = Radius.circular(h * 0.27);
    // the terminal on the right, rounded on its outer side
    final nub = Rect.fromLTWH(body.right + gap, h * 0.3, nubW, h * 0.4);
    canvas.drawRRect(
      RRect.fromRectAndCorners(nub, topRight: Radius.circular(nubW), bottomRight: Radius.circular(nubW)),
      Paint()..color = color,
    );
    final l = level;
    if (l != null) {
      final inner = body.deflate(stroke * 1.8);
      if (percentInside) {
        final tp = TextPainter(
          text: TextSpan(text: '$l', style: TextStyle(color: color, fontSize: h * 0.78, height: 1, fontWeight: FontWeight.w500)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(body.center.dx - tp.width / 2, body.center.dy - tp.height / 2));
        tp.dispose();
      } else {
        final frac = l.clamp(0, 100) / 100;
        final barW = math.max(inner.height * 0.35, inner.width * frac);
        final bar = RRect.fromRectAndRadius(Rect.fromLTWH(inner.left, inner.top, barW, inner.height), Radius.circular(math.max(0.5, outer.x - stroke * 1.8)));
        final barColor = (l <= lowLevel && !charging) ? lowColor : color;
        if (charging) {
          // the bolt is cut out of the bar so the page shows through it
          canvas.saveLayer(body, Paint());
          canvas.drawRRect(bar, Paint()..color = barColor);
          canvas.drawPath(bolt(inner), Paint()..blendMode = BlendMode.clear);
          canvas.restore();
        } else {
          canvas.drawRRect(bar, Paint()..color = barColor);
        }
      }
    }
    // the outline last, so nothing paints over it
    canvas.drawRRect(
      RRect.fromRectAndRadius(body.deflate(stroke / 2), outer),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(BatteryPainter old) =>
      old.level != level || old.color != color || old.charging != charging || old.percentInside != percentInside;
}

/// Battery state for the status line: battery_plus on a device (tests replace [read]; null = unknown).
abstract class ReaderBattery {
  static Future<({int level, bool charging})?> Function() read = _plugin;

  /// The last good reading. Every freshly built page starts from it synchronously: the curl builds the page several times per turn
  /// and photographs the first frame, which used to show an empty battery (the plugin answers a few frames later, and its very
  /// first answer on iOS can be -1) on the back of the paper and on the page put back after a cancelled turn (owner, 2026-10-30).
  static ({int level, bool charging})? last;

  /// Asks the plugin and keeps a plausible answer as [last].
  static Future<({int level, bool charging})?> current() async {
    final b = await read();
    if (b != null && b.level >= 0 && b.level <= 100) last = b;
    return last;
  }

  static Future<({int level, bool charging})?> _plugin() async {
    final b = Battery();
    final level = await b.batteryLevel;
    final state = await b.batteryState;
    return (level: level, charging: state == BatteryState.charging);
  }
}

/// How a battery item of the status line is drawn.
enum BatteryIconMode {
  /// 外置百分比电池: `95%` then the glyph.
  outside,

  /// 内置百分比电池: the level inside the glyph.
  inside,

  /// Legado's BatteryView: the level in a thin box with a terminal (`69`).
  box,

  /// Legado 时间+电量: `HH:mm  69` with the box.
  timeBox,

  /// Legado 时间+电量%: `HH:mm 69%`.
  timePercent,

  /// Legado 电量%: `69%`.
  percent,
}

class BatteryIcon extends StatefulWidget {
  final Color color;
  final double height;

  /// Glyph width; the original's `fontSize + 10` when the footer builds it, else 2.2 x the height.
  final double? width;

  /// 内置百分比电池 (the level inside the glyph).
  final bool percentInside;

  /// 外置百分比电池: the "level%" text before the glyph in this style (0x6339a0).
  final TextStyle? percentText;

  final BatteryIconMode mode;

  /// Text style of the Legado modes (12 pt tips in the page's typeface; the box uses 11 pt).
  final TextStyle? textStyle;

  /// `HH:mm` of the time modes (tests pass a fixed one).
  final String Function()? clock;

  const BatteryIcon({
    super.key,
    required this.color,
    this.height = 10,
    this.width,
    this.percentInside = false,
    this.percentText,
    this.mode = BatteryIconMode.outside,
    this.textStyle,
    this.clock,
  });

  @override
  State<BatteryIcon> createState() => _BatteryIconState();
}

/// Legado's battery: the level in a thin rectangle with a short terminal on the right (BatteryView.drawBattery: the box runs
/// 2 dp above and below the text line, the terminal is 2 dp wide and a third of the box high).
class LegadoBatteryBox extends StatelessWidget {
  final int? level;
  final Color color;
  final TextStyle style;
  const LegadoBatteryBox({super.key, required this.level, required this.color, required this.style});

  @override
  Widget build(BuildContext context) {
    final fs = style.fontSize ?? 11;
    final boxH = fs * 1.3 + 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          height: boxH,
          padding: const EdgeInsets.fromLTRB(2, 0, 3, 0),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: color, width: 1)),
          child: Text(level == null ? '--' : '$level', style: style.copyWith(color: color, height: 1.1)),
        ),
        Container(width: 2, height: boxH / 3, color: color),
      ],
    );
  }
}

class _BatteryIconState extends State<BatteryIcon> {
  int? _level = ReaderBattery.last?.level;
  bool _charging = ReaderBattery.last?.charging ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await ReaderBattery.current();
      if (!mounted || b == null || (b.level == _level && b.charging == _charging)) return;
      setState(() {
        _level = b.level;
        _charging = b.charging;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pt = widget.percentText;
    final ts = (widget.textStyle ?? TextStyle(fontSize: widget.height, color: widget.color)).copyWith(color: widget.color);
    final clock = widget.clock ?? _hhmm;
    switch (widget.mode) {
      case BatteryIconMode.box:
        return LegadoBatteryBox(level: _level, color: widget.color, style: ts);
      case BatteryIconMode.timeBox:
        // Legado: `"$time  $level"` with the box around the level
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${clock()}  ', style: ts),
          LegadoBatteryBox(level: _level, color: widget.color, style: ts),
        ]);
      case BatteryIconMode.timePercent:
        return Text(_level == null ? clock() : '${clock()} $_level%', style: ts);
      case BatteryIconMode.percent:
        return Text(_level == null ? '' : '$_level%', style: ts);
      case BatteryIconMode.outside:
      case BatteryIconMode.inside:
        break;
    }
    final inside = widget.percentInside || widget.mode == BatteryIconMode.inside;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pt != null && _level != null && !inside) Text('$_level%', style: pt),
        if (pt != null && _level != null && !inside) const SizedBox(width: 3),
        CustomPaint(
          size: Size(widget.width ?? widget.height * 2.2, widget.height),
          painter: BatteryPainter(level: _level, color: widget.color, charging: _charging, percentInside: inside),
        ),
        if (_charging) Text(' 充电中', style: pt ?? TextStyle(fontSize: widget.height, color: widget.color)),
      ],
    );
  }

  static String _hhmm() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
