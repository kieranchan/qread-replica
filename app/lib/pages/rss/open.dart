// pages/rss/open.dart — `RssOpen` (RSS等待界面, `rssopen`): decides how an RSS source opens and replaces itself after the first frame:
// a `singleUrl` source shows its (first sort) page directly in WebviewRssPage, every other source gets the article list.
// Original `_RssOpenState` (post-frame 0x10cb48c -> 0x9067f4 RssArticles / 0x906934, 0x906a14 WebviewRssPage).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/rss.dart';
import '../../models/rsssource.dart' as m;
import '../../qread/rssdata.dart';
import '../../util/toast.dart';
import '../../util/webbook/model/rss_source.dart';
import 'rss_articles.dart';
import 'rss_webview.dart';

class RssOpen extends StatefulWidget {
  final Map<String, dynamic> source;
  const RssOpen({super.key, required this.source});

  @override
  State<RssOpen> createState() => _RssOpenState();
}

class _RssOpenState extends State<RssOpen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  Future<void> _go() async {
    final src = RssSource.fromJson(widget.source);
    Widget page;
    if (src.singleUrl) {
      var url = src.sourceUrl;
      try {
        final sorts = await src.sortUrls();
        if (sorts.isNotEmpty && sorts.first.$2.isNotEmpty) url = sorts.first.$2;
      } catch (_) {}
      page = WebviewRssPage(source: widget.source, url: url, title: src.sourceName);
    } else {
      page = RssArticles(source: widget.source);
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (c) => page));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Target of `Nav.openRss`: opens the stored source with this url (local or backend).
Future<void> openRss(BuildContext context, m.RssSource source) async {
  await Rssdata.load();
  Map<String, dynamic>? raw = Rssdata.byUrl(source.sourceUrl);
  if (raw == null) {
    await QRssSources.load();
    final q = QRssSources.byUrl(source.sourceUrl);
    if (q != null) raw = {...q.toJson(), 'isqread': true};
  }
  // the model keeps the source's JSON text in `json` (sources handed over by other areas)
  if (raw == null && source.json.trim().startsWith('{')) {
    try {
      raw = Map<String, dynamic>.from(jsonDecode(source.json) as Map);
    } catch (_) {}
  }
  if (raw == null) {
    Toast.show('未找到订阅源');
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (c) => RssOpen(source: raw!)));
}
