// widget/book/booklist2.dart — `BookList2`: the book grid / list used by the shelf, search results, discovery lists and the history.
//
// Original (`_BookListState` of booklist2.dart): grid cells (sub_5a1544: cover with the unread badge `99+` and the type pill of
// sub_5a12e8) and list rows (sub_5a32b4: cover, name, `作者 • 共N章`, `已读：…`, `最新：…`, `来源：…`, the update state
// 「更新中」/「已取消」, word count `0万字`, relative time `N天前/小时前/分钟前` of sub_5a55ec); a footer
// 「没有更多数据了」 when the list pages (`hasMore` false), a spinner while `isLoading`; in edit mode (`isedit`) a tap toggles
// the selection (`toggleSourceSelection`). Columns come from `bookshelfColumns(2)` (0 = automatic) and the size from the
// shelf scale settings.
import 'package:flutter/material.dart';

import '../../data/source.dart';
import '../../models/book.dart';
import '../book_page.dart';
import '../image/cached_cover_image.dart';
import 'shelf_prefs.dart';

/// `N天前` / `N小时前` / `N分钟前` (sub_5a55ec); empty for 0.
String relativeTime(int ms, {DateTime? now}) {
  if (ms <= 0) return '';
  final d = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inDays > 0) return '${d.inDays}天前';
  if (d.inHours > 0) return '${d.inHours}小时前';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes}分钟前';
}

/// Unread chapters after the reading position.
int unreadCount(Book b) {
  final n = b.totalChapterNum - b.durChapterIndex - 1;
  return n < 0 ? 0 : n;
}

/// The source name shown as 「来源：」.
String sourceName(Book b) {
  if (isLocalShelfBook(b)) return '本地';
  final m = Sourcedata.byUrl(b.origin);
  final n = m == null ? '' : '${m['bookSourceName'] ?? ''}';
  return n.isNotEmpty ? n : b.origin;
}

class BookList2 extends StatefulWidget {
  final List<Book> books;
  final bool islist;
  final bool isedit;
  final bool isbookshelf;
  final bool ishistory;
  final bool showBookTypeOnCover;
  final Set<String> selected;

  /// Books whose update check is running / was cancelled (「更新中」 / 「已取消」).
  final Set<String> updating;
  final Set<String> cancelled;
  final bool hasMore;
  final bool isLoading;
  final double maxWidth;
  final ScrollController? scrollController;
  final ValueChanged<Book>? onTap;
  final ValueChanged<Book>? showBookOperations;
  final ValueChanged<String>? toggleSourceSelection;
  final VoidCallback? onLoadMore;

  /// Extra space at the bottom (the floating tab bar of the main page).
  final double bottom;

  /// Drag to reorder (手动排序): every item is a `DragTarget<Book>` around a `LongPressDraggable<Book>` (500 ms, the dragged
  /// item stays at opacity 0.4, closures 0x5a7358 / 0x5a6e68); dropping book A on book B calls `moveCallback(A, B)`. A long press
  /// that is released without moving still opens the book operations.
  final Future<void> Function(Book dragged, Book target)? moveCallback;

  const BookList2({
    super.key,
    required this.books,
    this.islist = false,
    this.isedit = false,
    this.isbookshelf = false,
    this.ishistory = false,
    this.showBookTypeOnCover = true,
    this.selected = const {},
    this.updating = const {},
    this.cancelled = const {},
    this.hasMore = false,
    this.isLoading = false,
    this.maxWidth = 400,
    this.scrollController,
    this.onTap,
    this.showBookOperations,
    this.toggleSourceSelection,
    this.onLoadMore,
    this.bottom = 0,
    this.moveCallback,
  });

  @override
  State<BookList2> createState() => _BookListState();
}

class _BookListState extends State<BookList2> {
  void _tap(Book b) {
    if (widget.isedit) {
      widget.toggleSourceSelection?.call(b.bookUrl);
    } else {
      widget.onTap?.call(b);
    }
  }

  bool _loadRequested = false;

  /// Wraps an item for drag-to-reorder when [BookList2.moveCallback] is set (not in edit mode).
  Widget _draggable(Book b, Widget child, double width) {
    final move = widget.moveCallback;
    if (move == null || widget.isedit) return child;
    return DragTarget<Book>(
      key: Key('drop_${b.bookUrl}'),
      onWillAcceptWithDetails: (d) => d.data.bookUrl != b.bookUrl,
      onAcceptWithDetails: (d) => move(d.data, b),
      builder: (context, candidates, rejected) => LongPressDraggable<Book>(
        data: b,
        delay: const Duration(milliseconds: 500),
        hapticFeedbackOnStart: true,
        feedback: Material(color: Colors.transparent, child: SizedBox(width: width, child: Opacity(opacity: 0.9, child: child))),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        onDragEnd: (d) {
          if (!d.wasAccepted && _moved < 12) widget.showBookOperations?.call(b);
        },
        child: Listener(
          onPointerDown: (e) {
            _down = e.position;
            _moved = 0;
          },
          onPointerMove: (e) {
            final m = (e.position - _down).distance;
            if (m > _moved) _moved = m;
          },
          child: candidates.isEmpty
              ? child
              : DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(8)),
                  child: child,
                ),
        ),
      ),
    );
  }

  Offset _down = Offset.zero;
  double _moved = 0;

  bool _onScroll(ScrollNotification n) {
    final more = widget.onLoadMore;
    if (more != null && widget.hasMore && !widget.isLoading && !_loadRequested && n.metrics.extentAfter < 300) {
      // scroll notifications can arrive during layout: ask for the next page after this frame
      _loadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadRequested = false;
        if (mounted) more();
      });
    }
    return false;
  }

  Widget _footer() {
    if (widget.isLoading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (widget.onLoadMore != null && !widget.hasMore && widget.books.isNotEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('没有更多数据了', style: TextStyle(color: Colors.grey))));
    }
    return const SizedBox.shrink();
  }

  Widget _badge(Book b, {bool small = false}) {
    if (!widget.isbookshelf) return const SizedBox.shrink();
    final mode = ShelfPrefs.unreadMode;
    final n = unreadCount(b);
    if (mode == ShelfPrefs.unreadHidden || (n == 0 && !b.isredupdate)) return const SizedBox.shrink();
    if (mode != ShelfPrefs.unreadFull || n == 0) {
      return Container(key: Key('dot_${b.bookUrl}'), width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle));
    }
    return Container(
      key: Key('unread_${b.bookUrl}'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
      child: Text(n > 99 ? '99+' : '$n', style: TextStyle(color: Colors.white, fontSize: small ? 9 : 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _typePill(Book b) {
    if (!widget.showBookTypeOnCover || b.type_ == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
      child: Text(bookTypeLabel(b.type_), style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }

  Widget _check(Book b) {
    if (!widget.isedit) return const SizedBox.shrink();
    final on = widget.selected.contains(b.bookUrl);
    return Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, key: Key('sel_${b.bookUrl}'), color: on ? Theme.of(context).colorScheme.primary : Colors.white);
  }

  Widget _cover(Book b, double w, double h) {
    final shadow = ShelfPrefs.coverShadow;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: shadow ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(1, 2))] : null,
      ),
      child: CachedCoverImage(url: b.coverUrl, title: b.name, author: b.author, width: w, height: h, borderRadius: BorderRadius.circular(6)),
    );
  }

  Widget _gridItem(Book b, double w) {
    final h = w * 4 / 3;
    return InkWell(
      key: Key('book_${b.bookUrl}'),
      onTap: () => _tap(b),
      onLongPress: widget.isedit || widget.moveCallback != null ? null : () => widget.showBookOperations?.call(b),
      borderRadius: BorderRadius.circular(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          _cover(b, w, h),
          Positioned(right: 3, top: 3, child: _badge(b)),
          Positioned(left: 3, bottom: 3, child: _typePill(b)),
          if (widget.updating.contains(b.bookUrl))
            const Positioned(left: 3, top: 3, child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
          Positioned(right: 4, bottom: 4, child: _check(b)),
        ]),
        const SizedBox(height: 4),
        Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.2)),
      ]),
    );
  }

  Widget _listItem(Book b, double scale) {
    final theme = Theme.of(context);
    final grey = TextStyle(fontSize: 12 * scale, color: theme.colorScheme.onSurfaceVariant);
    final cw = 60.0 * scale;
    final status = widget.updating.contains(b.bookUrl) ? '更新中' : (widget.cancelled.contains(b.bookUrl) ? '已取消' : '');
    final time = relativeTime(widget.ishistory ? b.durChapterTime : (b.latestChapterTime > 0 ? b.latestChapterTime : b.durChapterTime));
    return InkWell(
      key: Key('book_${b.bookUrl}'),
      onTap: () => _tap(b),
      onLongPress: widget.isedit || widget.moveCallback != null ? null : () => widget.showBookOperations?.call(b),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8 * scale),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            _cover(b, cw, cw * 4 / 3),
            Positioned(left: 2, bottom: 2, child: _typePill(b)),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.w600))),
                if (status.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                    child: Text(status, style: TextStyle(fontSize: 10 * scale)),
                  ),
                _badge(b),
                _check(b),
              ]),
              const SizedBox(height: 3),
              Text('${b.author.isEmpty ? '未知' : b.author}${b.totalChapterNum > 0 ? ' • 共${b.totalChapterNum}章' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: grey),
              if (widget.isbookshelf || widget.ishistory)
                Text('已读：${b.durChapterTitle.isEmpty ? '未知' : b.durChapterTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: grey),
              Text('最新：${b.latestChapterTitle.isEmpty ? '未知' : b.latestChapterTitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: grey),
              Row(children: [
                Expanded(child: Text('来源：${sourceName(b)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: grey)),
                if (b.wordCount.isNotEmpty) Text(' ${b.wordCount}', style: grey),
                if (time.isNotEmpty) Text(' $time', style: grey),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.maxWidth.isFinite && widget.maxWidth > 0 ? widget.maxWidth : 400.0;
    final count = widget.books.length + 1;
    Widget list;
    if (widget.islist) {
      final scale = ShelfPrefs.listScale / 100;
      final cols = ShelfPrefs.listColumns > 0 ? ShelfPrefs.listColumns : (w / (420 * scale)).floor().clamp(1, 4);
      if (cols == 1) {
        list = ListView.builder(
          controller: widget.scrollController,
          padding: EdgeInsets.only(bottom: widget.bottom),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: count,
          itemBuilder: (c, i) => i == widget.books.length ? _footer() : _draggable(widget.books[i], _listItem(widget.books[i], scale), w),
        );
      } else {
        list = GridView.builder(
          controller: widget.scrollController,
          padding: EdgeInsets.only(bottom: widget.bottom),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 112 * scale + 16),
          itemCount: widget.books.length,
          itemBuilder: (c, i) => _draggable(widget.books[i], _listItem(widget.books[i], scale), w / cols),
        );
      }
    } else {
      final scale = ShelfPrefs.gridScale / 100;
      final cols = ShelfPrefs.gridColumns > 0 ? ShelfPrefs.gridColumns : (w / (110 * scale)).floor().clamp(3, 12);
      final itemW = (w - 16 - (cols - 1) * 12) / cols;
      list = CustomScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 10,
                mainAxisExtent: itemW * 4 / 3 + 42,
              ),
              delegate: SliverChildBuilderDelegate((c, i) => _draggable(widget.books[i], _gridItem(widget.books[i], itemW), itemW),
                  childCount: widget.books.length),
            ),
          ),
          SliverToBoxAdapter(child: _footer()),
          SliverToBoxAdapter(child: SizedBox(height: widget.bottom)),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(onNotification: _onScroll, child: list);
  }
}
