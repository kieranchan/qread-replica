// pages/read/pages/novel/content.dart — one screen of the novel reader: background, header line, the laid-out text of a [MyPage]
// (one or two columns), footer line (time, battery, progress).
//
// Original: `ContentPageState` (93 KB; strings 我的 / 内容加载中... / 充电中 / 分页中). The original paints with its own painters and
// custom header/footer slots (`customHeaderLeft` ... ids, member feature); this port draws each content block with a `Text.rich` that uses
// the exact styles and strut of the layout engine, so line breaks match the pagination and the text is selectable. Header = chapter
// title, footer = time + battery on the left and the progress (`showProgress`) on the right.
// TODO(asm 0x1010228): custom header/footer slot items (member feature) are not rendered; the default layout is.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../read/model/mypage.dart';
import '../../../../read/model/page.dart';
import '../../../../read/setting/read_layout_style.dart';
import '../../../../read/setting/read_setting.dart';
import '../../../../read/util/content_painter.dart';
import '../../../../read/util/highlight_apply.dart';
import 'views/battery_painter.dart';

typedef BlockDecorator = List<TextDeco> Function(Content block, int chapterIndex);

/// Long press on the text: chapter index, chapter-text offset under the finger, global position.
typedef TextLongPress = void Function(int chapterIndex, int offset, Offset globalPosition);

/// Formats the progress text of the footer.
String progressText(int mode, {required int pageNum, required int totalPage, required double bookProgress}) {
  final chapter = '$pageNum/$totalPage';
  final book = '${(bookProgress * 100).clamp(0, 100).toStringAsFixed(1)}%';
  return switch (mode) {
    ProgressMode.hidden => '',
    ProgressMode.chapter => chapter,
    ProgressMode.book => book,
    _ => '$chapter  $book',
  };
}

String clockText([DateTime? now]) {
  final t = now ?? DateTime.now();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// The text of one [PageText] (one column), block by block.
class PageBody extends StatelessWidget {
  final PageText page;
  final ReadLayoutStyle style;
  final Color textColor;
  final double width;
  final int chapterIndex;
  final BlockDecorator? decorate;
  final TextLongPress? onLongPress;

  const PageBody({
    super.key,
    required this.page,
    required this.style,
    required this.textColor,
    required this.width,
    required this.chapterIndex,
    this.decorate,
    this.onLongPress,
  });

  Widget _image(String href, BoxFit fit) {
    if (href.startsWith('http')) return Image.network(href, fit: fit, errorBuilder: (_, _, _) => const SizedBox());
    if (href.isEmpty) return const SizedBox();
    return Image.file(File(href), fit: fit, errorBuilder: (_, _, _) => const SizedBox());
  }

  /// Chapter offset of the character under [local] in block [c] (-1 when none).
  int _offsetAt(Content c, Offset local) {
    final tp = TextPainter(
      text: HighlightApply.span(c, style, color: textColor),
      textAlign: HighlightApply.alignOf(c, style),
      strutStyle: HighlightApply.strutOf(c, style),
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    var flat = tp.getPositionForOffset(local).offset;
    tp.dispose();
    final n = HighlightApply.flatText(c).length;
    if (flat >= n) flat = n - 1;
    for (var i = flat; i >= 0; i--) {
      final s = ReadTextBuilder.sourceOffset(c, i);
      if (s >= 0) return s;
    }
    for (var i = flat + 1; i < n; i++) {
      final s = ReadTextBuilder.sourceOffset(c, i);
      if (s >= 0) return s;
    }
    return -1;
  }

  Widget _block(Content c) {
    if (c.isImage) {
      final href = c.lines.isEmpty || c.lines.first.clines.isEmpty ? '' : c.lines.first.clines.first.href;
      return SizedBox(width: width, height: c.height, child: _image(href, c.fit));
    }
    final isTitle = c.lines.isNotEmpty && c.lines.first.paragraphIndex < 0;
    Widget text = Text.rich(
      HighlightApply.span(c, style, color: textColor, decos: decorate?.call(c, chapterIndex) ?? const []),
      textAlign: HighlightApply.alignOf(c, style),
      strutStyle: HighlightApply.strutOf(c, style),
      textScaler: TextScaler.noScaling,
    );
    final lp = onLongPress;
    if (lp != null && !isTitle) {
      text = GestureDetector(
        onLongPressStart: (d) {
          final o = _offsetAt(c, d.localPosition);
          if (o >= 0) lp(chapterIndex, o, d.globalPosition);
        },
        child: text,
      );
    }
    if (isTitle) {
      return Padding(
        padding: EdgeInsets.only(top: style.titleTopMargin, bottom: style.titleBottomMargin),
        child: SizedBox(width: width, child: text),
      );
    }
    return SizedBox(width: width, child: text);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < page.contents.length; i++) {
      if (i > 0) children.add(SizedBox(height: style.paragraphSpacing));
      children.add(_block(page.contents[i]));
    }
    final col = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
    if (page.iscentos) return SizedBox(width: width, child: Center(child: col));
    return SizedBox(width: width, child: col);
  }
}

/// The header or footer line.
class StatusLine extends StatelessWidget {
  final Widget? left;
  final Widget? right;
  final double leftMargin;
  final double rightMargin;
  final double height;

  const StatusLine({super.key, this.left, this.right, required this.leftMargin, required this.rightMargin, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(left: leftMargin, right: rightMargin),
        child: Row(
          children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: left ?? const SizedBox())),
            ?right,
          ],
        ),
      ),
    );
  }
}

class ContentPage extends StatelessWidget {
  final MyPage page;
  final ReadLayoutStyle style;
  final ReadSetting setting;
  final ReadConfig config;
  final double bookProgress;
  final EdgeInsets safe;
  final BlockDecorator? decorate;
  final TextLongPress? onLongPress;

  /// Draws the background (false when a parent already paints it, e.g. scroll mode).
  final bool paintBackground;

  const ContentPage({
    super.key,
    required this.page,
    required this.style,
    required this.setting,
    required this.config,
    required this.safe,
    this.bookProgress = 0,
    this.decorate,
    this.onLongPress,
    this.paintBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final pad = style.padding;
      final w = size.width - pad.horizontal;
      final colW = style.columns == 2 ? (w - style.columnGap) / 2 : w;
      final dim = config.textColor.withValues(alpha: 0.55);
      final small = TextStyle(fontSize: setting.headerFooterFontSize.toDouble(), color: dim, height: 1.2);
      final top = setting.safeTop >= 0 ? setting.safeTop.toDouble() : safe.top;
      final bottom = setting.safeBottom >= 0 ? setting.safeBottom.toDouble() : safe.bottom;
      final body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageBody(page: page.text, style: style, textColor: config.textColor, width: colW, chapterIndex: page.currentChapterIndex, decorate: decorate, onLongPress: onLongPress),
          if (style.columns == 2) ...[
            SizedBox(width: style.columnGap),
            if (page.text2 != null)
              PageBody(page: page.text2!, style: style, textColor: config.textColor, width: colW, chapterIndex: page.currentChapterIndex, decorate: decorate, onLongPress: onLongPress),
          ],
        ],
      );
      return Container(
        decoration: paintBackground ? config.decoration : null,
        child: Stack(
          children: [
            if (setting.showTop)
              Positioned(
                left: 0,
                right: 0,
                top: top,
                child: StatusLine(
                  height: setting.headerHeight,
                  leftMargin: setting.headerLeftMargin.toDouble(),
                  rightMargin: setting.headerRightMargin.toDouble(),
                  left: Text(page.isFirstPageOfChapter && !setting.hidetitle ? '' : page.chapterName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                ),
              ),
            Positioned(
              left: pad.left,
              top: pad.top,
              right: pad.right,
              bottom: pad.bottom,
              child: ClipRect(child: OverflowBox(alignment: Alignment.topLeft, maxHeight: double.infinity, child: body)),
            ),
            if (setting.showBottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: bottom,
                child: StatusLine(
                  height: setting.footerHeight,
                  leftMargin: setting.footerLeftMargin.toDouble(),
                  rightMargin: setting.footerRightMargin.toDouble(),
                  left: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(clockText(), style: small),
                    const SizedBox(width: 6),
                    BatteryIcon(color: dim, height: setting.headerFooterFontSize * 0.8),
                  ]),
                  right: Text(
                    progressText(setting.showProgress, pageNum: page.pageNum, totalPage: page.totalPage, bookProgress: bookProgress),
                    style: small,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
