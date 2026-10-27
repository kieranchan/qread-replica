// read/util/listcontroller.dart — `ReadListController`: the window of chapters shown by the scroll-mode reader.
//
// Original: `ReadListController` (`ReadSetting.controller` 0x2e0, 31 reads of the VIP flag for the custom header/footer) plus
// `InfiniteScrollController` / `_InfiniteScrollPosition` (widget/read/list.dart) that let the list grow at both ends without jumping.
// This port uses fixed-height items (one page body each): prepending a chapter shifts the scroll offset by `pages * itemExtent`,
// which keeps the visible text in place.
import 'package:flutter/widgets.dart';

import '../model/page.dart';
import 'list_content.dart';

class ReadListController extends ChangeNotifier {
  final ScrollController scroll;
  final List<ListContent> items = [];

  /// Height of one item (the page body); set by the list when it lays out.
  double itemExtent = 1;

  ReadListController({ScrollController? scroll}) : scroll = scroll ?? ScrollController();

  bool get isEmpty => items.isEmpty;

  int get firstChapter => items.isEmpty ? -1 : items.first.chapterIndex;
  int get lastChapter => items.isEmpty ? -1 : items.last.chapterIndex;

  bool hasChapter(int ci) => items.any((e) => e.chapterIndex == ci);

  static List<ListContent> _itemsOf(int ci, String name, List<PageText> pages) => [
        for (var i = 0; i < pages.length; i++)
          ListContent(chapterIndex: ci, pageIndex: i, page: pages[i], chapterName: name, totalPage: pages.length),
      ];

  /// Replaces everything with one chapter and scrolls to [pageIndex].
  void reset(int ci, String name, List<PageText> pages, {int pageIndex = 0}) {
    items
      ..clear()
      ..addAll(_itemsOf(ci, name, pages));
    notifyListeners();
    _jump(pageIndex * itemExtent);
  }

  void append(int ci, String name, List<PageText> pages) {
    if (hasChapter(ci)) return;
    items.addAll(_itemsOf(ci, name, pages));
    notifyListeners();
  }

  /// Inserts a chapter in front and keeps the visible text in place.
  void prepend(int ci, String name, List<PageText> pages) {
    if (hasChapter(ci)) return;
    items.insertAll(0, _itemsOf(ci, name, pages));
    notifyListeners();
    if (scroll.hasClients) _jump(scroll.offset + pages.length * itemExtent);
  }

  void _jump(double offset) {
    if (!scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
      });
      return;
    }
    scroll.jumpTo(offset.clamp(0, scroll.position.hasContentDimensions ? scroll.position.maxScrollExtent : offset));
  }

  /// Index of the item at the top of the viewport (the one whose top third is visible).
  int get topIndex {
    if (items.isEmpty || !scroll.hasClients || itemExtent <= 1) return 0;
    return ((scroll.offset + itemExtent * 0.3) / itemExtent).floor().clamp(0, items.length - 1);
  }

  ListContent? get top => items.isEmpty ? null : items[topIndex];

  /// Scrolls to page [pageIndex] of chapter [ci] (when it is in the window).
  bool jumpTo(int ci, int pageIndex) {
    final i = items.indexWhere((e) => e.chapterIndex == ci && e.pageIndex == pageIndex);
    if (i < 0) return false;
    _jump(i * itemExtent);
    return true;
  }

  /// Scrolls by one screen (tap zones / volume keys in scroll mode).
  Future<void> page(int delta, {Duration duration = const Duration(milliseconds: 250)}) async {
    if (!scroll.hasClients) return;
    final target = (scroll.offset + delta * itemExtent * 0.9).clamp(0.0, scroll.position.maxScrollExtent);
    if (duration == Duration.zero) {
      scroll.jumpTo(target);
    } else {
      await scroll.animateTo(target, duration: duration, curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }
}
