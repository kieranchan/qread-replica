// pages/read/reader_routes.dart — the reader area's entry points for the lead's navigation wiring (not a file of the original).
//
//   Nav.openReader = ReadPage.open;
//   final prev = Nav.openNamed;
//   Nav.openNamed = (context, name, {arguments}) => ReaderRoutes.open(context, name, arguments: arguments) ?? prev(context, name, arguments: arguments);
import 'package:flutter/material.dart';

import '../../models/book.dart';
import '../highlight/highlight_rule_setting.dart';
import '../image/gallery_viewer_page.dart';
import '../image/image_look_page.dart';
import '../replace/replace_rule_setting.dart';
import '../setting/read_setting_page.dart';
import '../txtrule/txt_rule_setting.dart';
import '../video/video_player_page.dart';
import 'read_page.dart';

abstract class ReaderRoutes {
  /// Route names (the original's file stems) this area handles.
  static const List<String> names = [
    'read_page',
    'txtrule_page',
    'txt_rule_setting',
    'replace_page',
    'replace_rule_setting',
    'highlight_page',
    'highlight_rule_setting',
    'read_setting_page',
    'gallery_viewer_page',
    'image_look_page',
    'video_player_page',
  ];

  /// The page for [name], or null when the name is not handled here. Arguments: `read_page` a [Book]; `gallery_viewer_page` a
  /// `List<String>` or `{images, index}`; `image_look_page` a String; `video_player_page` a String url or `{url, title}`.
  static Widget? pageFor(String name, {Object? arguments}) {
    switch (name) {
      case 'read_page':
        return arguments is Book ? ReadPage(book: arguments) : null;
      case 'txtrule_page':
      case 'txt_rule_setting':
        return const TxtRuleSetting();
      case 'replace_page':
      case 'replace_rule_setting':
        return const ReplaceRuleSetting();
      case 'highlight_page':
      case 'highlight_rule_setting':
        return const HighlightRuleSetting();
      case 'read_setting_page':
        return const ReadSettingPage();
      case 'gallery_viewer_page':
        if (arguments is List) return GalleryViewerPage(images: [for (final e in arguments) '$e']);
        if (arguments is Map) {
          return GalleryViewerPage(images: [for (final e in (arguments['images'] as List? ?? const [])) '$e'], initialIndex: (arguments['index'] as int?) ?? 0);
        }
        return null;
      case 'image_look_page':
        return arguments is String ? ImageLookPage(src: arguments) : null;
      case 'video_player_page':
        if (arguments is String) return VideoPlayerPage(url: arguments);
        if (arguments is Map) return VideoPlayerPage(url: '${arguments['url'] ?? ''}', title: '${arguments['title'] ?? ''}');
        return null;
    }
    return null;
  }

  /// Pushes the page for [name]; null when the name is not handled here (the caller falls back to its own handler).
  static Future<void>? open(BuildContext context, String name, {Object? arguments}) {
    final page = pageFor(name, arguments: arguments);
    if (page == null) return null;
    return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}
