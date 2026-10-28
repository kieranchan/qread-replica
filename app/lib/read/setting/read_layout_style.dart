// read/setting/read_layout_style.dart — everything about a reading theme that changes where lines break and where pages end.
//
// The original keeps these as fields of `ReadSetting` / the current `BackGround` (docs/SETTINGS.md: fontSize, lineHeight,
// letterSpacing, fontWeight12345, paragraphSpacing, kong, fen, titleAlign, titleTopMargin, topMargin ... ). The layout engine
// only needs a small immutable value, so the reader UI builds one from its settings ([ReadLayoutStyle.fromBackGround]) and
// hands it to [CalculateChapter]. Colours are not part of it: they do not change the layout.
import 'package:flutter/painting.dart';

import '../../models/back_ground.dart';
import '../../models/highlight_rule.dart';
import '../model/line.dart';

/// The metric part of a highlight rule (`fontSize` / `lineHeight` / `fontFamily`). The original wraps every match of a rule in
/// `<span style='rule:N'>` before the chapter is laid out (0xf0caec), so those values are part of the measured text; here the
/// layout engine splits the runs at the matches and tags them with the token `rule:N` (N = index in [ReadLayoutStyle.metricRules]).
class RuleMetric {
  final String pattern;
  final bool isRegex;

  /// CSS-like values as typed on the rule page (如 16px 或 1.2em / 如 1.5): '' = unchanged.
  final String fontSize;
  final String lineHeight;
  final String fontFamily;

  const RuleMetric({required this.pattern, this.isRegex = false, this.fontSize = '', this.lineHeight = '', this.fontFamily = ''});

  /// Enabled rules with a pattern and at least one metric value, in list order.
  static List<RuleMetric> fromRules(Iterable<HighlightRule> rules) => [
        for (final r in rules)
          if (r.isEnabled && r.pattern.isNotEmpty && (r.fontSize.trim().isNotEmpty || r.lineHeight.trim().isNotEmpty || r.fontFamily.trim().isNotEmpty))
            RuleMetric(pattern: r.pattern, isRegex: r.isRegex, fontSize: r.fontSize.trim(), lineHeight: r.lineHeight.trim(), fontFamily: r.fontFamily.trim()),
      ];

  /// Matches of this rule in [text]; an invalid regex matches nothing.
  Iterable<Match> matches(String text) {
    if (!isRegex) return pattern.allMatches(text);
    try {
      return RegExp(pattern, multiLine: true).allMatches(text);
    } catch (_) {
      return const [];
    }
  }

  /// `16px` / `16` -> 16, `1.2em` / `120%` -> relative to [base]; null when empty or not a number.
  static double? size(String v, double base) {
    final t = v.trim().toLowerCase();
    if (t.isEmpty) return null;
    double? n(String s) => double.tryParse(s.trim());
    if (t.endsWith('px')) return n(t.substring(0, t.length - 2));
    if (t.endsWith('em')) {
      final f = n(t.substring(0, t.length - 2));
      return f == null ? null : f * base;
    }
    if (t.endsWith('%')) {
      final f = n(t.substring(0, t.length - 1));
      return f == null ? null : f / 100 * base;
    }
    return n(t);
  }

  /// `1.5` -> 1.5 (a multiple of the font size); `24px` -> 24 / [fontSize]; `150%` -> 1.5.
  static double? height(String v, double fontSize) {
    final t = v.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.endsWith('px')) {
      final px = double.tryParse(t.substring(0, t.length - 2).trim());
      return px == null || fontSize <= 0 ? null : px / fontSize;
    }
    if (t.endsWith('%')) {
      final f = double.tryParse(t.substring(0, t.length - 1).trim());
      return f == null ? null : f / 100;
    }
    return double.tryParse(t);
  }

  String get signature => [pattern, isRegex, fontSize, lineHeight, fontFamily].join('\u0001');
}

class ReadLayoutStyle {
  /// Body font size in logical pixels (`BackGround.fontSize`).
  final double fontSize;

  /// Line height as a multiple of the font size (`BackGround.lineHeightN`).
  final double lineHeight;

  /// Extra space between letters (`BackGround.letterSpacing`).
  final double letterSpacing;

  final FontWeight fontWeight;
  final String? fontFamily;

  /// Gap between paragraphs in logical pixels (`BackGround.paragraphSpacing`).
  final double paragraphSpacing;

  /// First-line indent in full-width spaces (`BackGround.kong`, default 2; the original prepends `　　`).
  final int indent;

  /// Justify the text (the UI draws each content block with `TextAlign.justify`); does not change the line breaks.
  final bool justify;

  final double titleFontSize;
  final FontWeight titleFontWeight;
  final TextAlign titleAlign;
  final double titleTopMargin;
  final double titleBottomMargin;

  /// Page margins: margin + safe distance (+ header/footer height when they are shown).
  final EdgeInsets padding;

  /// 1 or 2 (`BackGround.fen`: 单列 / 双列). With 2, every [PageText] is one column and the UI shows two per screen.
  final int columns;
  final double columnGap;

  /// Spread the spare height of a nearly full page over its lines (the original's `PageText.lineheight`).
  final bool stretchPages;

  /// Highlight rules that change the font size / line height / family of their matches (measured with the text).
  final List<RuleMetric> metricRules;

  const ReadLayoutStyle({
    this.fontSize = 18,
    this.lineHeight = 1.6,
    this.letterSpacing = 0,
    this.fontWeight = FontWeight.w400,
    this.fontFamily,
    this.paragraphSpacing = 10,
    this.indent = 2,
    this.justify = true,
    this.titleFontSize = 26,
    this.titleFontWeight = FontWeight.w700,
    this.titleAlign = TextAlign.left,
    this.titleTopMargin = 0,
    this.titleBottomMargin = 20,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 20),
    this.columns = 1,
    this.columnGap = 24,
    this.stretchPages = true,
    this.metricRules = const [],
  });

  /// Maps the stored theme (`models/back_ground.dart`, defaults for unset zero values).
  factory ReadLayoutStyle.fromBackGround(BackGround b, {double columnGap = 24, bool justify = true, double headerHeight = 0, double footerHeight = 0}) {
    final w = b.fontWeight <= 0 ? 400 : b.fontWeight;
    final weight = FontWeight.values[((w / 100).round().clamp(1, 9)) - 1];
    final align = switch (b.titleAlign) {
      1 => TextAlign.center,
      2 => TextAlign.right,
      _ => TextAlign.left,
    };
    final fs = b.fontSize > 0 ? b.fontSize : 18.0;
    return ReadLayoutStyle(
      fontSize: fs,
      lineHeight: b.lineHeightN > 0 ? b.lineHeightN : 1.6,
      letterSpacing: b.letterSpacing,
      fontWeight: weight,
      fontFamily: b.fontFamily.isEmpty ? null : b.fontFamily,
      paragraphSpacing: b.paragraphSpacing,
      indent: b.kong < 0 ? 0 : b.kong,
      justify: justify,
      titleFontSize: b.titlefontSize > 0 ? b.titlefontSize.toDouble() : fs + 8,
      titleAlign: align,
      titleTopMargin: b.titleTopMargin.toDouble(),
      titleBottomMargin: b.titleBottomMargin.toDouble(),
      padding: EdgeInsets.fromLTRB(
        b.leftMargin.toDouble(),
        b.topMargin + b.topSafeDistance + headerHeight,
        b.rightMargin.toDouble(),
        b.bottomMargin + b.bottomSafeDistance + footerHeight,
      ),
      columns: b.fen == 2 ? 2 : 1,
      columnGap: columnGap,
    );
  }

  ReadLayoutStyle copyWith({
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    FontWeight? fontWeight,
    String? fontFamily,
    double? paragraphSpacing,
    int? indent,
    bool? justify,
    double? titleFontSize,
    FontWeight? titleFontWeight,
    TextAlign? titleAlign,
    double? titleTopMargin,
    double? titleBottomMargin,
    EdgeInsets? padding,
    int? columns,
    double? columnGap,
    bool? stretchPages,
    List<RuleMetric>? metricRules,
  }) =>
      ReadLayoutStyle(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        fontWeight: fontWeight ?? this.fontWeight,
        fontFamily: fontFamily ?? this.fontFamily,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
        indent: indent ?? this.indent,
        justify: justify ?? this.justify,
        titleFontSize: titleFontSize ?? this.titleFontSize,
        titleFontWeight: titleFontWeight ?? this.titleFontWeight,
        titleAlign: titleAlign ?? this.titleAlign,
        titleTopMargin: titleTopMargin ?? this.titleTopMargin,
        titleBottomMargin: titleBottomMargin ?? this.titleBottomMargin,
        padding: padding ?? this.padding,
        columns: columns ?? this.columns,
        columnGap: columnGap ?? this.columnGap,
        stretchPages: stretchPages ?? this.stretchPages,
        metricRules: metricRules ?? this.metricRules,
      );

  /// Font size multiplier for the style tokens of a paragraph (`h1` .. `h3`, `sup`, `sub`).
  static double scaleFor(Set<String> tokens) {
    if (tokens.contains(CLineStyle.h1)) return 1.4;
    if (tokens.contains(CLineStyle.h2)) return 1.25;
    if (tokens.contains(CLineStyle.h3)) return 1.1;
    return 1.0;
  }

  /// The metric-relevant [TextStyle] of a run (no colour: the UI adds colour, underline and link decoration).
  /// [scale] is the paragraph's heading scale; `sup`/`sub` shrink the run.
  TextStyle textStyle(Set<String> tokens, {double scale = 1.0, bool title = false}) {
    var size = (title ? titleFontSize : fontSize) * scale;
    if (tokens.contains(CLineStyle.sup) || tokens.contains(CLineStyle.sub)) size *= 0.7;
    final bold = title ? titleFontWeight : (tokens.contains(CLineStyle.bold) || scale > 1.0 ? _bolder(fontWeight) : fontWeight);
    var family = fontFamily;
    var height = lineHeight;
    final rule = title ? null : ruleOf(tokens);
    if (rule != null) {
      size = RuleMetric.size(rule.fontSize, size) ?? size;
      height = RuleMetric.height(rule.lineHeight, size) ?? height;
      if (rule.fontFamily.isNotEmpty) family = rule.fontFamily;
    }
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: bold,
      fontStyle: tokens.contains(CLineStyle.italic) ? FontStyle.italic : FontStyle.normal,
      height: height,
      leadingDistribution: TextLeadingDistribution.even,
      letterSpacing: letterSpacing,
    );
  }

  /// The metric rule of a run (`rule:N` token), or null.
  RuleMetric? ruleOf(Set<String> tokens) {
    if (metricRules.isEmpty) return null;
    for (final t in tokens) {
      if (!t.startsWith(CLineStyle.rulePrefix)) continue;
      final i = int.tryParse(t.substring(CLineStyle.rulePrefix.length));
      if (i != null && i >= 0 && i < metricRules.length) return metricRules[i];
    }
    return null;
  }

  /// Whether any run of [runs] carries a metric rule (its lines then take their own heights).
  bool hasRuleRuns(Iterable<CLine> runs) => metricRules.isNotEmpty && runs.any((r) => ruleOf(r.styles) != null);

  /// Forces every line of a paragraph to the same height whatever fonts the run falls back to (so that layout and drawing
  /// agree on the line pitch).
  /// With [grow] (a paragraph holding metric-rule runs) the strut is only the minimum line height, so a larger rule font makes
  /// its line taller, in the measurement and in the drawing alike.
  StrutStyle strut({double scale = 1.0, bool title = false, bool grow = false}) => StrutStyle(
        fontFamily: fontFamily,
        fontSize: (title ? titleFontSize : fontSize) * scale,
        height: lineHeight,
        leadingDistribution: TextLeadingDistribution.even,
        forceStrutHeight: !grow,
      );

  static FontWeight _bolder(FontWeight w) => w.value >= 600 ? w : FontWeight.w700;

  /// Page-independent part of the cache key ([Mykey.signature]): every field that affects line breaking or pagination.
  String get signature => [
        fontSize,
        lineHeight,
        letterSpacing,
        fontWeight.value,
        fontFamily ?? '',
        paragraphSpacing,
        indent,
        titleFontSize,
        titleFontWeight.value,
        titleAlign.index,
        titleTopMargin,
        titleBottomMargin,
        padding.left,
        padding.top,
        padding.right,
        padding.bottom,
        columns,
        columnGap,
        stretchPages ? 1 : 0,
        for (final r in metricRules) r.signature,
      ].join('|');
}
