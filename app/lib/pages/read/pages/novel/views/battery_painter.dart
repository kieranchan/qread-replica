// pages/read/pages/novel/views/battery_painter.dart — the battery glyph of the reader's status line (original `BatteryPainter`, a
// CustomPainter: outline, cap and a fill proportional to the level; "充电中" is shown next to it while charging).
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

  @override
  void paint(Canvas canvas, Size size) {
    final capW = size.width * 0.08;
    final body = Rect.fromLTWH(0, 0, size.width - capW, size.height);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(RRect.fromRectAndRadius(body.deflate(0.5), const Radius.circular(2)), stroke);
    final cap = Rect.fromLTWH(size.width - capW, size.height * 0.3, capW, size.height * 0.4);
    canvas.drawRRect(RRect.fromRectAndRadius(cap, const Radius.circular(1)), Paint()..color = color);
    final l = level;
    if (l == null) return;
    final inner = body.deflate(2);
    if (percentInside) {
      final tp = TextPainter(
        text: TextSpan(text: '$l', style: TextStyle(color: color, fontSize: body.height * 0.75, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(body.center.dx - tp.width / 2, body.center.dy - tp.height / 2));
      tp.dispose();
      return;
    }
    final w = inner.width * (l.clamp(0, 100) / 100);
    final fill = Paint()..color = (l <= 20 && !charging) ? Colors.red : color;
    canvas.drawRect(Rect.fromLTWH(inner.left, inner.top, w, inner.height), fill);
  }

  @override
  bool shouldRepaint(BatteryPainter old) =>
      old.level != level || old.color != color || old.charging != charging || old.percentInside != percentInside;
}

/// Battery state for the status line: battery_plus on a device (tests replace [read]; null = unknown).
abstract class ReaderBattery {
  static Future<({int level, bool charging})?> Function() read = _plugin;

  static Future<({int level, bool charging})?> _plugin() async {
    final b = Battery();
    final level = await b.batteryLevel;
    final state = await b.batteryState;
    return (level: level, charging: state == BatteryState.charging);
  }
}

class BatteryIcon extends StatefulWidget {
  final Color color;
  final double height;

  /// 内置百分比电池 (the level inside the glyph).
  final bool percentInside;

  /// 外置百分比电池: the "level%" text before the glyph in this style (0x6339a0).
  final TextStyle? percentText;

  const BatteryIcon({super.key, required this.color, this.height = 10, this.percentInside = false, this.percentText});

  @override
  State<BatteryIcon> createState() => _BatteryIconState();
}

class _BatteryIconState extends State<BatteryIcon> {
  int? _level;
  bool _charging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await ReaderBattery.read();
      if (!mounted || b == null) return;
      setState(() {
        _level = b.level;
        _charging = b.charging;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pt = widget.percentText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pt != null && _level != null) Text('$_level%', style: pt),
        if (pt != null && _level != null) const SizedBox(width: 2),
        CustomPaint(
          size: Size(widget.height * 2.2, widget.height),
          painter: BatteryPainter(level: _level, color: widget.color, charging: _charging, percentInside: widget.percentInside),
        ),
        if (_charging) Text(' 充电中', style: pt ?? TextStyle(fontSize: widget.height, color: widget.color)),
      ],
    );
  }
}
