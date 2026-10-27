// pages/history/history_page.dart — 历史记录 (`HistoryPage`): the reading history kept by the reading core (`ReadApi.getHistory`,
// item `historybook`, most recent first) as a BookList (`history_list`, `ishistory`); 「操作确认」 「是否要清除历史记录？」 clears it.
// Tapping a book reopens the reader at its saved position; a long press opens the detail page.
import 'package:flutter/material.dart';

import '../../common/nav.dart';
import '../../models/book.dart';
import '../../read/api/read_file_store.dart';
import '../../read/api/readapi.dart';
import '../../widget/base_page.dart';
import '../../widget/book/booklist.dart';
import '../book/book_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends BasePage<HistoryPage> {
  List<Book>? _books;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ReadApi.getHistory(refresh: true);
    update(() => _books = list);
  }

  Future<void> _clear() async {
    if (!await confirm('操作确认', '是否要清除历史记录？')) return;
    await ReadItemStore.write(ReadApi.historyKey, '[]');
    ReadApi.historyTmp = <Book>[];
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _books;
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        centerTitle: true,
        actions: [IconButton(key: const Key('history_clear_all'), icon: const Icon(Icons.delete_sweep_outlined), onPressed: list == null || list.isEmpty ? null : _clear)],
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('暂无浏览历史'))
              : BookList(
                  key: const Key('history_list'),
                  books: list,
                  islist: true,
                  ishistory: true,
                  onTap: (b) => Nav.openReader(context, b),
                  showBookOperations: (b) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: b))),
                ),
    );
  }
}
