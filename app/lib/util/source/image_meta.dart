// util/source/image_meta.dart — not a file of the original: the `<img src>` conventions of book-source chapter text, as the
// original's source help (书源规则说明, 0x95fb18) documents them:
//   * `src,{json}`: a JSON object after the address — `js` (run in the source page when the image is tapped in the reader),
//     `headers` (sent with the image request), `imageDecode` (the page's `imagedecrypt` decodes it); single quotes are accepted;
//   * `dp:N,{json}`: the app's own 段评 bubble showing N (the bubble chosen in 段评气泡, `$color` = the reader's text colour);
//   * images on the same line as text are 段评 (drawn small), the others are normal images; `data:` images (base64, svg too) work.
// [ParagraphComments.click] runs an image's `js` in the page of the book's 时光源 (e.g. `showCmt(url, '番茄')` →
// `startBrowserDp`, the half-height comment sheet).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../../data/source.dart';
import '../../data/svg.dart';
import '../../storage/storage.dart';
import 'run.dart';
import 'source.dart';

class ImageMeta {
  /// The image address without the JSON (for `dp:` the count text follows in [dpText]).
  final String url;

  /// `js` of the JSON ('' when none).
  final String js;

  /// `headers` of the JSON.
  final Map<String, String> headers;

  /// `imageDecode` of the JSON.
  final bool imageDecode;

  const ImageMeta(this.url, {this.js = '', this.headers = const {}, this.imageDecode = false});

  /// A `dp:` bubble.
  bool get isDp => url.startsWith('dp:');

  /// The count a `dp:` bubble shows (`99+`, `3`, …).
  String get dpText => isDp ? url.substring(3).trim() : '';

  bool get isData => url.startsWith('data:');

  bool get isSvgData => url.startsWith('data:image/svg');

  static Object? _json(String s) {
    final t = s.trim();
    if (!t.startsWith('{') || !t.endsWith('}')) return null;
    try {
      return jsonDecode(t);
    } catch (_) {}
    try {
      return jsonDecode(t.replaceAll("'", '"'));
    } catch (_) {
      return null;
    }
  }

  /// Splits [src] at the first `,{` whose rest is a JSON object.
  static ImageMeta parse(String src) {
    final s = src.trim();
    var i = s.indexOf(',{');
    while (i >= 0) {
      final j = _json(s.substring(i + 1));
      if (j is Map) {
        final h = <String, String>{};
        final hv = j['headers'];
        if (hv is Map) hv.forEach((k, v) => h['$k'] = '$v');
        final dec = j['imageDecode'];
        return ImageMeta(
          s.substring(0, i).trim(),
          js: '${j['js'] ?? ''}',
          headers: h,
          imageDecode: dec == true || '$dec' == 'true',
        );
      }
      i = s.indexOf(',{', i + 1);
    }
    return ImageMeta(s);
  }

  /// The bytes of a `data:…;base64,` image (null when it is not one or does not decode).
  Uint8List? get dataBytes {
    if (!isData) return null;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    final head = url.substring(0, comma);
    final body = url.substring(comma + 1);
    try {
      if (head.endsWith(';base64')) return base64Decode(base64.normalize(body.trim()));
      return Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
    } catch (_) {
      return null;
    }
  }

  /// `#rrggbb` of [c] (the bubble's `$color`).
  static String hex(Color c) {
    String two(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${two(c.r)}${two(c.g)}${two(c.b)}';
  }

  /// The SVG of a `dp:` bubble: the bubble chosen in 段评气泡 (prefs `svg`), `$color` and `$displayText` filled in.
  String dpSvg(Color color) {
    final b = Svg.selected(Storage.getString('svg'));
    final svg = b?.svg ?? (Svg.desvgs.isEmpty ? '' : Svg.desvgs.first.svg);
    return svg.replaceAll(r'$color', hex(color)).replaceAll(r'$displayText', dpText);
  }
}

abstract class ParagraphComments {
  /// The source url of the book open in the reader (set by the reader; tests set it directly).
  static String Function()? activeSource;

  /// Runs [js] in the page of the 时光源 [sourceUrl] (default: the open book's source). Returns false when there is no such source.
  static Future<bool> click(String js, {String? sourceUrl}) async {
    if (js.trim().isEmpty) return false;
    final url = sourceUrl ?? activeSource?.call() ?? '';
    if (url.isEmpty) return false;
    try {
      await Sourcedata.load();
    } catch (_) {}
    final raw = Sourcedata.byUrl(url);
    if (!BaseSource.isTimeSource(raw)) return false;
    try {
      await (await SourceRun.of(BaseSource.fromJson(raw!))).runJs(js);
    } catch (e) {
      debugPrint('图片js执行失败:$e');
    }
    return true;
  }
}
