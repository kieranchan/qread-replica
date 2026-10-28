// pages/search/backbook_page.dart — `BackbookPage`: pick books from a backup and put them on the shelf (「备份导入」 of the
// add-book sheet). Search field 「搜索书名或作者」, multi-select 「全选 (n/m)」 / 「反选」, 「加入书架」 → 「确定要将这些加入书架吗？」 →
// 「共添加n 本书。」 (0xfa8024 skips books already on the shelf; local `phone_book` entries are kept only when the file exists).
// The books come from one backup device (0xfa8610): `getBookSelf(appid)` (0xfa8894: the server answers the download url of that
// device's 书架备份, the list is fetched and parsed; failures toast `获取书架书籍失败:`). 备份导入 first shows the device dialog
// ([BackbookPage.open] → pages/user/auto_device_management_dialog.dart), whose tap opens this page with the device's appid.
// (The original also lists the bound 轻阅读 backend as device "0" and reads `/getBookshelfPage` from it; the backend binding is
// the qread/ area's, pass a [loader] for it.)
import 'package:flutter/material.dart';

import '../../api/userapi.dart';
import '../../common/common.dart';
import '../../data/bookself.dart';
import '../../models/book.dart';
import '../../read/local_book_importer.dart';
import '../../storage/storage.dart';
import '../../util/toast.dart';
import '../../widget/book/booklist.dart';
import '../../widget/book_page.dart';
import '../user/auto_device_management_dialog.dart';

/// The cloud bookshelf list (`getBooks`), for callers that want to pick from 云端书架 instead of a device backup.
Future<List<Book>> cloudShelfBooks() async {
  final text = await UserApi.cloudList(CloudKind.books);
  return [for (final e in Storage.jsondecode(text)) if (e is Map) Book.fromJson(Map<String, dynamic>.from(e))];
}

class BackbookPage extends StatefulWidget {
  /// The backup device to read (`getBookSelf`); null = this device.
  final String? appid;
  final Future<List<Book>> Function()? loader;
  const BackbookPage({super.key, this.appid, this.loader});

  /// 备份导入 (0x53d29c): the 书架备份 device dialog; tapping a device opens this page for it.
  static Future<void> open(BuildContext context) => AutoDeviceManagementDialog.show(context, isSource: false);

  @override
  State<BackbookPage> createState() => _BackbookPageState();
}

class _BackbookPageState extends BookApiPage<BackbookPage> {
  List<Book>? _books;
  String _error = '';
  final Set<String> _selected = {};
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await BookSelfN.load();
      final list = await (widget.loader ?? () => UserApi.getBookSelf(widget.appid ?? Common.appid))();
      update(() => _books = list);
    } catch (e) {
      update(() {
        _books = [];
        _error = '$e';
      });
    }
  }

  List<Book> get _shown {
    final f = _filter.text.trim();
    final all = _books ?? const <Book>[];
    return f.isEmpty ? all : all.where((b) => b.name.contains(f) || b.author.contains(f)).toList();
  }

  Future<void> _add() async {
    final chosen = [for (final b in _books ?? const <Book>[]) if (_selected.contains(b.bookUrl)) b];
    if (chosen.isEmpty) return;
    if (!await confirm('加入书架', '确定要将这些加入书架吗？')) return;
    final ok = chosen.where((b) => !BookSelfN.contains(b.bookUrl) && (!isLocalShelfBook(b) || LocalBookImporter.fileOf(b).existsSync()));
    final n = await BookSelfN.addAll(ok);
    Toast.show('共添加$n 本书。');
    update(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final n = shown.where((b) => _selected.contains(b.bookUrl)).length;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('backbook_filter'),
          controller: _filter,
          onChanged: (_) => update(),
          decoration: const InputDecoration(hintText: '搜索书名或作者', border: InputBorder.none),
        ),
      ),
      body: _books == null
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty && _books!.isEmpty
              ? Center(child: Text(_error))
              : BookList(
                  key: const Key('backbook'),
                  books: shown,
                  islist: true,
                  isedit: true,
                  selected: _selected,
                  toggleSourceSelection: (u) => update(() => _selected.contains(u) ? _selected.remove(u) : _selected.add(u)),
                ),
      bottomNavigationBar: SafeArea(
        child: Row(children: [
          TextButton(
            onPressed: () => update(() {
              final all = shown.map((b) => b.bookUrl).toSet();
              _selected.containsAll(all) ? _selected.removeAll(all) : _selected.addAll(all);
            }),
            child: Text('全选 ($n/${shown.length})'),
          ),
          TextButton(
            onPressed: () => update(() {
              for (final b in shown) {
                if (!_selected.remove(b.bookUrl)) _selected.add(b.bookUrl);
              }
            }),
            child: const Text('反选'),
          ),
          const Spacer(),
          Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton(key: const Key('backbook_add'), onPressed: n == 0 ? null : _add, child: const Text('加入书架'))),
        ]),
      ),
    );
  }
}
