// pages/read/pages/novel/search_book.dart — "搜索正文": full-text search in the open book (original `_SearchBookPageState`: 搜索关键词 /
// 输入关键词开始搜索 / 正在搜索中... / 找到 N 个结果 / 未找到相关内容 / 错误). Local books are searched chapter by chapter; web books only in
// the chapters that are cached on the device (searching would otherwise download the whole book). Tapping a result pops a [SearchHit].
import 'package:flutter/material.dart';

import '../../../../read/api/readapi.dart';
import 'views/reader_host.dart';

class SearchHit {
  final int chapterIndex;
  final String chapterName;
  final int start;
  final int end;

  /// Text around the hit.
  final String context;
  const SearchHit(this.chapterIndex, this.chapterName, this.start, this.end, this.context);
}

/// Finds [key] in [text] (case-insensitive); [around] characters of context on each side.
List<SearchHit> searchText(String text, String key, int chapterIndex, String chapterName, {int around = 20, int limit = 200}) {
  final out = <SearchHit>[];
  if (key.isEmpty) return out;
  final lower = text.toLowerCase();
  final k = key.toLowerCase();
  var i = lower.indexOf(k);
  while (i >= 0 && out.length < limit) {
    final s = (i - around).clamp(0, text.length);
    final e = (i + k.length + around).clamp(0, text.length);
    out.add(SearchHit(chapterIndex, chapterName, i, i + k.length, text.substring(s, e).replaceAll('\n', ' ')));
    i = lower.indexOf(k, i + k.length);
  }
  return out;
}

class SearchBookPage extends StatefulWidget {
  final ReaderHost host;
  final String initialKeyword;

  const SearchBookPage({super.key, required this.host, this.initialKeyword = ''});

  @override
  State<SearchBookPage> createState() => _SearchBookPageState();
}

class _SearchBookPageState extends State<SearchBookPage> {
  late final TextEditingController _key = TextEditingController(text: widget.initialKeyword);
  final List<SearchHit> _hits = [];
  bool _searching = false;
  bool _done = false;
  String? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialKeyword.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _gen++;
    _key.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    final gen = ++_gen;
    setState(() {
      _hits.clear();
      _searching = true;
      _done = false;
      _error = null;
    });
    final host = widget.host;
    final api = host.api;
    final local = ReadApi.isLocalBook(host.book);
    try {
      for (var i = 0; i < host.chapters.length; i++) {
        if (gen != _gen) return;
        if (!local && i != host.chapterIndex && !api.bookContent.existsSync(host.book.bookUrl, i)) continue;
        final rc = await api.loadChapter(i);
        if (gen != _gen || !mounted) return;
        final found = searchText(rc.content.text, key, i, rc.title);
        if (found.isNotEmpty) setState(() => _hits.addAll(found));
      }
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = '$e');
    }
    if (mounted && gen == _gen) {
      setState(() {
        _searching = false;
        _done = true;
      });
    }
  }

  Widget _status() {
    if (_error != null) return Text('错误: $_error');
    if (_searching) return Text('正在搜索中... 找到 ${_hits.length} 个结果');
    if (!_done) return const Text('输入关键词开始搜索');
    if (_hits.isEmpty) return const Text('未找到相关内容');
    return Text('找到 ${_hits.length} 个结果');
  }

  @override
  Widget build(BuildContext context) {
    final key = _key.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _key,
          autofocus: widget.initialKeyword.isEmpty,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '搜索关键词', border: InputBorder.none),
          onSubmitted: (_) => _search(),
        ),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: _search)],
      ),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(12), child: _status()),
          Expanded(
            child: ListView.separated(
              itemCount: _hits.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final h = _hits[i];
                final pos = h.context.toLowerCase().indexOf(key.toLowerCase());
                final hl = TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold);
                return ListTile(
                  title: Text(h.chapterName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: pos < 0
                      ? Text(h.context)
                      : Text.rich(TextSpan(children: [
                          TextSpan(text: h.context.substring(0, pos)),
                          TextSpan(text: h.context.substring(pos, pos + key.length), style: hl),
                          TextSpan(text: h.context.substring(pos + key.length)),
                        ])),
                  onTap: () => Navigator.pop(context, h),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
