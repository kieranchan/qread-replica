// pages/image/gallery_viewer_page.dart — full-screen image gallery (original `_GalleryViewerPageState` / `_GalleryPageState`, "关闭"): swipe
// between images, pinch to zoom, index indicator. Sources are file paths, http(s) URLs or asset paths.
import 'dart:io';

import 'package:flutter/material.dart';

ImageProvider galleryImageProvider(String src) {
  if (src.startsWith('http')) return NetworkImage(src);
  if (src.startsWith('lib/assets/')) return AssetImage(src);
  return FileImage(File(src));
}

class GalleryViewerPage extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const GalleryViewerPage({super.key, required this.images, this.initialIndex = 0});

  @override
  State<GalleryViewerPage> createState() => _GalleryViewerPageState();
}

class _GalleryViewerPageState extends State<GalleryViewerPage> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _pages,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => _GalleryPage(src: widget.images[i]),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Row(children: [
              TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('关闭', style: TextStyle(color: Colors.white))),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('${_index + 1}/${widget.images.length}', style: const TextStyle(color: Colors.white)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _GalleryPage extends StatefulWidget {
  final String src;
  const _GalleryPage({required this.src});

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  final TransformationController _t = TransformationController();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => _t.value = Matrix4.identity(),
      child: InteractiveViewer(
        transformationController: _t,
        maxScale: 5,
        child: Center(
          child: Image(
            image: galleryImageProvider(widget.src),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}
