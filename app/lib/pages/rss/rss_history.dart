// pages/rss/rss_history.dart — `RssHistory`: the articles read from one RSS source (历史记录). File-store key `<sourceUrl>rsshistory`
// (template `{}rsshistory`, docs/SETTINGS.md), a JSON list of `Article`, newest first. Original `_RssHistoryState` (build 0x5bfb14
// `历史记录`, item 0x5c0040 image + title, open 0xfbc1b0 -> WebviewRssPage, clear 0xfbd028 `历史记录已清空`).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/article.dart';
import '../../storage/storage.dart';
import '../../util/toast.dart';
import 'rss_webview.dart';

abstract class RssHistoryStore {
  static const int max = 200;
  static String key(String sourceUrl) => '${sourceUrl}rsshistory';

  static Future<List<Article>> load(String sourceUrl) async =>
      [for (final e in Storage.jsondecode(await Storage.read(key(sourceUrl)))) if (e is Map) Article.fromJson(Map<String, dynamic>.from(e))];

  /// Puts [a] first (by link) and keeps at most [max] entries.
  static Future<void> add(String sourceUrl, Article a) async {
    final list = await load(sourceUrl)
      ..removeWhere((e) => e.link == a.link)
      ..insert(0, a);
    await Storage.write(key(sourceUrl), jsonEncode([for (final e in list.take(max)) e.toJson()]));
  }

  static Future<void> clear(String sourceUrl) => Storage.write(key(sourceUrl), '');
}

class RssHistory extends StatefulWidget {
  /// Raw JSON of the RSS source.
  final Map<String, dynamic> source;
  const RssHistory({super.key, required this.source});

  @override
  State<RssHistory> createState() => _RssHistoryState();
}

class _RssHistoryState extends State<RssHistory> {
  List<Article> _list = [];
  String get _url => '${widget.source['sourceUrl'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await RssHistoryStore.load(_url);
    if (mounted) setState(() => _list = l);
  }

  Future<void> _clear() async {
    await RssHistoryStore.clear(_url);
    setState(() => _list = []);
    Toast.show('历史记录已清空');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        actions: [IconButton(key: const Key('rss_history_clear'), tooltip: '清空', icon: const Icon(Icons.delete_sweep_outlined), onPressed: _clear)],
      ),
      body: SafeArea(
        child: _list.isEmpty
            ? Center(child: Text('暂无历史记录', style: TextStyle(color: cs.outline)))
            : ListView.separated(
                itemCount: _list.length,
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final a = _list[i];
                  return InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => WebviewRssPage(source: widget.source, article: a))),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        if (a.image.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(a.image, width: 64, height: 48, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(width: 64, height: 48, color: cs.surfaceContainerHighest)),
                          ),
                        if (a.image.isNotEmpty) const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (a.pubDate.isNotEmpty) Text(a.pubDate, style: TextStyle(fontSize: 12, color: cs.outline)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
