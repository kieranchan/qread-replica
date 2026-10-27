// pages/web/search_page.dart — the browser's address/search input with the search history (`SearchPage`, size 0x30; not the book
// search page). Original `_SearchPageState` (build 0x830cb0: search field, `搜索历史` + `清理`, `暂无搜索历史`; filter 0x927e70).
// It returns the typed text; the browser decides between url and search (chrome_inapp.dart). History lives in the file store
// under `searchHistory` (written by the browser 0xfd1cf8, read 0x10cc278).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../storage/storage.dart';

abstract class WebSearchHistory {
  static const String key = 'searchHistory';
  static const int max = 50;

  static Future<List<String>> load() async {
    Storage.keepOnClean(key);
    try {
      return [for (final e in Storage.jsondecode(await Storage.read(key))) '$e'];
    } catch (e) {
      debugPrint('加载搜索历史失败: $e');
      return [];
    }
  }

  /// Puts [text] first (no duplicates, at most [max] entries).
  static Future<void> add(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final list = await load()
      ..remove(t)
      ..insert(0, t);
    try {
      await Storage.write(key, jsonEncode(list.take(max).toList()));
    } catch (e) {
      debugPrint('保存搜索历史失败: $e');
    }
  }

  static Future<void> clear() => Storage.write(key, '');
}

class SearchPage extends StatefulWidget {
  final String initial;
  const SearchPage({super.key, this.initial = ''});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  List<String> _history = [];
  late List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _c.addListener(_filter);
    WebSearchHistory.load().then((h) {
      if (!mounted) return;
      setState(() {
        _history = h;
        _filter();
      });
    });
  }

  void _filter() {
    final t = _c.text.trim().toLowerCase();
    setState(() => _suggestions = t.isEmpty ? _history : _history.where((e) => e.toLowerCase().contains(t)).toList());
  }

  void _submit(String v) {
    if (v.trim().isEmpty) return;
    Navigator.of(context).pop(v.trim());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('web_search_input'),
          controller: _c,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            hintText: '搜索或输入网址',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            filled: true,
            isDense: true,
          ),
          onSubmitted: _submit,
        ),
        actions: [TextButton(onPressed: () => _submit(_c.text), child: const Text('前往'))],
      ),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              Text('搜索历史', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await WebSearchHistory.clear();
                  setState(() {
                    _history = [];
                    _suggestions = [];
                  });
                },
                child: const Text('清理'),
              ),
            ]),
          ),
          Expanded(
            child: _suggestions.isEmpty
                ? Center(child: Text('暂无搜索历史', style: TextStyle(color: cs.outline)))
                : ListView.builder(
                    itemCount: _suggestions.length,
                    itemBuilder: (c, i) => ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(_suggestions[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _submit(_suggestions[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
