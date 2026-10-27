// pages/read/pages/novel/views/battery_painter.dart — the battery glyph of the reader's status line (original `BatteryPainter`, a
// CustomPainter: outline, cap and a fill proportional to the level; "充电中" is shown next to it while charging).
import 'package:flutter/material.dart';

class BatteryPainter extends CustomPainter {
  /// 0..100, null = unknown (drawn as an empty outline).
  final int? level;
  final Color color;
  final bool charging;

  const BatteryPainter({required this.level, required this.color, this.charging = false});

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
    final w = inner.width * (l.clamp(0, 100) / 100);
    final fill = Paint()..color = (l <= 20 && !charging) ? Colors.red : color;
    canvas.drawRect(Rect.fromLTWH(inner.left, inner.top, w, inner.height), fill);
  }

  @override
  bool shouldRepaint(BatteryPainter old) => old.level != level || old.color != color || old.charging != charging;
}

/// Battery state for the status line. No battery plugin is bundled: the lead may point [read] at one (null = unknown).
abstract class ReaderBattery {
  static Future<({int level, bool charging})?> Function() read = () async => null;
}

class BatteryIcon extends StatefulWidget {
  final Color color;
  final double height;

  const BatteryIcon({super.key, required this.color, this.height = 10});

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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(widget.height * 2.2, widget.height),
          painter: BatteryPainter(level: _level, color: widget.color, charging: _charging),
        ),
        if (_charging) Text(' 充电中', style: TextStyle(fontSize: widget.height, color: widget.color)),
      ],
    );
  }
}
