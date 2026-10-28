// pages/read/pages/video/video_page.dart — one episode of a video book (original `_VideoPageState`, "无效的视频地址 ："): plays it in the
// app with [VideoPlayerPage] (video_player).
import 'package:flutter/material.dart';

import '../../../video/video_player_page.dart';

class VideoPage extends StatelessWidget {
  final String url;
  final String title;
  final VoidCallback? onCompleted;
  const VideoPage({super.key, required this.url, this.title = '', this.onCompleted});

  @override
  Widget build(BuildContext context) => VideoPlayerPage(url: url, title: title, onCompleted: onCompleted);
}
