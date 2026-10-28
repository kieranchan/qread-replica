// widget/book/booklist.dart — `BookList`: measures the available width (LayoutBuilder, closure 0x5f15f8) and hands everything to
// [BookList2]; this is the widget the pages instantiate (shelf `bookshelf_list…`, search `search_list`, discovery `found_list`,
// backbook `backbook`).
import 'package:flutter/material.dart';

import '../../models/book.dart';
import 'booklist2.dart';

export 'booklist2.dart' show relativeTime, unreadCount, sourceName;

class BookList extends StatelessWidget {
  final List<Book> books;
  final bool islist;
  final bool isedit;
  final bool isbookshelf;
  final bool ishistory;
  final bool showBookTypeOnCover;
  final Set<String> selected;
  final Set<String> updating;
  final Set<String> cancelled;
  final bool hasMore;
  final bool isLoading;
  final ScrollController? scrollController;
  final ValueChanged<Book>? onTap;
  final ValueChanged<Book>? showBookOperations;
  final ValueChanged<String>? toggleSourceSelection;
  final VoidCallback? onLoadMore;
  final double bottom;
  final Future<void> Function(Book dragged, Book target)? moveCallback;

  const BookList({
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
    this.scrollController,
    this.onTap,
    this.showBookOperations,
    this.toggleSourceSelection,
    this.onLoadMore,
    this.bottom = 0,
    this.moveCallback,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => BookList2(
        books: books,
        islist: islist,
        isedit: isedit,
        isbookshelf: isbookshelf,
        ishistory: ishistory,
        showBookTypeOnCover: showBookTypeOnCover,
        selected: selected,
        updating: updating,
        cancelled: cancelled,
        hasMore: hasMore,
        isLoading: isLoading,
        maxWidth: c.maxWidth,
        scrollController: scrollController,
        onTap: onTap,
        showBookOperations: showBookOperations,
        toggleSourceSelection: toggleSourceSelection,
        onLoadMore: onLoadMore,
        bottom: bottom,
        moveCallback: moveCallback,
      ),
    );
  }
}
