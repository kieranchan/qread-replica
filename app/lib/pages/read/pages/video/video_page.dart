// pages/read/pages/video/video_page.dart — one episode of a video book (original `_VideoPageState`, "无效的视频地址 ："). Delegates to the
// video player shell ([VideoPlayerPage]) because no video plugin is bundled.
import 'package:flutter/material.dart';

import '../../../video/video_player_page.dart';

class VideoPage extends StatelessWidget {
  final String url;
  final String title;
  const VideoPage({super.key, required this.url, this.title = ''});

  @override
  Widget build(BuildContext context) => VideoPlayerPage(url: url, title: title);
}
