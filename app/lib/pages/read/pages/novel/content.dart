// pages/read/pages/novel/content.dart — one screen of the novel reader: background, header line, the laid-out text of a [MyPage]
// (one or two columns), footer line (time, battery, progress).
//
// Original: `ContentPageState` (93 KB; strings 我的 / 内容加载中... / 充电中 / 分页中). This port draws each content block with a `Text.rich`
// that uses the exact styles and strut of the layout engine, so line breaks match the pagination and the text is selectable.
// Header and footer ([ReaderStatusBar]) are the original's three slots each (`customHeaderLeft` ... `customFooterRight`, items
// 时间 · 内置百分比电池 · 外置百分比电池 · 章节进度 · 全文进度 · 标题 · 书名; defaults 标题 | | and 时间 | 章节进度 | 外置百分比电池), text size
// `headerFooterFontSize` (0 -> 12, 8..25, 0x6342b8), with the `fen` divider lines (分割线). Battery level / charging ("充电中", "level" + "%",
// 0x6339a0) come from [ReaderBattery].
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../read/model/mypage.dart';
import '../../../../read/model/page.dart';
import '../../../../read/pdf/pdf_file.dart';
import '../../../../read/setting/read_layout_style.dart';
import '../../../../read/setting/read_setting.dart';
import '../../../../read/util/content_painter.dart';
import '../../../../read/util/highlight_apply.dart';
import '../../../../read/util/highlight_bg.dart';
import 'views/battery_painter.dart';

typedef BlockDecorator = List<TextDeco> Function(Content block, int chapterIndex);

/// Long press on the text: chapter index, chapter-text offset under the finger, global position.
typedef TextLongPress = void Function(int chapterIndex, int offset, Offset globalPosition);

/// Slot item 章节进度 (0x632f5c, item 3): `<page>/<pages>`, `分页中` while the chapter is still being paginated (no page count yet).
String chapterProgressText(int pageNum, int totalPage) => totalPage <= 0 ? '分页中' : '$pageNum/$totalPage';

/// Slot item 全文进度 (0x632f5c, item 4): the book percent with two decimals.
String bookProgressText(double bookProgress) => '${(bookProgress * 100).clamp(0, 100).toStringAsFixed(2)}%';

/// The `showProgress` text (显示进度: 不显示 / 章节进度 / 全文进度 / 章节进度和全文进度). The original reads `showProgress` only in the
/// battery items (0x6344a8: 0 = the battery alone, otherwise this text stands before it); the progress slot items ignore it.
String progressText(int mode, {required int pageNum, required int totalPage, required double bookProgress}) {
  final chapter = chapterProgressText(pageNum, totalPage);
  final book = bookProgressText(bookProgress);
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
    if (href.startsWith(PdfFile.scheme)) return PdfPageView(src: href, fit: fit);
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
    final decos = decorate?.call(c, chapterIndex) ?? const <TextDeco>[];
    final span = HighlightApply.span(c, style, color: textColor, decos: decos);
    final align = HighlightApply.alignOf(c, style);
    final strut = HighlightApply.strutOf(c, style);
    Widget text = Text.rich(span, textAlign: align, strutStyle: strut, textScaler: TextScaler.noScaling);
    final images = [for (final d in decos) if (d.bgImage != null) (d.start, d.end, d.bgImage!)];
    if (images.isNotEmpty) {
      // the rules' background images, nine-patch behind their ranges
      text = CustomPaint(painter: NinePatchPainter(span: span, align: align, strut: strut, ranges: images), child: text);
    }
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

/// The header or footer of a reader screen: the three custom slots of the original, a divider line (`fen`).
class ReaderStatusBar extends StatelessWidget {
  final ReadSetting setting;
  final bool header;
  final Color color;
  final String title;
  final String bookName;
  final int pageNum;
  final int totalPage;
  final double bookProgress;

  const ReaderStatusBar({
    super.key,
    required this.setting,
    required this.header,
    required this.color,
    required this.title,
    this.bookName = '',
    this.pageNum = 0,
    this.totalPage = 0,
    this.bookProgress = 0,
  });

  Widget? _item(int id, TextStyle style) {
    final fs = style.fontSize ?? 12;
    switch (id) {
      case SlotItem.time:
        return Text(clockText(), style: style);
      case SlotItem.batteryInside:
      case SlotItem.batteryOutside:
        final battery = id == SlotItem.batteryInside
            ? BatteryIcon(color: style.color ?? color, height: fs * 0.9, percentInside: true)
            : BatteryIcon(color: style.color ?? color, height: fs * 0.8, percentText: style);
        final t = progressText(setting.showProgress, pageNum: pageNum, totalPage: totalPage, bookProgress: bookProgress);
        if (t.isEmpty) return battery;
        return Row(mainAxisSize: MainAxisSize.min, children: [Text(t, style: style), const SizedBox(width: 4), battery]);
      case SlotItem.chapterProgress:
        return Text(chapterProgressText(pageNum, totalPage), style: style);
      case SlotItem.bookProgress:
        return Text(bookProgressText(bookProgress), style: style);
      case SlotItem.title:
        return Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
      case SlotItem.bookName:
        return Text(bookName, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    return null;
  }

  Widget _slot(String key, TextStyle style, MainAxisAlignment align) {
    final items = <Widget>[];
    for (final id in setting.slots[key] ?? const <int>[]) {
      final w = _item(id, style);
      if (w != null) items.add(w);
    }
    return Row(
      mainAxisAlignment: align,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          items[i] is Text ? Flexible(child: items[i]) : items[i],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: setting.statusFontSize, color: color, height: 1.2);
    final prefix = header ? 'customHeader' : 'customFooter';
    final divider = setting.fen == DividerMode.both || setting.fen == (header ? DividerMode.header : DividerMode.footer);
    final left = (header ? setting.headerLeftMargin : setting.footerLeftMargin).toDouble();
    final right = (header ? setting.headerRightMargin : setting.footerRightMargin).toDouble();
    final line = Container(height: 0.5, margin: EdgeInsets.only(left: left, right: right), color: color.withValues(alpha: 0.4));
    return SizedBox(
      height: header ? setting.headerHeight : setting.footerHeight,
      child: Column(
        children: [
          if (divider && !header) line,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: left, right: right),
              child: Row(
                children: [
                  Expanded(child: _slot('${prefix}Left', style, MainAxisAlignment.start)),
                  Expanded(child: _slot('${prefix}Center', style, MainAxisAlignment.center)),
                  Expanded(child: _slot('${prefix}Right', style, MainAxisAlignment.end)),
                ],
              ),
            ),
          ),
          if (divider && header) line,
        ],
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
  final String bookName;

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
    this.bookName = '',
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
                child: ReaderStatusBar(
                  setting: setting,
                  header: true,
                  color: dim,
                  title: page.isFirstPageOfChapter && !setting.hidetitle ? '' : page.chapterName,
                  bookName: bookName,
                  pageNum: page.pageNum,
                  totalPage: page.totalPage,
                  bookProgress: bookProgress,
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
                child: ReaderStatusBar(
                  setting: setting,
                  header: false,
                  color: dim,
                  title: page.chapterName,
                  bookName: bookName,
                  pageNum: page.pageNum,
                  totalPage: page.totalPage,
                  bookProgress: bookProgress,
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// A PDF page (`pdf:<file>,<page>`), rendered once and then read from its cached PNG.
class PdfPageView extends StatelessWidget {
  final String src;
  final BoxFit fit;
  const PdfPageView({super.key, required this.src, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    final s = PdfFile.parseSrc(src);
    if (s == null) return const SizedBox();
    return FutureBuilder<File>(
      future: PdfFile.pageFile(s.$1, s.$2),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) {
          return snap.hasError ? Center(child: Text('渲染第 ${s.$2 + 1} 页失败')) : const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return Image.file(f, fit: fit, errorBuilder: (_, _, _) => const SizedBox());
      },
    );
  }
}
