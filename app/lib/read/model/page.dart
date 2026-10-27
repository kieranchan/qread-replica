// read/model/page.dart — pages of a laid-out chapter. Recovered from `read/model/page.dart`, the allocation sites in
// `CalculateChapter` (0x236954, 0x23ae00, 0x23ae78, 0xeb964c) and the JSON of `MyPage` (0x228d80 / 0x228fac / 0x51a9d4 /
// 0x51acb4). JSON keys are the original's:
//   PageText {content:[Content], height, lineheight, iscentos}      (+ this port's `start`, `end`)
//   Content  {text:[Line], height, type, line, fit}
//
// A [PageText] is what fits on one page (or one column in double-column mode). Pages come out of [CalculateChapter].
import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show BoxFit;

import '../../models/_json.dart';
import 'line.dart';

/// Where a character range sits in a laid-out chapter (selection, search hit, note anchor).
/// 7 slots in the original (size 0x40); the meaning of the slots is not recoverable, so this is the natural tuple.
/// TODO(asm class 1479 PitchInfo): field meanings.
class PitchInfo {
  final int page;
  final int content;
  final int line;
  final int cline;
  final int start;
  final int end;
  final int offsetInRun;

  const PitchInfo({
    this.page = 0,
    this.content = 0,
    this.line = 0,
    this.cline = 0,
    this.start = 0,
    this.end = 0,
    this.offsetInRun = 0,
  });

  @override
  String toString() => 'PitchInfo(page $page, content $content, line $line, cline $cline, $start-$end)';
}

/// An image to be placed in a chapter: path (or `data:` URI) and its intrinsic size.
/// The original keeps only one slot (class 1480 ImageData, 0x10 bytes: the decoded image / cache entry); the layout engine
/// only needs the size.
class ImageData {
  final String src;
  final double width;
  final double height;

  const ImageData({required this.src, required this.width, required this.height});

  Size get size => Size(width, height);
}

/// One layout input element (class 1481 `CalcuPages`: a payload and an int `type` where `1` = image, see 0x240794).
/// [runs] are the styled runs of one paragraph (type 0) or a single image run (type 1).
class CalcuPages {
  final List<CLine> runs;
  final int type;

  const CalcuPages(this.runs, [this.type = CLineType.text]);

  factory CalcuPages.text(List<CLine> runs) => CalcuPages(runs, CLineType.text);

  factory CalcuPages.image(CLine image) => CalcuPages([image], CLineType.image);

  bool get isImage => type == CLineType.image;
}

/// Class 1482 `Content`: a block on a page, one paragraph chunk (type 0) or one image (type 1).
/// Field order in the original: lines, height, type (`[0]`), line (count), fit.
class Content {
  List<Line> lines;

  /// Height of the block without the gap to the next block.
  double height;

  /// 0 = text, 1 = image ([CLineType]).
  int type;

  /// Number of lines (used to spread the page's spare height, see [PageText.lineheight]).
  int line;

  BoxFit fit;

  Content({List<Line>? lines, this.height = 0, this.type = CLineType.text, this.line = 0, this.fit = BoxFit.contain}) : lines = lines ?? <Line>[];

  bool get isImage => type == CLineType.image;

  String get text => lines.map((l) => l.text).join();

  factory Content.fromJson(Map<String, dynamic> json) {
    final fit = jInt(json['fit']);
    return Content(
      lines: jList(json['text']).map((e) => Line.fromJson(jMap(e))).toList(),
      height: jDouble(json['height']),
      type: jInt(json['type']),
      line: jInt(json['line']),
      fit: fit >= 0 && fit < BoxFit.values.length ? BoxFit.values[fit] : BoxFit.contain,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': lines.map((l) => l.toJson()).toList(),
        'height': height,
        'type': type,
        'line': line,
        'fit': fit.index,
      };
}

/// Class 1483 `PageText`: the content of one page (or column).
class PageText {
  List<Content> contents;

  /// Height used by the contents (without the gaps between them).
  double height;

  /// Extra height added after every body line (not the title block, whose lines have `paragraphIndex < 0`) so that a nearly
  /// full page ends flush with the bottom margin (vertical justification; `0` on the last page of a chapter and on pages
  /// with images). Key `lineheight` in the original.
  double lineheight;

  /// Page without body text: the volume-title page and the blank page appended in double-column mode (key `iscentos`;
  /// the UI centres the content vertically).
  bool iscentos;

  /// First / last source offset shown on the page (this port's addition; `end` is exclusive). Used for the
  /// page <-> offset mapping that keeps reading progress across layout changes.
  int start;
  int end;

  PageText({List<Content>? contents, this.height = 0, this.lineheight = 0, this.iscentos = false, this.start = 0, this.end = 0})
      : contents = contents ?? <Content>[];

  bool get isEmpty => contents.isEmpty;

  int get lineCount => contents.fold(0, (n, c) => n + c.lines.length);

  Iterable<Line> get lines sync* {
    for (final c in contents) {
      yield* c.lines;
    }
  }

  String get text => contents.map((c) => c.text).join('\n');

  factory PageText.fromJson(Map<String, dynamic> json) => PageText(
        contents: jList(json['content']).map((e) => Content.fromJson(jMap(e))).toList(),
        height: jDouble(json['height']),
        lineheight: jDouble(json['lineheight']),
        iscentos: jBool(json['iscentos']),
        start: jInt(json['start']),
        end: jInt(json['end']),
      );

  Map<String, dynamic> toJson() => {
        'content': contents.map((c) => c.toJson()).toList(),
        'height': height,
        'lineheight': lineheight,
        'iscentos': iscentos,
        'start': start,
        'end': end,
      };
}
