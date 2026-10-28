// read/model/line.dart — the lines of a laid-out page. Recovered from `read/model/line.dart` and the JSON writers/readers
// in `read/model/mypage.dart` (CLine closure 0x22935c / 0x51b2dc, Line 0x22921c / 0x51b040). JSON keys are the original's.
//
//   Line   = one visual line of a page: a list of CLine runs (+ TTS/selection flags, index of the source paragraph)
//   CLine  = one styled run inside a line: text, style tokens, offsets into the chapter text, anchor id, link target
//
// Offsets (`start`/`end`) index the chapter text that was laid out ([CalculateChapter]); `-1` marks synthetic runs (the
// chapter title, which is not part of the body text, and inline images: a CLine of type image inside a text line, `str` '', like the
// original's type-1 CLines that 0x23d118 puts between the text CLines of a source line). Characters in [CLine.prefix] (the first-line
// indent, `　　`) have no source offset: `end - start == str.length` always holds for the source part.
import '../../models/_json.dart';

/// Style tokens carried by [CLine.style] (space separated). `style` is a String in the original JSON (`"style": ""`). In the original
/// it is the raw `style` attribute of the chapter's `<span style=…>` markup (0x23e740 cuts `<span\s+[^>]*>` … `</span>` into runs with
/// str / style / href / noteref, 0x23df10 builds the CLines; highlight rules add `rule:N`, 0xf0caec). This port's runs come from
/// ChapterContent blocks, so it keeps tokens instead of CSS text; `rule:N` is the same marker.
abstract class CLineStyle {
  static const String bold = 'bold';
  static const String italic = 'italic';
  static const String underline = 'underline';
  static const String strike = 'strike';
  static const String sup = 'sup';
  static const String sub = 'sub';
  static const String link = 'link';
  static const String code = 'code';
  static const String title = 'title';
  static const String h1 = 'h1';
  static const String h2 = 'h2';
  static const String h3 = 'h3';
  static const String center = 'center';
  static const String right = 'right';
  static const String image = 'image';

  /// `rule:N`: the run is a match of metric highlight rule N (the original's `<span style='rule:N'>`, 0xf0caec).
  static const String rulePrefix = 'rule:';

  static Set<String> parse(String style) => style.isEmpty ? <String>{} : style.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
}

/// `CLine.type`.
abstract class CLineType {
  static const int text = 0;
  static const int image = 1;
}

class CLine {
  String str;
  String style;
  int type;
  String id;
  int start;
  int end;
  bool isfirst;
  String href;
  bool noteref;

  /// "ish" in the original's CLine builder (0x236db8): the run belongs to a heading.
  bool ish;

  /// Text drawn before [str] that is not part of the chapter text (first-line indent). Key `prefix` as in 0x23df10.
  String prefix;

  CLine({
    this.str = '',
    this.style = '',
    this.type = CLineType.text,
    this.id = '',
    this.start = -1,
    this.end = -1,
    this.isfirst = false,
    this.href = '',
    this.noteref = false,
    this.ish = false,
    this.prefix = '',
  });

  bool get isImage => type == CLineType.image;

  /// Text as drawn (indent + body).
  String get text => '$prefix$str';

  Set<String> get styles => CLineStyle.parse(style);

  factory CLine.fromJson(Map<String, dynamic> json) => CLine(
        str: jStr(json['str']),
        style: jStr(json['style']),
        type: jInt(json['type']),
        id: jStr(json['id']),
        start: jInt(json['start'], -1),
        end: jInt(json['end'], -1),
        isfirst: jBool(json['isfirst']),
        href: jStr(json['href']),
        noteref: jBool(json['noteref']),
        ish: jBool(json['ish']),
        prefix: jStr(json['prefix']),
      );

  Map<String, dynamic> toJson() => {
        'str': str,
        'style': style,
        'type': type,
        'id': id,
        'start': start,
        'end': end,
        'isfirst': isfirst,
        'href': href,
        'noteref': noteref,
        if (ish) 'ish': ish,
        if (prefix.isNotEmpty) 'prefix': prefix,
      };

  CLine copy() => CLine(
        str: str,
        style: style,
        type: type,
        id: id,
        start: start,
        end: end,
        isfirst: isfirst,
        href: href,
        noteref: noteref,
        ish: ish,
        prefix: prefix,
      );

  @override
  String toString() => 'CLine($start-$end "$str")';
}

class Line {
  List<CLine> clines;

  /// TTS highlight: this line is being read aloud (set by the reader UI, never by the layout).
  bool isread;

  /// Original `istop`: UI/selection flag, never set by the layout.
  bool istop;

  /// Index of the source paragraph (block) in the chapter; `-1` for the title.
  int paragraphIndex;

  Line({List<CLine>? clines, this.isread = false, this.istop = false, this.paragraphIndex = 0}) : clines = clines ?? <CLine>[];

  String get text => clines.map((c) => c.text).join();

  /// First / last source offset on the line (-1 when the line is synthetic).
  int get start {
    for (final c in clines) {
      if (c.start >= 0) return c.start;
    }
    return -1;
  }

  int get end {
    for (var i = clines.length - 1; i >= 0; i--) {
      if (clines[i].end >= 0) return clines[i].end;
    }
    return -1;
  }

  factory Line.fromJson(Map<String, dynamic> json) => Line(
        clines: jList(json['lines']).map((e) => CLine.fromJson(jMap(e))).toList(),
        isread: jBool(json['isread']),
        istop: jBool(json['istop']),
        paragraphIndex: jInt(json['paragraphIndex']),
      );

  Map<String, dynamic> toJson() => {
        'lines': clines.map((c) => c.toJson()).toList(),
        'isread': isread,
        'istop': istop,
        'paragraphIndex': paragraphIndex,
      };

  @override
  String toString() => 'Line($start-$end "$text")';
}

/// `Gender` of the AI dialogue structures. The enum carries one int in the original (`field_8`).
/// Order from the const `ButtonSegment<Gender>`s of the character editor (objs: index 0 "男", 1 "女", 2 "未知").
enum Gender {
  male(0),
  female(1),
  unknown(2);

  final int value;
  const Gender(this.value);

  static Gender fromInt(int v) => Gender.values.firstWhere((g) => g.value == v, orElse: () => Gender.unknown);
}

/// One spoken fragment of a dialogue-analysed line (`AiZLine`, JSON read by 0xf06d64, written by 0x2a00d0).
class AiZLine {
  String id;
  String str;
  bool ispb;
  String name;
  int gender;
  String personality;

  AiZLine({this.id = '', this.str = '', this.ispb = false, this.name = '', this.gender = 0, this.personality = ''});

  Gender get genderEnum => Gender.fromInt(gender);

  factory AiZLine.fromJson(Map<String, dynamic> json) => AiZLine(
        id: jStr(json['id']),
        str: jStr(json['str']),
        ispb: jBool(json['ispb']),
        name: jStr(json['name']),
        gender: jInt(json['gender']),
        personality: jStr(json['personality']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'str': str,
        'ispb': ispb,
        'name': name,
        'gender': gender,
        'personality': personality,
      };
}

/// `AiCLine`: a run with the analysed fragments (`lines`) (JSON read by 0x81f5a4, written by 0x29ff90).
class AiCLine {
  String str;
  String id;
  int type;
  List<AiZLine> lines;

  AiCLine({this.str = '', this.id = '', this.type = 0, List<AiZLine>? lines}) : lines = lines ?? <AiZLine>[];

  factory AiCLine.fromJson(Map<String, dynamic> json) => AiCLine(
        str: jStr(json['str']),
        id: jStr(json['id']),
        type: jInt(json['type']),
        lines: jList(json['lines']).map((e) => AiZLine.fromJson(jMap(e))).toList(),
      );

  Map<String, dynamic> toJson() => {
        'str': str,
        'id': id,
        'type': type,
        'lines': lines.map((e) => e.toJson()).toList(),
      };
}

/// `AiLine`: a dialogue-analysed line (JSON read by 0x81f338, written by 0x2a14fc).
class AiLine {
  List<AiCLine> lines;
  bool isread;
  bool istop;

  AiLine({List<AiCLine>? lines, this.isread = false, this.istop = false}) : lines = lines ?? <AiCLine>[];

  factory AiLine.fromJson(Map<String, dynamic> json) => AiLine(
        lines: jList(json['lines']).map((e) => AiCLine.fromJson(jMap(e))).toList(),
        isread: jBool(json['isread']),
        istop: jBool(json['istop']),
      );

  Map<String, dynamic> toJson() => {
        'lines': lines.map((e) => e.toJson()).toList(),
        'isread': isread,
        'istop': istop,
      };
}
