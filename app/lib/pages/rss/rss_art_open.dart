// pages/rss/rss_art_open.dart — `RssArtOpen` (RSS等待界面二, `rssart`): records the article in the source's history and replaces itself
// with the article page after the first frame. Original `_RssArtOpenState` (post-frame 0x10cb7c4 -> 0x906c34 WebviewRssPage).
import 'package:flutter/material.dart';

import '../../models/article.dart';
import 'rss_history.dart';
import 'rss_webview.dart';

class RssArtOpen extends StatefulWidget {
  final Map<String, dynamic> source;
  final Article article;
  const RssArtOpen({super.key, required this.source, required this.article});

  @override
  State<RssArtOpen> createState() => _RssArtOpenState();
}

class _RssArtOpenState extends State<RssArtOpen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await RssHistoryStore.add('${widget.source['sourceUrl'] ?? ''}', widget.article);
      } catch (_) {}
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (c) => WebviewRssPage(source: widget.source, article: widget.article)));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
