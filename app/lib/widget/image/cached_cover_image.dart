// widget/image/cached_cover_image.dart — `CachedCoverImage`, the book cover of the shelf, search and detail pages.
//
// Original (`_CachedCoverImagePage`, closures 0x104fafc / 0x1050534; default-cover builder sub_59fd54 with the key `book_title_`):
// network covers are cached, local covers (`covers/…`, absolute paths, `file:/`) are read from disk, `data:` urls are decoded,
// and when there is no cover or it fails (the url is remembered in `Common.imgerrors`) the default cover asset is shown with the
// book title written on it. A long press offers 「刷新」 (reload the image).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../common/common.dart';
import '../../read/api/read_storage_root.dart';

/// Default cover asset (copied from the original's flutter_assets).
const String kNoCoverAsset = 'lib/assets/images/no_cover.jpeg';

class CachedCoverImage extends StatefulWidget {
  final String url;

  /// Written on the default cover.
  final String title;
  final String author;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Asset used when there is no cover (original parameter `errorimg`).
  final String errorimg;
  final BorderRadius? borderRadius;

  const CachedCoverImage({
    super.key,
    required this.url,
    this.title = '',
    this.author = '',
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorimg = kNoCoverAsset,
    this.borderRadius,
  });

  /// Resolves a stored cover url to a local file, or null for network / data urls.
  static File? localFile(String url) {
    if (url.isEmpty || url.startsWith('http') || url.startsWith('data:')) return null;
    var path = url.startsWith('file:/') ? Uri.parse(url).toFilePath() : url;
    if (!File(path).isAbsolute && ReadStorageRoot.isSet) path = '${ReadStorageRoot.dir.path}/$path';
    return File(path);
  }

  @override
  State<CachedCoverImage> createState() => _CachedCoverImagePage();
}

class _CachedCoverImagePage extends State<CachedCoverImage> {
  int _reload = 0;

  Widget _fallback() => DefaultCover(
        key: ValueKey('book_title_${widget.title}'),
        title: widget.title,
        author: widget.author,
        asset: widget.errorimg,
        width: widget.width,
        height: widget.height,
      );

  Widget _image() {
    final url = widget.url.trim();
    if (url.isEmpty || Common.imgerrors.contains(url)) return _fallback();
    Widget onError(BuildContext c, Object e, StackTrace? s) {
      Common.imgerrors.add(url);
      return _fallback();
    }

    if (url.startsWith('data:')) {
      final i = url.indexOf('base64,');
      if (i < 0) return _fallback();
      try {
        return Image.memory(base64Decode(url.substring(i + 7)),
            width: widget.width, height: widget.height, fit: widget.fit, gaplessPlayback: true, errorBuilder: onError);
      } catch (_) {
        return _fallback();
      }
    }
    final file = CachedCoverImage.localFile(url);
    if (file != null) {
      if (!file.existsSync()) return _fallback();
      return Image.file(file, width: widget.width, height: widget.height, fit: widget.fit, gaplessPlayback: true, errorBuilder: onError);
    }
    return Image.network(url,
        key: ValueKey('$url#$_reload'), width: widget.width, height: widget.height, fit: widget.fit, gaplessPlayback: true, errorBuilder: onError);
  }

  void _refresh() {
    Common.imgerrors.remove(widget.url);
    imageCache.evict(NetworkImage(widget.url));
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(width: widget.width, height: widget.height, child: _image());
    final clipped = widget.borderRadius == null ? child : ClipRRect(borderRadius: widget.borderRadius!, child: child);
    if (!widget.url.startsWith('http')) return clipped;
    return GestureDetector(
      onSecondaryTap: _refresh,
      child: clipped,
    );
  }
}

/// The original's default cover: the `no_cover` picture with the title (and author) written vertically centred on it.
class DefaultCover extends StatelessWidget {
  final String title;
  final String author;
  final String asset;
  final double? width;
  final double? height;

  const DefaultCover({super.key, required this.title, this.author = '', this.asset = kNoCoverAsset, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = width ?? (c.maxWidth.isFinite ? c.maxWidth : 90);
      final fs = (w / 7).clamp(9.0, 22.0);
      return Stack(fit: StackFit.expand, children: [
        Image.asset(asset, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: const Color(0xFF7CB7B2))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.12, vertical: w * 0.18),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fs, fontWeight: FontWeight.bold, color: Colors.white, height: 1.25, shadows: const [
                  Shadow(blurRadius: 3, color: Colors.black54),
                ])),
            if (author.isNotEmpty) ...[
              SizedBox(height: fs * 0.4),
              Text(author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: fs * 0.6, color: Colors.white70)),
            ],
          ]),
        ),
      ]);
    });
  }
}
