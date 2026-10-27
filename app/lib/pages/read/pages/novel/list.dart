// pages/read/pages/novel/list.dart — the scroll-mode reader ("上下滚动"): the page bodies of the loaded chapters one below the other,
// with a fixed header (chapter title) and footer (time, progress). Original `_ListPageState` (41 KB, "奇怪了没移动对previous"); the list
// itself is `widget/read/list.dart` (`ReadListPage`) driven by `ReadListController`.
import 'package:flutter/material.dart';

import '../../../../read/setting/read_layout_style.dart';
import '../../../../read/setting/read_setting.dart';
import '../../../../read/util/list_content.dart';
import '../../../../read/util/listcontroller.dart';
import '../../../../widget/read/list.dart';
import 'content.dart';
import 'views/battery_painter.dart';

class ListPage extends StatelessWidget {
  final ReadListController controller;
  final ReadSetting setting;
  final ReadLayoutStyle style;
  final ReadConfig config;
  final EdgeInsets safe;
  final String chapterTitle;
  final int pageNum;
  final int totalPage;
  final double bookProgress;
  final BlockDecorator? decorate;
  final TextLongPress? onLongPress;
  final void Function(Offset local, Size size) onTap;
  final void Function(ListContent top) onTopChanged;
  final void Function(int direction) onEdge;

  const ListPage({
    super.key,
    required this.controller,
    required this.setting,
    required this.style,
    required this.config,
    required this.safe,
    required this.chapterTitle,
    required this.pageNum,
    required this.totalPage,
    required this.bookProgress,
    required this.onTap,
    required this.onTopChanged,
    required this.onEdge,
    this.decorate,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final pad = style.padding;
    final dim = config.textColor.withValues(alpha: 0.55);
    final small = TextStyle(fontSize: setting.headerFooterFontSize.toDouble(), color: dim, height: 1.2);
    final top = setting.safeTop >= 0 ? setting.safeTop.toDouble() : safe.top;
    final bottom = setting.safeBottom >= 0 ? setting.safeBottom.toDouble() : safe.bottom;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth - pad.horizontal;
      final colW = style.columns == 2 ? (w - style.columnGap) / 2 : w;
      return Stack(
        children: [
          Positioned(
            left: pad.left,
            right: pad.right,
            top: pad.top,
            bottom: pad.bottom,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => onTap(d.localPosition + Offset(pad.left, pad.top), box.biggest),
              child: ReadListPage(
                controller: controller,
                onTopChanged: onTopChanged,
                onEdge: onEdge,
                itemBuilder: (item) => PageBody(
                  page: item.page,
                  style: style,
                  textColor: config.textColor,
                  width: colW,
                  chapterIndex: item.chapterIndex,
                  decorate: decorate,
                  onLongPress: onLongPress,
                ),
              ),
            ),
          ),
          if (setting.showTop)
            Positioned(
              left: 0,
              right: 0,
              top: top,
              child: StatusLine(
                height: setting.headerHeight,
                leftMargin: setting.headerLeftMargin.toDouble(),
                rightMargin: setting.headerRightMargin.toDouble(),
                left: Text(chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
              ),
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
                right: Text(progressText(setting.showProgress, pageNum: pageNum, totalPage: totalPage, bookProgress: bookProgress), style: small),
              ),
            ),
        ],
      );
    });
  }
}
