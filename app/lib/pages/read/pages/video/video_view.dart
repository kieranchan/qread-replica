// pages/read/pages/video/video_view.dart — video books (`Book.type == 4`; original `_VideoViewState`: 保存进度到服务器 ·
// 当前章节超出目录总章节，请前往目录重新选择章节 · 章节列表为空). Lists the episodes; an episode opens [VideoPage].
import 'package:flutter/material.dart';

import '../../../../models/book.dart';
import '../../../../models/bookchapter.dart';
import '../../../../read/api/readapi.dart';
import '../../../../util/toast.dart';
import '../novel_view.dart' show ChapterListLoader;
import 'video_page.dart';

class VideoView extends StatefulWidget {
  final Book book;
  final List<BookChapter>? chapters;
  final int? chapterIndex;
  final ChapterListLoader? chapterListLoader;

  const VideoView({super.key, required this.book, this.chapters, this.chapterIndex, this.chapterListLoader});

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  List<BookChapter>? _chapters;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var list = widget.chapters;
      if (list == null || list.isEmpty) list = await widget.chapterListLoader?.call(widget.book) ?? const [];
      if (!mounted) return;
      setState(() {
        _chapters = list;
        if (list!.isEmpty) _error = '章节列表为空';
      });
      final i = widget.chapterIndex;
      if (i != null && (i < 0 || i >= list.length)) Toast.show('当前章节超出目录总章节，请前往目录重新选择章节');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _play(int i) async {
    final list = _chapters!;
    final c = list[i];
    try {
      await ReadApi(widget.book, chapters: list).saveProgress(chapterIndex: i, pos: 0);
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPage(title: c.name, url: c.chapterId.isNotEmpty ? c.chapterId : c.baseUrl)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = _chapters;
    return Scaffold(
      appBar: AppBar(title: Text(widget.book.name)),
      body: _error != null
          ? Center(child: Text(_error!))
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => ListTile(
                    selected: i == widget.book.durChapterIndex,
                    leading: const Icon(Icons.play_circle_outline),
                    title: Text(list[i].name),
                    onTap: () => _play(i),
                  ),
                ),
    );
  }
}
