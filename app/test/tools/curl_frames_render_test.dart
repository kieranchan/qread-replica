// Renders frames of the 模拟翻书 corner curl to PNG files so the look (shadows, the back of the paper, the first frames of a backward
// turn) can be inspected on the host without a phone. A tool, not a check: runs only with CURL_FRAMES=1, writes to CURL_OUT (default
// build/curl_frames). Each frame is drawn twice — from the live widgets (the pager's first frames) and from a picture of the page —
// and the mean difference between the two is printed: a visible "flash" when the pager switches from one to the other shows there.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newread/pages/read/pages/novel/views/battery_painter.dart';
import 'package:newread/widget/bookfx/book_painter.dart';

const _paper = Color(0xFFF2EEE4);
const _w = 440.0, _h = 956.0;

Widget _page(String tag, Color paper) => Container(
      color: paper,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFF222222), fontSize: 18, height: 1.8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('第$tag章 测试页面', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          for (var i = 0; i < 11; i++) Text('这是第$tag页的第${i + 1}行正文，用来观察翻页时纸张背面与阴影的样子。'),
          const Spacer(),
          const Text('00:31                      1/8                      95% ▭ 充电中', style: TextStyle(fontSize: 12)),
        ]),
      ),
    );

void main() {
  final enabled = Platform.environment['CURL_FRAMES'] == '1';

  testWidgets('render curl frames to PNG', (tester) async {
    final out = Directory(Platform.environment['CURL_OUT'] ?? 'build/curl_frames')..createSync(recursive: true);
    tester.view.physicalSize = const Size(_w * 2, _h * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // the turns to look at: name, lifted corner, touch points
    const corner = Offset(_w, _h);
    final back = [for (final t in [0.0, 0.01, 0.03, 0.06, 0.12, 0.25, 0.5, 0.75, 0.95]) Offset.lerp(const Offset(-_w, _h), corner, Curves.easeOut.transform(t))!];
    final fwd = [for (final t in [0.0, 0.05, 0.15, 0.3, 0.5, 0.7, 0.9, 0.99]) Offset.lerp(const Offset(_w - 1, _h - 1), const Offset(-_w, _h), Curves.easeOut.transform(t))!];
    final diag = [for (final t in [0.1, 0.3, 0.5, 0.7]) Offset.lerp(const Offset(_w - 1, _h - 1), const Offset(-_w * 0.4, _h * 0.55), t)!];
    final sets = <String, (Offset, List<Offset>)>{'back': (corner, back), 'fwd': (corner, fwd), 'diag': (corner, diag)};

    final report = StringBuffer();
    await tester.runAsync(() async {
      Future<ui.Image> shoot(GlobalKey key, double ratio) async {
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final ro = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        return ro.toImage(pixelRatio: ratio);
      }

      Future<void> save(ui.Image img, String name) async {
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
      }

      Future<double> meanDiff(ui.Image a, ui.Image b) async {
        final x = (await a.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final y = (await b.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        var sum = 0;
        final n = x.lengthInBytes;
        for (var i = 0; i < n; i++) {
          sum += (x.getUint8(i) - y.getUint8(i)).abs();
        }
        return sum / n;
      }

      // the picture of the front page, as the pager takes it
      final pageKey = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: pageKey, child: _page('A', _paper))));
      final pageImg = await shoot(pageKey, 2);

      for (final e in sets.entries) {
        final (f, touches) = e.value;
        for (var i = 0; i < touches.length; i++) {
          final a = touches[i];
          final liveKey = GlobalKey(), imgKey = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            home: RepaintBoundary(key: liveKey, child: BookCurl(front: _page('A', _paper), under: _page('B', _paper), touch: a, corner: f, paperColor: _paper)),
          ));
          final live = await shoot(liveKey, 2); // device pixels, as on the phone: the picture path maps 1:1 there
          await tester.pumpWidget(MaterialApp(
            home: RepaintBoundary(
              key: imgKey,
              child: BookCurl(front: _page('A', _paper), under: _page('B', _paper), frontImage: pageImg, touch: a, corner: f, paperColor: _paper),
            ),
          ));
          final pic = await shoot(imgKey, 2);
          final name = '${e.key}_${i.toString().padLeft(2, '0')}';
          await save(live, '${name}_live');
          await save(pic, '${name}_pic');
          final d = await meanDiff(live, pic);
          report.writeln('$name touch=(${a.dx.toStringAsFixed(1)}, ${a.dy.toStringAsFixed(1)}) live-vs-picture mean diff ${d.toStringAsFixed(2)}');
          live.dispose();
          pic.dispose();
        }
      }
      pageImg.dispose();
      File('${out.path}/report.txt').writeAsStringSync(report.toString());
    });
    // ignore: avoid_print
    print(report);
  }, skip: !enabled);

  testWidgets('render the footer battery glyph variants to PNG', (tester) async {
    final out = Directory(Platform.environment['CURL_OUT'] ?? 'build/curl_frames')..createSync(recursive: true);
    tester.view.physicalSize = const Size(_w * 2, _h * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    const color = Color(0xFF4A4036);
    Widget row(double fs, int? level, bool charging, {bool inside = false}) {
      final style = TextStyle(fontSize: fs, color: color, height: 1);
      final g = BatteryPainter.sizeFor(fs);
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('fs=$fs ', style: style),
          if (!inside && level != null) Text('$level%', style: style),
          if (!inside && level != null) const SizedBox(width: 3),
          CustomPaint(size: g, painter: BatteryPainter(level: level, color: color, charging: charging, percentInside: inside)),
          if (charging) Text(' 充电中', style: style),
        ]),
      );
    }

    await tester.runAsync(() async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Container(
            color: _paper,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              row(12, 95, true),
              row(12, 95, false),
              row(12, 50, false),
              row(12, 15, false),
              row(12, 15, true),
              row(12, null, false),
              row(12, 95, false, inside: true),
              row(18, 95, true),
              row(18, 62, false, inside: true),
              row(25, 40, false),
            ]),
          ),
        ),
      ));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 6);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${out.path}/battery.png').writeAsBytesSync(bd!.buffer.asUint8List());
      img.dispose();
    });
  }, skip: !enabled);
}
