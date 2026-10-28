// read/util/highlight_bg.dart — background images of highlight rules (original `highlight_apply.dart` 0xf0caec with the editor 0x6513e0:
// 上传背景图 · 拖拽 4 条线划分九宫格 (水平拉伸：拖拽上下横线 / 垂直拉伸：拖拽左右竖线, "左 x% / 右 y%", "上 x% / 下 y%", 重置) · 透明度 · 延展区域,
// images kept as `@high/<file>` (or `@images/<file>`, an http url), the page repainting when one finished loading —
// `ContentPageState._onTextBgImageVersion`). Each matched range is drawn as a nine-patch: the image's centre slice (the four lines,
// in percent) stretches over the text boxes of the range, grown by the 延展区域 padding, at the rule's opacity.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../common/app_dirs.dart';
import 'content_painter.dart';

/// One rule's background image for day or night.
class RuleBgImage {
  final String path;

  /// 0..1 (0 = the default, fully opaque).
  final double opacity;

  /// 延展区域: how far the image reaches beyond the text, left / top / right / bottom in px.
  final EdgeInsets padding;

  /// The nine-patch lines in percent of the image: left, right, top, bottom.
  final List<double> stretch;

  const RuleBgImage(this.path, {this.opacity = 0, this.padding = EdgeInsets.zero, this.stretch = defaultStretch});

  static const List<double> defaultStretch = [30, 30, 30, 30];

  static double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  /// From the rule's JSON fields (`dayBgImagePadding` [l, t, r, b], `dayBgImageStretch` [left, right, top, bottom] %).
  static RuleBgImage? of(String path, double opacity, List<dynamic> padding, List<dynamic> stretch) {
    if (path.trim().isEmpty) return null;
    final p = [for (var i = 0; i < 4; i++) i < padding.length ? _n(padding[i]) : 0.0];
    final s = stretch.length == 4 ? [for (final v in stretch) _n(v).clamp(0.0, 49.0).toDouble()] : defaultStretch;
    return RuleBgImage(path.trim(), opacity: opacity, padding: EdgeInsets.fromLTRB(p[0], p[1], p[2], p[3]), stretch: s);
  }

  double get alpha => opacity <= 0 ? 1 : opacity.clamp(0.0, 1.0);

  /// The centre slice of an image of [w] x [h] pixels.
  Rect centerSlice(double w, double h) {
    final l = w * stretch[0] / 100, r = w - w * stretch[1] / 100;
    final t = h * stretch[2] / 100, b = h - h * stretch[3] / 100;
    return Rect.fromLTRB(l, t, r < l + 1 ? l + 1 : r, b < t + 1 ? t + 1 : b);
  }
}

/// Decoded images by path; [version] changes when one more finished loading (pages listen and repaint).
abstract class HighlightBgImages {
  static final Map<String, ui.Image> _images = {};
  static final Set<String> _loading = {};
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// `@high/x` / `@images/x` -> the app folder, other paths as they are.
  static String resolve(String path) {
    if (path.startsWith('@high/')) return '${AppDirs.path('high')}/${path.substring(6)}';
    if (path.startsWith('@images/')) return '${AppDirs.path('images')}/${path.substring(8)}';
    return path;
  }

  static ui.Image? get(String path) {
    final img = _images[path];
    if (img == null) unawaited(_load(path));
    return img;
  }

  static Future<void> _load(String path) async {
    if (_loading.contains(path)) return;
    _loading.add(path);
    try {
      Uint8List bytes;
      if (path.startsWith('http')) {
        final r = await HttpClient().getUrl(Uri.parse(path)).then((q) => q.close());
        bytes = await consolidateHttpClientResponseBytes(r);
      } else {
        final f = File(resolve(path));
        if (!f.existsSync()) return;
        bytes = await f.readAsBytes();
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _images[path] = frame.image;
      version.value++;
    } catch (_) {
      // a broken image is simply not drawn
    } finally {
      _loading.remove(path);
    }
  }

  /// Puts a decoded image in the cache (tests, the editor's preview).
  static void put(String path, ui.Image image) {
    _images[path] = image;
    version.value++;
  }

  static void evict(String path) => _images.remove(path);
}

/// Paints the nine-patch backgrounds of [ranges] behind a text laid out like the page's `Text.rich`.
class NinePatchPainter extends CustomPainter {
  final InlineSpan span;
  final TextAlign align;
  final StrutStyle? strut;
  final List<(int, int, RuleBgImage)> ranges;

  NinePatchPainter({required this.span, required this.align, required this.strut, required this.ranges}) : super(repaint: HighlightBgImages.version);

  /// The line boxes of `[start, end)`, merged per line.
  static List<Rect> lineRects(TextPainter tp, int start, int end) {
    final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));
    final out = <Rect>[];
    for (final b in boxes) {
      final r = b.toRect();
      if (out.isNotEmpty && (out.last.top - r.top).abs() < 1) {
        out[out.length - 1] = out.last.expandToInclude(r);
      } else {
        out.add(r);
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(text: span, textAlign: align, strutStyle: strut, textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)
      ..setPlaceholderDimensions(ReadTextBuilder.dimensionsOf(span))
      ..layout(minWidth: size.width, maxWidth: size.width);
    for (final (s, e, bg) in ranges) {
      final img = HighlightBgImages.get(bg.path);
      if (img == null) continue;
      final w = img.width.toDouble(), h = img.height.toDouble();
      final paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, bg.alpha);
      for (final r in lineRects(tp, s, e)) {
        final dst = bg.padding.inflateRect(r);
        if (dst.width < 2 || dst.height < 2) continue;
        canvas.drawImageNine(img, bg.centerSlice(w, h), dst, paint);
      }
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(NinePatchPainter old) => old.span != span || old.ranges.length != ranges.length || old.align != align;
}
