// read/util/list_content.dart — one entry of the scroll-mode reader ("上下滚动"): a laid-out page of a chapter.
// Original: `list_content.dart` (the item model of `ReadListController`); this port keeps the chapter / page pair and the page itself.
import '../model/page.dart';

class ListContent {
  final int chapterIndex;
  final int pageIndex;
  final PageText page;

  /// Title of the chapter (shown in the fixed header while the item is on top).
  final String chapterName;

  /// Number of pages of the chapter.
  final int totalPage;

  const ListContent({required this.chapterIndex, required this.pageIndex, required this.page, required this.chapterName, required this.totalPage});
}
