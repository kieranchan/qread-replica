// pages/read/pages/comic_view.dart — the comic reader (original `_ComicViewState`, 152 functions): the images of a chapter one below
// the other, the next chapter appended when the end is reached, tap for the menu (上一话 / 下一话 / 目录 / day-night), progress saved as
// the scrolled fraction of the chapter. Strings: 漫画 · 内容加载中... · 目录 · 章节列表为空 · 上一话 · 下一话 · 正在前往下一章 · 进度 ·
// 预加载图片时出错:  · 已切换到白天模式 / 已切换到夜间模式 · 当前章节超出目录总章节，请前往目录重新选择章节 · 初始化失败: .
// Images come from the chapter content (image blocks: EPUB images, `<img>` of a source); a source's `imageDecode` script can be applied
// through [ComicView.imageBytes] (the app points it at `SourceApi.decodeImage`).
// Settings read at start (0x10c4230): `two` = 双指缩放 (pinch zoom, a double tap restores), `menuSliderType2` = the menu slider 按章节 (0,
// chapters) / 按分页 (1, the scroll position), `smart` (default true) = the volume keys keep their system function; off, they page
// (`_goToNextPage` / `_goToPreviousPage`: one screen less 100 px, "正在前往下一章" at the end; 0xf2331c / 0x2b17b4 / 0x2b2ac4).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/book.dart';
import '../../../models/bookchapter.dart';
import '../../../read/api/readapi.dart';
import '../../../storage/storage.dart';
import '../../../util/source/source_events.dart';
import '../../../util/toast.dart';
import '../../image/gallery_viewer_page.dart';
import 'novel_view.dart' show ChapterListLoader;

class ComicView extends StatefulWidget {
  final Book book;
  final List<BookChapter>? chapters;
  final int? chapterIndex;
  final ChapterLoader loader;
  final ChapterListLoader? chapterListLoader;

  /// Downloads + decodes an image of a source (null = `Image.network`).
  static Future<Uint8List> Function(Book book, BookChapter chapter, String url)? imageBytes;

  const ComicView({super.key, required this.book, required this.loader, this.chapters, this.chapterIndex, this.chapterListLoader});

  @override
  State<ComicView> createState() => ComicViewState();
}

class _ComicChapter {
  final int index;
  final String title;
  final List<String> images;
  const _ComicChapter(this.index, this.title, this.images);
}

class ComicViewState extends State<ComicView> {
  late ReadApi _api;
  List<BookChapter> _chapters = [];
  final List<_ComicChapter> _loaded = [];
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  int _ci = 0;
  bool _menu = false;
  bool _night = false;
  bool _loadingMore = false;
  String? _error;
  bool _ready = false;

  /// 双指缩放 (`two`), 菜单滑动条 (`menuSliderType2`), volume keys page unless `smart`.
  final bool _zoom = Storage.getBool('two');
  final int _sliderType = Storage.getInt('menuSliderType2');
  final bool _smart = Storage.getString('smart').isEmpty || Storage.getBool('smart', true);
  final TransformationController _zoomCtl = TransformationController();
  final FocusNode _focus = FocusNode(debugLabel: 'comic');
  double? _slider;

  int get chapterIndex => _ci;
  int get imageCount => _loaded.fold(0, (n, c) => n + c.images.length);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _init();
  }

  /// `_goToNextPage` / `_goToPreviousPage`: one screen less 100 px; at the end the next chapter.
  Future<void> page(int dir) async {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final step = (p.viewportDimension - 100).clamp(50.0, double.infinity);
    if (dir > 0 && p.pixels >= p.maxScrollExtent - 1) {
      if (_ci + 1 < _chapters.length) {
        Toast.show('正在前往下一章');
        await _open(_ci + 1);
      }
      return;
    }
    final to = (p.pixels + dir * step).clamp(0.0, p.maxScrollExtent);
    await _scroll.animateTo(to, duration: const Duration(milliseconds: 200), curve: Curves.linear);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final volume = k == LogicalKeyboardKey.audioVolumeDown || k == LogicalKeyboardKey.audioVolumeUp;
    if (volume && _smart) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.audioVolumeDown || k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown) {
      page(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.audioVolumeUp || k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp) {
      page(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The bottom slider: chapters (按章节) or the scroll position (按分页).
  Widget _menuSlider() {
    if (_sliderType == 1) {
      final max = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
      if (max <= 0) return const Slider(key: ValueKey('comic_slider_page'), value: 0, onChanged: null);
      final v = (_slider ?? _scroll.offset).clamp(0.0, max);
      return Slider(
        key: const ValueKey('comic_slider_page'),
        value: v,
        max: max,
        onChanged: (x) => setState(() => _slider = x),
        onChangeEnd: (x) {
          _slider = null;
          _scroll.jumpTo(x);
        },
      );
    }
    if (_chapters.length < 2) return const SizedBox.shrink();
    final v = (_slider ?? _ci.toDouble()).clamp(0.0, (_chapters.length - 1).toDouble());
    return Slider(
      key: const ValueKey('comic_slider_chapter'),
      value: v,
      max: (_chapters.length - 1).toDouble(),
      divisions: _chapters.length - 1,
      label: _chapters[v.round()].name,
      onChanged: (x) => setState(() => _slider = x),
      onChangeEnd: (x) {
        _slider = null;
        _open(x.round());
      },
    );
  }

  @override
  void dispose() {
    _save();
    _zoomCtl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      var list = widget.chapters;
      if (list == null || list.isEmpty) list = await widget.chapterListLoader?.call(widget.book) ?? const [];
      _chapters = List.of(list);
      if (_chapters.isEmpty) {
        setState(() => _error = '章节列表为空');
        return;
      }
      _api = ReadApi(widget.book, chapters: _chapters, loader: widget.loader);
      var start = widget.chapterIndex ?? widget.book.durChapterIndex;
      if (start < 0 || start >= _chapters.length) {
        Toast.show('当前章节超出目录总章节，请前往目录重新选择章节');
        start = 0;
      }
      await _open(start, progress: widget.chapterIndex == null ? widget.book.durChapterPos : 0);
    } catch (e) {
      if (mounted) setState(() => _error = '初始化失败: $e');
    }
  }

  Future<_ComicChapter> _load(int i) async {
    final rc = await _api.loadChapter(i);
    final images = <String>[
      for (final b in rc.content.blocks)
        if (b.isImage && b.runs.first.href.isNotEmpty) b.runs.first.href,
    ];
    return _ComicChapter(i, rc.title, images);
  }

  Future<void> _open(int i, {double progress = 0}) async {
    setState(() {
      _ready = false;
      _error = null;
    });
    try {
      final c = await _load(i);
      if (!mounted) return;
      setState(() {
        _loaded
          ..clear()
          ..add(c);
        _ci = i;
        _ready = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && progress > 0) _scroll.jumpTo(_scroll.position.maxScrollExtent * progress.clamp(0, 1));
      });
      await _save();
    } catch (e) {
      if (mounted) setState(() => _error = '发生错误: $e');
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loaded.isEmpty) return;
    final p = _scroll.position;
    if (p.pixels > p.maxScrollExtent - 600) _appendNext();
    // The chapter whose header is above the viewport top is the current one.
    var cur = _loaded.first.index;
    for (final c in _loaded) {
      final ctx = _keys[c.index]?.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= 80) cur = c.index;
    }
    if (cur != _ci) {
      setState(() => _ci = cur);
      _save();
    }
  }

  Future<void> _appendNext() async {
    final next = _loaded.last.index + 1;
    if (_loadingMore || next >= _chapters.length) return;
    _loadingMore = true;
    try {
      final c = await _load(next);
      if (mounted) setState(() => _loaded.add(c));
    } catch (e) {
      Toast.show('预加载图片时出错: $e');
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _save() async {
    if (!_ready || _chapters.isEmpty) return;
    double pos = 0;
    if (_scroll.hasClients && _loaded.length == 1 && _scroll.position.maxScrollExtent > 0) {
      pos = (_scroll.offset / _scroll.position.maxScrollExtent).clamp(0, 1);
    }
    try {
      await _api.saveProgress(chapterIndex: _ci, pos: pos);
      SourceEvents.fire(SourceEvents.saveRead, _api.book);
    } catch (_) {}
  }

  Widget _image(BookChapter chapter, String src) {
    final hook = ComicView.imageBytes;
    Widget err(BuildContext _, Object _, StackTrace? _) => const SizedBox(height: 200, child: Center(child: Icon(Icons.broken_image)));
    if (src.startsWith('http')) {
      if (hook != null) {
        return FutureBuilder<Uint8List>(
          future: hook(widget.book, chapter, src),
          builder: (context, s) => s.hasData
              ? Image.memory(s.data!, width: double.infinity, fit: BoxFit.fitWidth)
              : const SizedBox(height: 300, child: Center(child: CircularProgressIndicator())),
        );
      }
      return Image.network(src, width: double.infinity, fit: BoxFit.fitWidth, errorBuilder: err);
    }
    return Image.file(File(src), width: double.infinity, fit: BoxFit.fitWidth, errorBuilder: err);
  }

  void _catalog() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: _chapters.length,
        itemBuilder: (_, i) => ListTile(
          selected: i == _ci,
          title: Text(_chapters[i].name),
          onTap: () {
            Navigator.pop(ctx);
            _open(i);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = _night ? Colors.black : Colors.white;
    Widget body;
    if (_error != null) {
      body = Center(
        child: Text(_error!, style: TextStyle(color: _night ? Colors.white70 : Colors.black87)),
      );
    } else if (!_ready) {
      body = const Center(child: Text('内容加载中...'));
    } else {
      final children = <Widget>[];
      for (final c in _loaded) {
        final chapter = _chapters[c.index];
        children.add(
          Padding(
            key: _keys.putIfAbsent(c.index, GlobalKey.new),
            padding: const EdgeInsets.all(8),
            child: Text(c.title, style: TextStyle(color: _night ? Colors.white54 : Colors.black54)),
          ),
        );
        for (var k = 0; k < c.images.length; k++) {
          children.add(
            GestureDetector(
              onLongPress: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GalleryViewerPage(images: c.images, initialIndex: k),
                ),
              ),
              child: _image(chapter, c.images[k]),
            ),
          );
        }
      }
      if (_loaded.last.index + 1 >= _chapters.length) {
        children.add(
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('已经到底了')),
          ),
        );
      }
      body = ListView(controller: _scroll, children: children);
      if (_zoom) {
        // 允许双指缩小或者放大内容（连点两下可恢复）
        body = GestureDetector(
          onDoubleTap: () => _zoomCtl.value = Matrix4.identity(),
          child: InteractiveViewer(transformationController: _zoomCtl, minScale: 0.5, maxScale: 4, panEnabled: false, child: body),
        );
      }
    }
    final title = _chapters.isEmpty || _ci >= _chapters.length ? widget.book.name : _chapters[_ci].name;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(onTap: () => setState(() => _menu = !_menu), child: body),
            ),
            if (_menu)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  elevation: 4,
                  child: SafeArea(
                    bottom: false,
                    child: ListTile(
                      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).maybePop()),
                      title: Text(widget.book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ),
            if (_menu)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Material(
                  elevation: 4,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _menuSlider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            TextButton(onPressed: _ci > 0 ? () => _open(_ci - 1) : null, child: const Text('上一话')),
                            TextButton(onPressed: _catalog, child: const Text('目录')),
                            TextButton(
                              onPressed: () {
                                setState(() => _night = !_night);
                                Toast.show(_night ? '已切换到夜间模式' : '已切换到白天模式');
                              },
                              child: Text(_night ? '白天' : '夜间'),
                            ),
                            TextButton(
                              onPressed: _ci + 1 < _chapters.length
                                  ? () {
                                      Toast.show('正在前往下一章');
                                      _open(_ci + 1);
                                    }
                                  : null,
                              child: const Text('下一话'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
