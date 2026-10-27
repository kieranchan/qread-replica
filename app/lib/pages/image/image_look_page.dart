// pages/image/image_look_page.dart — a single image full screen (original `image_look_page.dart`); same viewer as the gallery.
import 'package:flutter/material.dart';

import 'gallery_viewer_page.dart';

class ImageLookPage extends StatelessWidget {
  final String src;
  const ImageLookPage({super.key, required this.src});

  @override
  Widget build(BuildContext context) => GalleryViewerPage(images: [src]);
}
