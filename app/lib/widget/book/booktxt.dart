// widget/book/booktxt.dart — `CacheTxtProgressDialog`: exports the cached chapters of a book as one TXT (「导出进度」, 「准备导出...」,
// 「正在导出第 n 章...」, 「导出完成」, 「导出失败: 」, buttons 「关闭」 / 「保存」 → share sheet). Original 0x10cfbe4 / 0x1049d5c; the
// file goes to `<root>/export/<name>.txt` (TODO(asm 0x1049d5c): the original writes into its documents folder root).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/book.dart';
import '../../models/bookchapter.dart';
import '../../read/api/book_content.dart';
import '../../read/api/read_storage_root.dart';
import '../base_page.dart';

/// Writes the cached chapters of [book] to [out]; [onProgress] gets the 1-based chapter number. Returns the number of chapters
/// written (chapters without cache are skipped).
Future<int> exportCachedTxt(Book book, List<BookChapter> chapters, File out,
    {void Function(int n)? onProgress, BookContent content = const BookContent()}) async {
  out.parent.createSync(recursive: true);
  final sink = out.openWrite();
  var n = 0;
  try {
    sink.write('${book.name}\n作者：${book.author}\n\n');
    for (var i = 0; i < chapters.length; i++) {
      onProgress?.call(i + 1);
      final text = await content.readFromLocal(book.bookUrl, i);
      if (text == null) continue;
      sink.write('${chapters[i].name}\n\n${text.trim()}\n\n');
      n++;
    }
  } finally {
    await sink.close();
  }
  return n;
}

class CacheTxtProgressDialog extends StatefulWidget {
  final Book book;
  final List<BookChapter> chapters;

  const CacheTxtProgressDialog({super.key, required this.book, required this.chapters});

  @override
  State<CacheTxtProgressDialog> createState() => _CacheTxtProgressDialogState();
}

class _CacheTxtProgressDialogState extends BasePage<CacheTxtProgressDialog> {
  String _msg = '准备导出...';
  double _p = 0;
  File? _file;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final name = widget.book.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final f = File('${ReadStorageRoot.ensureSub('export').path}/$name.txt');
      await exportCachedTxt(widget.book, widget.chapters, f, onProgress: (n) {
        update(() {
          _msg = '正在导出第 $n 章...';
          _p = widget.chapters.isEmpty ? 1 : n / widget.chapters.length;
        });
      });
      update(() {
        _file = f;
        _p = 1;
        _msg = '导出完成';
      });
    } catch (e) {
      update(() => _msg = '导出失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导出进度'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [LinearProgressIndicator(value: _p), const SizedBox(height: 16), Text(_msg, key: const Key('export_msg'))]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
        if (_file != null)
          ElevatedButton(onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(_file!.path)])), child: const Text('保存')),
      ],
    );
  }
}
