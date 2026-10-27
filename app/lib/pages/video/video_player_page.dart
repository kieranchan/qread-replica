// pages/video/video_player_page.dart — the video player (original `_VideoPlayerPageState`, 83 functions: gestures 快退中... / 快进中...,
// speed, progress `video_progress_<id>`, device list for casting). This build bundles no video plugin, so the page is a shell that shows
// the address and opens it in the system player / browser. TODO(asm video_player_page): in-app playback needs `video_player` (or similar).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../util/toast.dart';

class VideoPlayerPage extends StatelessWidget {
  final String url;
  final String title;

  const VideoPlayerPage({super.key, required this.url, this.title = ''});

  static const String unsupported = '当前版本不支持视频播放';

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final valid = uri != null && uri.hasScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.ondemand_video, size: 72),
            const SizedBox(height: 12),
            Text(valid ? unsupported : '无效的视频地址 ：$url', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            SelectableText(url, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Wrap(spacing: 12, children: [
              OutlinedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  Toast.show('地址已复制');
                },
                child: const Text('复制地址'),
              ),
              if (valid)
                FilledButton(onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication), child: const Text('用浏览器打开')),
            ]),
          ]),
        ),
      ),
    );
  }
}
