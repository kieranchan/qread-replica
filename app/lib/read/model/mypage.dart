// read/model/mypage.dart — one screen of the novel reader (class 1484 `MyPage`, JSON by 0x228a3c / 0x51a468).
// JSON keys: chapterName text text2 ispad currentChapterIndex bigtitle pageNum totalPage progress isFirstPageOfChapter isVolume
// backgroundImage. `text` / `text2` are [PageText] (left column / right column in double-column mode).
import '../../models/_json.dart';
import 'page.dart';

class MyPage {
  String chapterName;
  PageText text;

  /// Second column (double-column mode); null in single-column mode.
  PageText? text2;

  /// Laid out for the tablet profile (`BackGround.ispad`).
  bool ispad;
  int currentChapterIndex;

  /// `bigtitle` (double). Every page builder of the original stores 0 (0x229ecc, 0x22a1c0, 0x25e4e0, 0x573c5c); only the JSON reader
  /// (0x228a3c / 0x51a934) fills it from a saved page. Kept for the JSON round trip.
  double bigtitle;

  /// 1-based page number inside the chapter and the number of pages of the chapter.
  int pageNum;
  int totalPage;

  /// Reading progress through the chapter, 0..1 (fraction of the chapter text, see [CalculateChapter.progressForPage]).
  double progress;
  bool isFirstPageOfChapter;
  bool isVolume;
  String? backgroundImage;

  MyPage({
    this.chapterName = '',
    PageText? text,
    this.text2,
    this.ispad = false,
    this.currentChapterIndex = 0,
    this.bigtitle = 0,
    this.pageNum = 1,
    this.totalPage = 1,
    this.progress = 0,
    this.isFirstPageOfChapter = false,
    this.isVolume = false,
    this.backgroundImage,
  }) : text = text ?? PageText();

  /// Builds the screen for page [index] of [pages] (the output of [CalculateChapter]). With [columns] == 2 the screen shows
  /// pages `index` and `index + 1` side by side; [index] is rounded down to an even page.
  factory MyPage.fromPages({
    required List<PageText> pages,
    required int index,
    required int chapterIndex,
    required String chapterName,
    int columns = 1,
    bool isVolume = false,
    bool ispad = false,
    String? backgroundImage,
    double progress = 0,
  }) {
    if (pages.isEmpty) {
      return MyPage(chapterName: chapterName, currentChapterIndex: chapterIndex, isVolume: isVolume, ispad: ispad, backgroundImage: backgroundImage);
    }
    var i = index.clamp(0, pages.length - 1);
    if (columns == 2) i -= i % 2;
    final first = pages[i];
    final second = columns == 2 && i + 1 < pages.length ? pages[i + 1] : null;
    var title = 0.0;
    if (i == 0 && first.contents.isNotEmpty) {
      final c = first.contents.first;
      if (c.lines.isNotEmpty && c.lines.first.paragraphIndex < 0) title = c.height;
    }
    return MyPage(
      chapterName: chapterName,
      text: first,
      text2: second,
      ispad: ispad,
      currentChapterIndex: chapterIndex,
      bigtitle: title,
      pageNum: i + 1,
      totalPage: pages.length,
      progress: progress,
      isFirstPageOfChapter: i == 0,
      isVolume: isVolume,
      backgroundImage: backgroundImage,
    );
  }

  factory MyPage.fromJson(Map<String, dynamic> json) => MyPage(
        chapterName: jStr(json['chapterName']),
        text: PageText.fromJson(jMap(json['text'])),
        text2: json['text2'] == null ? null : PageText.fromJson(jMap(json['text2'])),
        ispad: jBool(json['ispad']),
        currentChapterIndex: jInt(json['currentChapterIndex']),
        bigtitle: jDouble(json['bigtitle']),
        pageNum: jInt(json['pageNum'], 1),
        totalPage: jInt(json['totalPage'], 1),
        progress: jDouble(json['progress']),
        isFirstPageOfChapter: jBool(json['isFirstPageOfChapter']),
        isVolume: jBool(json['isVolume']),
        backgroundImage: json['backgroundImage'] == null ? null : jStr(json['backgroundImage']),
      );

  Map<String, dynamic> toJson() => {
        'chapterName': chapterName,
        'text': text.toJson(),
        'text2': text2?.toJson(),
        'ispad': ispad,
        'currentChapterIndex': currentChapterIndex,
        'bigtitle': bigtitle,
        'pageNum': pageNum,
        'totalPage': totalPage,
        'progress': progress,
        'isFirstPageOfChapter': isFirstPageOfChapter,
        'isVolume': isVolume,
        'backgroundImage': backgroundImage,
      };
}
